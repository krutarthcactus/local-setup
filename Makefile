.DEFAULT_GOAL := help
.PHONY: help up down restart build fresh logs logs-nginx logs-backend logs-frontend logs-queue \
        logs-websocket logs-floci ps shell-backend shell-frontend shell-websocket artisan npm npm-websocket migrate migrate-fresh \
        tinker mailpit psql redis-cli hosts-check hosts-add s3-init s3-list s3-test up-only-websocket down-only-websocket


# =============================================================================
# Load environment variables from .env file
# =============================================================================
ifneq ("$(wildcard .env)","")
include .env
export $(shell sed 's/=.*//' .env)
endif

# =============================================================================
# SCR Platform — local Docker convenience commands
# =============================================================================

help: ## Show this help
	@echo "SCR Platform — local Docker commands"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Build and start the full stack (detached)
	docker compose up -d --build
	@echo ""
	@echo "Stack starting. First boot bootstraps Laravel + React — this can take a few minutes."
	@echo "Follow progress with:  make logs"
	@echo "Once ready, visit:      http://local.scr.com/"

down: ## Stop and remove containers (keeps volumes/data)
	docker compose down

restart: ## Restart all containers without rebuilding
	docker compose restart

build: ## Rebuild all images
	docker compose build

fresh: ## Full reset: stop, remove volumes (DB/deps), rebuild, start
	docker compose down -v
	docker compose up -d --build

logs: ## Tail logs from every container
	docker compose logs -f

make: ## Tail nginx logs
	docker compose logs -f nginx

logs-backend: ## Tail backend (Laravel/php-fpm) logs
	docker compose logs -f backend

logs-frontend: ## Tail frontend (Vite) logs
	docker compose logs -f frontend

logs-queue: ## Tail queue worker logs
	docker compose logs -f queue

logs-websocket: ## Tail websocket (Node.js + Socket.io) logs
	docker compose logs -f websocket

ps: ## Show status of all containers
	docker compose ps

shell-backend: ## Open a shell in the backend container
	docker compose exec backend bash

shell-frontend: ## Open a shell in the frontend container
	docker compose exec frontend bash

shell-websocket: ## Open a shell in the websocket container
	docker compose exec websocket bash

artisan: ## Run an artisan command, e.g. `make artisan cmd="make:model Manuscript"`
	docker compose exec backend php artisan $(cmd)

npm: ## Run an npm command in the frontend, e.g. `make npm cmd="install axios"`
	docker compose exec frontend npm $(cmd)

npm-websocket: ## Run an npm command in the websocket, e.g. `make npm-websocket cmd="install express"`
	docker compose exec websocket npm $(cmd)

migrate: ## Run pending migrations
	docker compose exec backend php artisan migrate

migrate-fresh: ## Drop all tables and re-migrate (DESTRUCTIVE)
	docker compose exec backend php artisan migrate:fresh

tinker: ## Open Laravel Tinker REPL
	docker compose exec backend php artisan tinker

mailpit: ## Open the Mailpit web UI
	@open http://localhost:$${MAILPIT_UI_PORT:-8025} 2>/dev/null || xdg-open http://localhost:$${MAILPIT_UI_PORT:-8025} 2>/dev/null || echo "Open http://localhost:$${MAILPIT_UI_PORT:-8025} manually"

psql: ## Open a psql shell to the local Postgres
	docker compose exec postgres psql -U $${POSTGRES_USER:-scr} -d $${POSTGRES_DB:-scr_platform}

redis-cli: ## Open a redis-cli shell
	docker compose exec redis redis-cli

hosts-check: ## Check whether local.scr.com is mapped in /etc/hosts
	@grep -q "local.scr.com" /etc/hosts && echo "✅ local.scr.com found in /etc/hosts" || echo "❌ local.scr.com NOT found — run: make hosts-add"

hosts-add: ## Add local.scr.com to /etc/hosts (prompts for sudo)
	@grep -q "local.scr.com" /etc/hosts && echo "Already present." || (echo "127.0.0.1 local.scr.com" | sudo tee -a /etc/hosts && echo "✅ Added.")

# =============================================================================
# AWS S3 / Floci management
# =============================================================================

s3-init: ## Create S3 bucket (run once after first startup)
	@echo "Creating S3 bucket..."
	@docker run --rm --network scr-local_scr-local \
		-e AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-test} \
		-e AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY:-test} \
		-e AWS_DEFAULT_REGION=$${AWS_DEFAULT_REGION:-us-east-1} \
		amazon/aws-cli --endpoint-url=http://floci:4566 \
		s3 mb s3://$${AWS_BUCKET:-scr-local-bucket} 2>&1 | grep -v "BucketAlreadyOwnedByYou" || echo "✅ Bucket ready"

s3-list: ## List all S3 buckets
	@docker run --rm --network scr-local_scr-local \
		-e AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-test} \
		-e AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY:-test} \
		-e AWS_DEFAULT_REGION=$${AWS_DEFAULT_REGION:-us-east-1} \
		amazon/aws-cli --endpoint-url=http://floci:4566 s3 ls

s3-test: ## Test S3 upload/download/delete
	@echo "Testing S3 operations..."
	@docker compose exec backend php artisan tinker --execute="Storage::disk('s3')->put('test.txt', 'Hello from SCR Platform!'); echo 'Upload: ✅'; echo Storage::disk('s3')->get('test.txt'); echo '\nDownload: ✅'; Storage::disk('s3')->delete('test.txt'); echo 'Delete: ✅';"

logs-floci: ## Tail Floci (AWS S3) logs
	docker compose logs -f floci

# =============================================================================
# Run only specific services
# =============================================================================
up-only-websocket: ## Start ONLY the websocket service (+ dependencies: none)
	@echo "Starting only the websocket service..."
	docker compose up -d --build websocket
	@echo "✅ Websocket service is running on ws://localhost:3000"

down-only-websocket: ## Stop only the websocket service
	docker compose down websocket