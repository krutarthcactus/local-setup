# SCR Platform — Local Docker Development Environment

One command (`make up` / `docker compose up`) gives you a full working stack —
Laravel 13, Next.js 16, PostgreSQL, Redis, real-time WebSockets, and a local
mail catcher — all wired together and reachable at a single URL:

**http://local.scr.com/**

No ports in the browser bar. `/` serves the  Next.js app, `/api/*` serves the
Laravel API.

---

## What's in the stack

| Service    | What it is                                   | Reachable at |
|------------|-----------------------------------------------|--------------|
| `nginx`    | Reverse proxy — the only port published to your host | `http://local.scr.com/` |
| `frontend` | Next.js 16 dev server (HMR enabled)           | via nginx `/` |
| `backend`  | Laravel 13 on PHP 8.4-fpm                     | via nginx `/api/*` |
| `queue`    | `php artisan queue:work` — processes reminders, reports, ingestion jobs | — |
| `websocket` | Node.js 24 + TypeScript + Socket.io server   | `localhost:3000` |
| `postgres` | PostgreSQL 14 (matches SOW §2.3)              | `localhost:5432` |
| `redis`    | Cache / session / queue driver                | `localhost:6379` |
| `floci`    | AWS S3-compatible storage (all 75 AWS services) | `localhost:4566` |
| `mailpit`  | Catches every outbound email locally — no real SES/Brevo needed | `http://localhost:8025` |

---

## Prerequisites

- Docker Desktop (or compatible engine) with Docker Compose v2+
- The two application repos checked out **as siblings of this `SCR` repo**:
  ```
  ~/development/scr-backend/    (Laravel 13 — can be empty, gets bootstrapped)
  ~/development/scr-frontend/   (Next.js 16 — expects a real checkout, with package.json)
  ~/development/SCR/            (this repo — local-docker/ lives here)
  ```
  If your repos live somewhere else, edit `BACKEND_PATH` / `FRONTEND_PATH` in
  `.env` (paths are relative to this `local-docker/` directory, or use an
  absolute path).

---

## First-time setup

### 1. Point `local.scr.com` at your machine

This one-time step needs `sudo` and is intentionally **not** automated:

```bash
make hosts-add
# or manually:
echo "127.0.0.1 local.scr.com" | sudo tee -a /etc/hosts
```

Verify it worked:

```bash
make hosts-check
```

### 2. Review `.env`

`.env` is already committed with sane local defaults (see `.env.example` for
the full list). The only thing you're likely to change is `BACKEND_PATH` /
`FRONTEND_PATH` / `WEBSOCKET_PATH` if your sibling repos aren't at `~/development/scr-backend`,
`~/development/scr-frontend`, and `~/development/scr-websocket`.

### 3. Clone the application repositories 

Clone the backend, frontend, and websocket repositories as siblings to this local-docker directory:

#### Navigate to your development directory
```bash
cd ~/development
```

#### Clone the backend repository (SSH)
```bash
git clone git@github.com:cactuscommunications/scr-backend.git scr-backend
```

#### Clone the frontend repository (SSH)
```bash
git clone git@github.com:cactuscommunications/scr-frontend.git scr-frontend
```

#### Clone the websocket repository (SSH) - Optional
```bash
git clone git@github.com:cactuscommunications/scr-websocket.git scr-websocket
```

Your final directory structure should look like:
```
~/development/
├── SCR/
│   └── local-docker/    (this repository - already cloned)
├── scr-backend/         (Laravel application)
├── scr-frontend/        (Next.js application)
└── scr-websocket/       (Node.js WebSocket server - optional)
```

### 4. Start the stack

Navigate to the local-docker directory and start the services:

```bash
cd ~/development/SCR/local-docker
make up
# or: docker compose up -d --build
```

**First boot does a lot of work automatically:**
-- If `scr-backend/` is empty → runs `composer create-project laravel/laravel:^13.0`, adds `laravel/sanctum`, generates `.env`, wires DB/Redis/Mail config, generates `APP_KEY`, waits for Postgres, runs migrations.
-- `scr-frontend/` and `scr-websocket/` are expected to already have their `package.json` checked out from GitHub — the entrypoint just copies `.env.sample` → `.env.local` / `.env` if one exists (falling back to built-in defaults otherwise) and runs `npm install`.

This can take **2–5 minutes** the first time (composer/npm installs). Watch progress with:

```bash
make logs
```

### 5. Visit the app

Once containers report healthy:

