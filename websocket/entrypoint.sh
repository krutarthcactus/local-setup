#!/usr/bin/env bash
# =============================================================================
# SCR Platform — scr-websocket (Node.js + TypeScript + Socket.io)
# =============================================================================
# Responsibilities:
#   1. Bootstrap a fresh Node.js + TypeScript + Socket.io server into /app if it's
#      empty (only when AUTO_BOOTSTRAP=true)
#   2. npm install (idempotent)
#   3. Hand off to `npm run dev`
# =============================================================================

set -e

APP_DIR=/app
cd "$APP_DIR"

log() { echo "[websocket-entrypoint] $*"; }

# -----------------------------------------------------------------------------
# 1. Bootstrap fresh Node.js + TypeScript project if missing
# -----------------------------------------------------------------------------
if [ "${AUTO_BOOTSTRAP:-true}" = "true" ] && [ ! -f "$APP_DIR/package.json" ]; then
    log "No websocket app found in $APP_DIR — bootstrapping Node.js 24 + TypeScript + Socket.io..."

    # Create package.json
    cat > "$APP_DIR/package.json" <<EOF
{
  "name": "scr-websocket",
  "version": "1.0.0",
  "description": "SCR Platform WebSocket Server - Node.js 24 + TypeScript + Socket.io",
  "main": "dist/index.js",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "lint": "eslint src",
    "type-check": "tsc --noEmit"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "dependencies": {
    "socket.io": "^4.7.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "@types/cors": "^2.8.17",
    "typescript": "^5.3.3",
    "tsx": "^4.6.2",
    "@typescript-eslint/eslint-plugin": "^6.13.2",
    "@typescript-eslint/parser": "^6.13.2",
    "eslint": "^8.55.0"
  }
}
EOF
    log "package.json created."

    # Create TypeScript config
    cat > "$APP_DIR/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020"],
    "moduleResolution": "node",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
EOF
    log "tsconfig.json created."

    # Create .env
    cat > "$APP_DIR/.env" <<EOF
NODE_ENV=development
WEBSOCKET_PORT=3000
WEBSOCKET_HOST=0.0.0.0
EOF
    log ".env created."

    # Create src directory and index.ts
    mkdir -p "$APP_DIR/src"
    cat > "$APP_DIR/src/index.ts" <<'EOF'
import { createServer } from "http";
import { Server } from "socket.io";
import cors from "cors";
import dotenv from "dotenv";

// Load environment variables
dotenv.config();

const PORT = parseInt(process.env.WEBSOCKET_PORT || "3000", 10);
const HOST = process.env.WEBSOCKET_HOST || "0.0.0.0";

// Create HTTP server
const httpServer = createServer();

// Initialize Socket.io with CORS
const io = new Server(httpServer, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },
  transports: ["websocket", "polling"],
});

// Socket.io connection handler
io.on("connection", (socket) => {
  console.log(`[Socket.io] Client connected: ${socket.id}`);

  // Handle incoming messages
  socket.on("message", (data) => {
    console.log(`[Socket.io] Message from ${socket.id}:`, data);
    // Broadcast to all clients
    io.emit("message", {
      from: socket.id,
      data,
      timestamp: new Date().toISOString(),
    });
  });

  // Handle custom events
  socket.on("chat", (message) => {
    console.log(`[Socket.io] Chat from ${socket.id}:`, message);
    io.emit("chat", {
      userId: socket.id,
      message,
      timestamp: new Date().toISOString(),
    });
  });

  // Handle disconnection
  socket.on("disconnect", () => {
    console.log(`[Socket.io] Client disconnected: ${socket.id}`);
  });

  // Handle errors
  socket.on("error", (error) => {
    console.error(`[Socket.io] Error from ${socket.id}:`, error);
  });
});

// Start server
httpServer.listen(PORT, HOST, () => {
  console.log(
    `[WebSocket Server] Running on ws://${HOST}:${PORT}`
  );
  console.log(`[Environment] NODE_ENV=${process.env.NODE_ENV}`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("[Server] SIGTERM signal received: closing HTTP server");
  httpServer.close(() => {
    console.log("[Server] HTTP server closed");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("[Server] SIGINT signal received: closing HTTP server");
  httpServer.close(() => {
    console.log("[Server] HTTP server closed");
    process.exit(0);
  });
});
EOF
    log "TypeScript + Socket.io server scaffold created."
fi

if [ ! -f "$APP_DIR/package.json" ]; then
    log "ERROR: no package.json found and AUTO_BOOTSTRAP is disabled."
    log "Either set AUTO_BOOTSTRAP=true or create the Node.js app manually at ${WEBSOCKET_PATH}."
    exec "$@"
fi

# Create .gitignore if not exists
if [ ! -f "$APP_DIR/.gitignore" ]; then
    cat > "$APP_DIR/.gitignore" <<EOF
node_modules/
dist/
.env.local
.DS_Store
*.log
npm-debug.log*
.idea/
.vscode/
EOF
fi

# Create .eslintrc.json if not exists
if [ ! -f "$APP_DIR/.eslintrc.json" ]; then
    cat > "$APP_DIR/.eslintrc.json" <<EOF
{
  "env": {
    "node": true,
    "es2020": true
  },
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended"
  ],
  "parser": "@typescript-eslint/parser",
  "parserOptions": {
    "ecmaVersion": "latest",
    "sourceType": "module"
  },
  "rules": {
    "@typescript-eslint/no-unused-vars": ["error", { "argsIgnorePattern": "^_" }]
  }
}
EOF
fi

# =============================================================================
# Install dependencies (named volume persists node_modules/ across restarts)
# =============================================================================
if [ ! -x "$APP_DIR/node_modules/.bin/tsx" ]; then
    log "tsx binary missing (no or incomplete node_modules/) — running npm install..."
    npm install
fi

# =============================================================================
# Hand off to the real process
# =============================================================================
log "Starting: $*"
exec "$@"
