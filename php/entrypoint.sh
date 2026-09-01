#!/usr/bin/env bash
# =============================================================================
# SCR Platform — backend container entrypoint
# =============================================================================
# Responsibilities:
#   1. Bootstrap a fresh Laravel 13 app into /var/www/html if it's empty
#      (only when AUTO_BOOTSTRAP=true)
#   2. composer install (idempotent — skipped if vendor/ already populated
#      and composer.lock hasn't changed)
#   3. Wire up .env to point at the postgres/redis/mailpit services
#   4. Wait for PostgreSQL to accept connections
#   5. Run migrations (only from the primary "php-fpm" container, to avoid
#      the queue sidecar racing on first boot)
#   6. Hand off to the real process (php-fpm or queue:work)
# =============================================================================

set -e

APP_DIR=/var/www/html
cd "$APP_DIR"

log() { echo "[entrypoint] $*scr"; }

# -----------------------------------------------------------------------------
# 0. Single-flight lock
# -----------------------------------------------------------------------------
# backend and queue both bind-mount the SAME code directory and all
# start at roughly the same time on every `docker compose up`. Without a
# lock, they'd race on `composer create-project` / `composer install` /
# writing .env simultaneously and corrupt each other's work (this is not
# hypothetical — it reproduces every time on a clean first boot). Only the
# first container to grab the lock does setup; the others wait for it to
# finish, then all proceed independently to step 4 onward.
LOCK_DIR="$APP_DIR/.docker-bootstrap.lock"
DONE_FILE="$APP_DIR/.docker-bootstrap.done"
LOCK_TIMEOUT=600 # seconds

if [ ! -f "$DONE_FILE" ]; then
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        # Always release the lock on exit — including on error (`set -e`
        # aborting the script) — so a transient failure (e.g. a network
        # blip mid `composer create-project`) doesn't leave the lock dir
        # behind and permanently deadlock every future boot. On failure,
        # DONE_FILE is simply never created, so the next container to boot
        # retries setup from scratch.
        trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

        log "Acquired setup lock — this container will run bootstrap/composer install/.env wiring."

        # -------------------------------------------------------------------
        # 1. Bootstrap fresh Laravel app if missing
        # -------------------------------------------------------------------
        if [ "${AUTO_BOOTSTRAP:-true}" = "true" ] && [ ! -f "$APP_DIR/artisan" ]; then
            log "No Laravel app found in $APP_DIR — bootstrapping Laravel 13..."
            rm -rf "$APP_DIR/tmp-install"
            composer create-project laravel/laravel:^13.0 tmp-install --prefer-dist --no-interaction
            # `mv` fails here: composer's own post-create hook already builds
            # tmp-install/storage and tmp-install/vendor, and `mv` tries to
            # atomically rename them on top of $APP_DIR/storage and
            # $APP_DIR/vendor — which already exist as Docker bind/volume
            # mount points (declared in docker-compose.yml) and can't be
            # replaced as a directory object. `cp -a` instead copies file-by-
            # file INTO the existing directories, which works fine with an
            # active mount point underneath.
            shopt -s dotglob
            cp -a tmp-install/. "$APP_DIR"/
            rm -rf tmp-install
            shopt -u dotglob
            log "Laravel 13 scaffold created."

            # Add packages required by the SOW tech stack (§2.1) that
            # aren't in the default skeleton: Sanctum (API auth).
            log "Installing laravel/sanctum..."
            composer require laravel/sanctum --no-interaction
        fi

        if [ ! -f "$APP_DIR/artisan" ]; then
            log "ERROR: no artisan file found and AUTO_BOOTSTRAP is disabled."
            log "Either set AUTO_BOOTSTRAP=true or create the Laravel app manually at ${BACKEND_PATH}."
            rmdir "$LOCK_DIR"
            exec "$@"
        fi

        # -------------------------------------------------------------------
        # 2. Composer dependencies (named volume persists vendor/ across
        #    restarts)
        # -------------------------------------------------------------------
        if [ ! -f "$APP_DIR/vendor/autoload.php" ]; then
            log "vendor/ missing — running composer install..."
            composer install --no-interaction --prefer-dist
        fi

        # -------------------------------------------------------------------
        # 3. Environment wiring
        # -------------------------------------------------------------------
        if [ ! -f "$APP_DIR/.env" ]; then
            log "No .env found — copying .env.example..."
            cp .env.example .env
        fi

        touch "$DONE_FILE"
        rmdir "$LOCK_DIR"
        log "Setup complete — lock released."
    else
        log "Another container is running setup — waiting for it to finish..."
        waited=0
        until [ -f "$DONE_FILE" ]; do
            sleep 1
            waited=$((waited + 1))
            if [ "$waited" -ge "$LOCK_TIMEOUT" ]; then
                log "ERROR: timed out after ${LOCK_TIMEOUT}s waiting for setup to finish."
                log "Check 'docker compose logs backend' for errors, then 'make fresh' to retry."
                exit 1
            fi
        done
        log "Setup finished by another container — continuing."
    fi
fi

if [ ! -f "$APP_DIR/artisan" ]; then
    log "ERROR: no artisan file found and AUTO_BOOTSTRAP is disabled."
    log "Either set AUTO_BOOTSTRAP=true or create the Laravel app manually at ${SCR_BACKEND_PATH}."
    exec "$@"
fi

# Ensure .env and APP_KEY are set (runs for all containers, including cloned projects)
if [ ! -f "$APP_DIR/.env" ]; then
    log "No .env found — copying .env.example..."
    cp .env.example .env
fi

if ! grep -q "^APP_KEY=base64" .env 2>/dev/null; then
    log "Generating APP_KEY..."
    php artisan key:generate --ansi --force
fi

# -----------------------------------------------------------------------------
# 4. Wait for PostgreSQL
# -----------------------------------------------------------------------------
log "Waiting for PostgreSQL at postgres:5432..."
until php -r "
    try {
        new PDO('pgsql:host=postgres;port=5432;dbname=${POSTGRES_DB:-scr_platform}', '${POSTGRES_USER:-scr}', '${POSTGRES_PASSWORD:-scr_local_password}');
        exit(0);
    } catch (\Exception \$e) {
        exit(1);
    }
"; do
    sleep 1
done
log "PostgreSQL is ready."

# -----------------------------------------------------------------------------
# 5. Migrations — same single-flight pattern as step 0. Whichever of
#    backend/queue gets here FIRST runs the migration; the others
#    wait for it, so queue:work never races ahead of a DB schema that isn't
#    ready yet.
# -----------------------------------------------------------------------------
MIGRATE_LOCK_DIR="$APP_DIR/.docker-migrate.lock"
MIGRATE_DONE_FILE="$APP_DIR/.docker-migrate.done"

if mkdir "$MIGRATE_LOCK_DIR" 2>/dev/null; then
    log "Running migrations..."
    php artisan migrate --force || log "Migration failed or nothing to migrate yet — continuing."

    log "Ensuring storage symlink exists..."
    php artisan storage:link || true

    touch "$MIGRATE_DONE_FILE"
    rmdir "$MIGRATE_LOCK_DIR"
else
    log "Another container is running migrations — waiting for it to finish..."
    waited=0
    until [ -f "$MIGRATE_DONE_FILE" ]; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$LOCK_TIMEOUT" ]; then
            log "ERROR: timed out after ${LOCK_TIMEOUT}s waiting for migrations."
            exit 1
        fi
    done
    log "Migrations finished by another container — continuing."
fi

# -----------------------------------------------------------------------------
# 6. Hand off to the real process
# -----------------------------------------------------------------------------
log "Starting: $*"
exec "$@"