- **Frontend + API:** http://local.scr.com/
- **API directly:** http://local.scr.com/api/...
- **WebSocket Server:** `ws://localhost:3000` (Node.js + Socket.io)
- **Mailpit (catches all local email):** http://localhost:8025
- **Postgres:** `localhost:5432` (user/db from `.env`, default `scr` / `scr_platform`)
- **Redis:** `localhost:6379`
- **Floci (AWS S3):** `http://localhost:4566` (S3-compatible storage)

---

## Daily use

```bash
make up             # start everything
make down            # stop everything (data/deps persist in named volumes)
make restart         # restart without rebuilding
make logs            # tail all logs
make ps              # see container status
```

### Editing code

Just edit files in `~/development/scr-backend` or `~/development/scr-frontend`
as normal — both are bind-mounted into their containers, so:

- **PHP changes** (routes, controllers, models, etc.) take effect on the very
  next request — no restart needed.
- **Next.js/TS changes** hot-reload in the browser instantly via Next.js HMR.

`vendor/` and `node_modules/` live in **named Docker volumes**, not bind
mounts — this avoids native-binary mismatches between your host OS/arch and
the container's Linux environment (a common source of "works on my machine"
bugs with Composer/npm packages that compile native extensions).

### Running artisan / npm commands

```bash
make artisan cmd="make:model Manuscript -mfs"
make artisan cmd="route:list"
make migrate
make migrate-fresh     # ⚠️ drops all tables and re-migrates
make tinker

make npm cmd="install some-package"
```

Or drop into a shell directly:

```bash
make shell-backend
make shell-frontend
make shell-websocket
```

Run websocket-specific commands:

```bash
make npm-websocket cmd="install socket.io-client"
make npm-websocket cmd="run build"
```

### Database & cache access

```bash
make psql        # psql shell into Postgres
make redis-cli    # redis-cli shell
```

### Email testing

Any mail Laravel sends locally (invitations, reminders, password resets —
SOW §3.5) is caught by Mailpit instead of actually being delivered:

```bash
make mailpit      # opens http://localhost:8025 in your browser
```

### AWS S3 / Floci file storage

Floci provides a local AWS S3-compatible storage service, eliminating the need
for a real AWS account during development. Laravel can upload, download, delete,
and manage files using the S3 disk exactly as it would with real AWS S3.

#### Setup

**1. Configure Laravel filesystem** (in `scr-backend/.env`, **not** `local-docker/.env`):

> **Note:** Laravel reads from its own `.env` file in the `scr-backend/` directory. The AWS environment variables in `docker-compose.yml` are for shell/CLI convenience only.

```bash
FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_DEFAULT_REGION=us-east-1

# Private bucket for sensitive files (documents, reports, compliance data)
AWS_BUCKET_PRIVATE=scr-private-bucket

# Public bucket for user-uploaded content (avatars, public files)
AWS_BUCKET_PUBLIC=scr-public-bucket

AWS_ENDPOINT=http://floci:4566
AWS_USE_PATH_STYLE_ENDPOINT=true
```

> **Tip:** Bucket names are configured in `local-docker/.env` and automatically passed to the backend service.

**2. Install AWS SDK** (if not already installed):

```bash
make shell-backend
composer require league/flysystem-aws-s3-v3 "^3.0" --with-all-dependencies
```

**3. Initialize the S3 buckets** (run once after first startup):

```bash
make s3-init
```

This creates two buckets:
- `scr-private-bucket` - For sensitive files (documents, reports, etc.)
- `scr-public-bucket` - For publicly accessible content (user uploads, avatars, etc.)

Buckets persist in the `floci_data` Docker volume.

#### Managing S3 buckets

**List all buckets:**

```bash
make s3-list
```

**Test upload/download/delete:**

```bash
make s3-test      # tests both private and public buckets
```

**List all buckets:**

```bash
make s3-list
```

**View Floci logs:**

```bash
make logs-floci
```

#### Important notes

 The default bucket name is `scr-private-bucket` (configurable via `AWS_BUCKET` in `.env`)
- Floci data persists in a Docker volume, surviving container restarts
- S3 endpoint is accessible from both Laravel containers (`backend` and `queue`)
- For production, simply update the `.env` to use real AWS credentials and remove the `AWS_ENDPOINT` variable

---

## Logs — accessible outside Docker

nginx and php-fpm's own logs are bind-mounted to `local-docker/logs/` on your
host, so you can `tail -f` them directly without `docker exec`:

