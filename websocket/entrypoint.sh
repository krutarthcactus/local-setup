#!/usr/bin/env bash
# =============================================================================
# SCR Platform — scr-websocket (Node.js + TypeScript + Socket.io)
# =============================================================================
# Responsibilities:
#   1. Wire up .env (copied from .env.sample if the repo has one)
#   2. npm install (idempotent)
#   3. Hand off to `npm run dev`
# =============================================================================

set -e

APP_DIR=/app
cd "$APP_DIR"

log() { echo "[websocket-entrypoint] $*"; }

# -----------------------------------------------------------------------------
# 1. Sanity check — scr-websocket is expected to be cloned from GitHub into
#    WEBSOCKET_PATH with its package.json already committed. We no longer
#    scaffold a fresh Node.js + Socket.io project here.
# -----------------------------------------------------------------------------
if [ ! -f "$APP_DIR/package.json" ]; then
    log "ERROR: no package.json found in $APP_DIR."
    log "Make sure WEBSOCKET_PATH points at a checked-out scr-websocket repo."
    exec "$@"
fi

# -----------------------------------------------------------------------------
# 2. Wire up .env — copy .env.sample (committed in the repo) if present,
#    otherwise fall back to the inline defaults below.
# -----------------------------------------------------------------------------
ENV_FILE="$APP_DIR/.env"
ENV_SAMPLE="$APP_DIR/.env.sample"
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$ENV_SAMPLE" ]; then
        log "No .env found — copying .env.sample..."
        cp "$ENV_SAMPLE" "$ENV_FILE"
    else
        log "No .env or .env.sample found — creating .env with defaults..."
        cat > "$ENV_FILE" <<EOF
NODE_ENV=development
WEBSOCKET_PORT=3000
WEBSOCKET_HOST=0.0.0.0
EOF
    fi
fi

# =============================================================================
# 3. Install dependencies (named volume persists node_modules/ across
#    restarts)
# =============================================================================
if [ ! -x "$APP_DIR/node_modules/.bin/tsx" ]; then
    log "tsx binary missing (no or incomplete node_modules/) — running npm install..."
    npm install
fi

# =============================================================================
# 4. Hand off to the real process
# =============================================================================
log "Starting: $*"
exec "$@"