```bash
tail -f local-docker/logs/nginx/access.log
tail -f local-docker/logs/nginx/error.log
tail -f local-docker/logs/php/fpm-access.log
tail -f local-docker/logs/php/fpm-error.log
```

Laravel's own application log needs no extra plumbing at all: since the
**entire** `scr-backend` repo is bind-mounted into the backend/queue
containers, `storage/logs/laravel.log` is already a normal file on your host
the moment Laravel writes it:

```bash
tail -f ~/development/scr-backend/storage/logs/laravel.log
```

---

## Using the `laravel-scaffold` / `react-component-scaffold` skills

Once the stack is up and `scr-backend` / `scr-frontend` are bootstrapped, the
existing Claude Code skills generate code directly into those repos:

```bash
cd ~/development/scr-backend
/laravel-scaffold --module "UserManagement" --features "sso-login,two-factor-auth,bulk-import,gdpr-deletion" --stream "A"

cd ~/development/scr-frontend
/nextjs-component-scaffold --component "AdminDashboard" --type "dashboard" --features "overview,manuscript-table" --accessibility "wcag-aa"
```

Since both repos are bind-mounted, generated files appear inside the running
containers immediately — refresh the browser or hit the API to see them.

---

## Troubleshooting

**`local.scr.com` doesn't resolve / connection refused**
→ Run `make hosts-check`. If missing, `make hosts-add`. Confirm nginx is
running: `make ps`.

**"Invalid Host header" or blank page from Vite**
→ The entrypoint patches `vite.config.ts` with `allowedHosts` automatically
on first bootstrap. If you already had a `vite.config.ts` before running this
stack, add `local.scr.com` to `server.allowedHosts` manually.

**Composer/npm install seems stuck on first boot**
→ Totally normal for 1–3 minutes depending on connection speed. Watch
`make logs-backend` or `make logs-frontend` for progress.

**Changes to PHP/JS files aren't reflected**
→ Confirm you're editing files inside `~/development/scr-backend` or
`~/development/scr-frontend` (the bind-mounted paths), not somewhere else.
Vite uses polling (`CHOKIDAR_USEPOLLING=true`) for reliable file-watching
across the bind mount, so changes should show up within ~1 second.

**Port 80 already in use**
→ Something else (another local project, system service) is bound to 80.
Either stop it, or change `NGINX_PORT` in `.env` and access via
`http://local.scr.com:<port>/` instead.

**Want to reset everything (fresh DB, fresh deps)**
→ `make fresh` — stops containers, deletes the named volumes (Postgres data,
Redis data, `vendor/`, `node_modules/`), rebuilds, and restarts. Does **not**
touch your source code in `scr-backend`/`scr-frontend`.

**Only want the Docker plumbing, not auto-bootstrap**
→ Set `AUTO_BOOTSTRAP=false` in `.env` before first `make up`, and create the
Laravel/Next.js apps yourself in `BACKEND_PATH` / `FRONTEND_PATH` first.

---

## Directory reference

```
local-docker/
├── docker-compose.yml       # all 9 services, shared network, named volumes
├── .env / .env.example       # paths, ports, credentials (local-only, safe to commit)
├── Makefile                  # `make up`, `make logs`, `make artisan cmd=...`, etc.
├── nginx/
│   ├── Dockerfile
│   └── conf.d/local.scr.com.conf   # the single-domain routing rules
├── php/
│   ├── Dockerfile             # PHP 8.4-fpm + Laravel-required extensions
│   ├── php.ini                 # upload limits, opcache tuned for live-reload
│   ├── fpm-pool.conf            # php-fpm access/error logs → host-visible path
│   └── entrypoint.sh            # bootstrap Laravel 13 if missing, wire .env, migrate
├── node/
│   ├── Dockerfile
│   └── entrypoint.sh           # patch next.config.ts, wire .env.local, npm install
├── websocket/
│   ├── Dockerfile             # Node.js 24 + TypeScript
│   └── entrypoint.sh           # wire .env, npm install
├── postgres/
│   └── init/001-init.sql        # pg_trgm, uuid-ossp, unaccent extensions
├── scripts/
│   ├── s3-init.sh               # creates private and public S3 buckets in Floci
│   └── s3-list.sh               # lists all S3 buckets in Floci
├── logs/                        # host-visible nginx + php-fpm logs
│   ├── nginx/
│   └── php/
```

(Laravel's own `storage/logs/laravel.log` needs no entry here — it's already
on your host inside `scr-backend/`, since that whole repo is bind-mounted.)
