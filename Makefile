
DATE_SUFFIX=${shell date +"%Y%m%d%H%M%S"}
DATAROOT=.
LOG_DIR=./logs
LOG_PID_FILE=./logs/.capture.pid
DBLOG_DIR=./dblogs
DBLOG_PID_FILE=./dblogs/.capture.pid

.PHONY: logs logs-start logs-stop logs-today logs-errors logs-service logs-search logs-rotate logs-status logs-clean logs-cron-install logs-cron-remove logdirs
.PHONY: dblogs dblogs-start dblogs-stop dblogs-today dblogs-errors dblogs-service dblogs-search dblogs-rotate dblogs-status dblogs-clean dblogs-cron-install dblogs-cron-remove dblogdirs
.PHONY: version version-history version-pull version-set rollback rollback-service rollback-to update-safe check-updates ecr-login migrate-versions
.PHONY: setup-autorestart disable-autorestart autorestart-status
.PHONY: start stop restart update

encrypt:
	gpg -c .env
	rm -f .env

logs:
	docker compose logs -f --tail 300

# Log Management - Capture and filter logs
logdirs:
	@mkdir -p $(LOG_DIR)
	@sudo chown -R $$(id -u):$$(id -g) $(LOG_DIR) 2>/dev/null || true

logs-start: logdirs
	@if [ -f $(LOG_PID_FILE) ] && kill -0 $$(cat $(LOG_PID_FILE)) 2>/dev/null; then \
		echo "Log capture already running (PID: $$(cat $(LOG_PID_FILE)))"; \
	else \
		echo "Starting background log capture to $(LOG_DIR)/$$(date +%Y-%m-%d).log"; \
		nohup docker compose logs -f >> $(LOG_DIR)/$$(date +%Y-%m-%d).log 2>&1 & \
		echo $$! > $(LOG_PID_FILE); \
		echo "Log capture started (PID: $$!)"; \
	fi

logs-stop:
	@if [ -f $(LOG_PID_FILE) ] && kill -0 $$(cat $(LOG_PID_FILE)) 2>/dev/null; then \
		kill $$(cat $(LOG_PID_FILE)) && rm -f $(LOG_PID_FILE) && echo "Log capture stopped"; \
	else \
		rm -f $(LOG_PID_FILE); \
		echo "No log capture process running"; \
	fi

logs-today:
	@cat $(LOG_DIR)/$$(date +%Y-%m-%d).log 2>/dev/null || echo "No logs captured today. Run 'make logs-start' first."

logs-errors:
	@grep -i "error\|exception\|fail" $(LOG_DIR)/*.log 2>/dev/null || echo "No errors found in captured logs"

logs-service:
	@if [ -z "$(SERVICE)" ]; then \
		echo "Usage: make logs-service SERVICE=<service-name>"; \
		echo "Example: make logs-service SERVICE=req-router"; \
	else \
		grep "^$(SERVICE)" $(LOG_DIR)/$$(date +%Y-%m-%d).log 2>/dev/null || echo "No logs for $(SERVICE)."; \
	fi

logs-search:
	@if [ -z "$(PATTERN)" ]; then \
		echo "Usage: make logs-search PATTERN='text'"; \
	else \
		grep -i "$(PATTERN)" $(LOG_DIR)/*.log 2>/dev/null || echo "Pattern '$(PATTERN)' not found"; \
	fi

logs-rotate:
	@find $(LOG_DIR) -name "*.log" -mtime +3 -exec gzip {} \; 2>/dev/null || true
	@find $(LOG_DIR) -name "*.log.gz" -mtime +7 -delete 2>/dev/null || true
	@echo "Log rotation complete (compressed >3 days, deleted >7 days)"

logs-status:
	@echo "Log directory: $(LOG_DIR)"
	@du -sh $(LOG_DIR) 2>/dev/null || echo "No logs yet"
	@echo ""
	@ls -lh $(LOG_DIR)/ 2>/dev/null || echo "No log files"

logs-clean:
	@read -p "Delete all captured logs? [y/N] " confirm && \
	[ "$$confirm" = "y" ] && rm -rf $(LOG_DIR)/* && echo "Logs deleted" || echo "Cancelled"

logs-cron-install:
	@DKAPP_DIR=$$(pwd) && \
	(crontab -l 2>/dev/null | grep -v "dkapp.*logs-rotate"; \
	echo "0 0 * * * cd $$DKAPP_DIR && make logs-rotate >> $$DKAPP_DIR/logs/cron.log 2>&1") | crontab - && \
	echo "Cron job installed: daily log rotation at midnight" && \
	echo "View with: crontab -l"

logs-cron-remove:
	@crontab -l 2>/dev/null | grep -v "dkapp.*logs-rotate" | crontab - && \
	echo "Cron job removed"

# ==============================================
# DATABASE LOG MANAGEMENT
# ==============================================

dblogdirs:
	@mkdir -p $(DBLOG_DIR)
	@sudo chown -R $$(id -u):$$(id -g) $(DBLOG_DIR) 2>/dev/null || true

dblogs-start: dblogdirs
	@if [ -f $(DBLOG_PID_FILE) ] && kill -0 $$(cat $(DBLOG_PID_FILE)) 2>/dev/null; then \
		echo "DB log capture already running (PID: $$(cat $(DBLOG_PID_FILE)))"; \
	else \
		echo "Starting background DB log capture to $(DBLOG_DIR)/$$(date +%Y-%m-%d).log"; \
		nohup docker compose -f db-docker-compose.yml logs -f >> $(DBLOG_DIR)/$$(date +%Y-%m-%d).log 2>&1 & \
		echo $$! > $(DBLOG_PID_FILE); \
		echo "DB log capture started (PID: $$!)"; \
	fi

dblogs-stop:
	@if [ -f $(DBLOG_PID_FILE) ] && kill -0 $$(cat $(DBLOG_PID_FILE)) 2>/dev/null; then \
		kill $$(cat $(DBLOG_PID_FILE)) && rm -f $(DBLOG_PID_FILE) && echo "DB log capture stopped"; \
	else \
		rm -f $(DBLOG_PID_FILE); \
		echo "No DB log capture process running"; \
	fi

dblogs-today:
	@cat $(DBLOG_DIR)/$$(date +%Y-%m-%d).log 2>/dev/null || echo "No DB logs captured today. Run 'make dblogs-start' first."

dblogs-errors:
	@grep -i "error\|exception\|fail\|oom\|killed\|exit" $(DBLOG_DIR)/*.log 2>/dev/null || echo "No errors found in captured DB logs"

dblogs-service:
	@if [ -z "$(SERVICE)" ]; then \
		echo "Usage: make dblogs-service SERVICE=postgres|elasticsearch"; \
	else \
		grep "^$(SERVICE)" $(DBLOG_DIR)/$$(date +%Y-%m-%d).log 2>/dev/null || echo "No logs for $(SERVICE)."; \
	fi

dblogs-search:
	@if [ -z "$(PATTERN)" ]; then \
		echo "Usage: make dblogs-search PATTERN='text'"; \
	else \
		grep -i "$(PATTERN)" $(DBLOG_DIR)/*.log 2>/dev/null || echo "Pattern '$(PATTERN)' not found in DB logs"; \
	fi

dblogs-rotate:
	@find $(DBLOG_DIR) -name "*.log" -mtime +3 -exec gzip {} \; 2>/dev/null || true
	@find $(DBLOG_DIR) -name "*.log.gz" -mtime +7 -delete 2>/dev/null || true
	@echo "DB log rotation complete (compressed >3 days, deleted >7 days)"

dblogs-status:
	@echo "DB Log directory: $(DBLOG_DIR)"
	@du -sh $(DBLOG_DIR) 2>/dev/null || echo "No DB logs yet"
	@echo ""
	@ls -lh $(DBLOG_DIR)/ 2>/dev/null || echo "No DB log files"

dblogs-clean:
	@read -p "Delete all captured DB logs? [y/N] " confirm && \
	[ "$$confirm" = "y" ] && rm -rf $(DBLOG_DIR)/* && echo "DB logs deleted" || echo "Cancelled"

dblogs-cron-install:
	@DKAPP_DIR=$$(pwd) && \
	(crontab -l 2>/dev/null | grep -v "dkapp.*dblogs-rotate"; \
	echo "0 0 * * * cd $$DKAPP_DIR && make dblogs-rotate >> $$DKAPP_DIR/dblogs/cron.log 2>&1") | crontab - && \
	echo "DB log cron job installed: daily rotation at midnight" && \
	echo "View with: crontab -l"

dblogs-cron-remove:
	@crontab -l 2>/dev/null | grep -v "dkapp.*dblogs-rotate" | crontab - && \
	echo "DB log cron job removed"

prepare:
	@if [ -f .env.default ]; then \
		cp .env.default .env; \
		rm -f .env.default; \
	fi
	sudo apt-get update
	sudo apt-get install -y make docker.io docker-compose unzip python3-pip docker-compose-v2 gpg
	echo "Installing Docker Repos..."
	sudo apt-get install ca-certificates curl gnupg
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	echo "Adding user to docker user group..."
	sudo usermod -aG docker ${USER}
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	echo "Adding the repository to Apt sources..."

p2:
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

build: down
	gpg -o .env -d .env.gpg
	docker compose build --no-cache
	sleep 5
	rm -f .env


dblogs:
	docker compose -f db-docker-compose.yml logs -f --tail 100

restart: down updb up

down: logs-stop dblogs-stop
	docker compose -f docker-compose.yml down --remove-orphans
	docker compose -f db-docker-compose.yml down --remove-orphans

# Legacy update (use 'make update' instead for smart restart)
update-build: down pull build
	echo "App updated. Bring it up again with 'make start' or 'make updb up logs'"

up: ensurenetworks logdirs
	gpg -o .env -d .env.gpg
	@# Generate versions.env from manifest if it exists
	@if [ -f "version-manifest.yaml" ]; then \
		python3 version-manager.py generate-env 2>/dev/null || true; \
	fi
	@# Start services with version env if available
	@if [ -f "versions.env" ]; then \
		set -a && . ./versions.env && set +a && \
		docker compose -f docker-compose.yml up -d; \
	else \
		docker compose -f docker-compose.yml up -d; \
	fi
	sleep 5
	rm -f .env
	@echo "Starting background log capture..."
	@$(MAKE) logs-start


ensurenetworks:
	@# Network is created automatically by Docker Compose with named network config
	@true

pull:
	@# Pull images from manifest if available, otherwise pull latest
	@if [ -f "version-manifest.yaml" ]; then \
		python3 version-manager.py pull-from-manifest; \
	else \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/wsfe:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/ansi_processing:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/jobsched:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/apigateway:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/conv_mgr:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/settings:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/taskservice:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/req_router:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/dagknows_nuxt:latest; \
	fi

# Pull latest images (updates manifest if versioning is enabled)
pull-latest:
	@if [ -f "version-manifest.yaml" ]; then \
		python3 version-manager.py pull-latest; \
	else \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/wsfe:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/ansi_processing:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/jobsched:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/apigateway:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/conv_mgr:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/settings:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/taskservice:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/req_router:latest; \
		python3 docker-pull-retry.py public.ecr.aws/n5k3t9x2/dagknows_nuxt:latest; \
	fi

updb: dbdirs ensurenetworks dblogdirs
	gpg -o .env -d .env.gpg
	docker compose -f db-docker-compose.yml down --remove-orphans
	docker compose -f db-docker-compose.yml up -d
	@echo "Waiting for databases to be healthy..."
	@sleep 5
	@echo "  Postgres: checking pg_isready..."
	@i=0; while [ $$i -lt 30 ]; do \
		if docker compose -f db-docker-compose.yml exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then \
			echo "  Postgres: ready"; \
			break; \
		fi; \
		sleep 2; \
		i=$$((i + 1)); \
	done; \
	if [ $$i -ge 30 ]; then \
		echo "ERROR: Postgres failed to become ready after 60s"; \
		rm -f .env; \
		exit 1; \
	fi
	@echo "  Elasticsearch: waiting for cluster status yellow..."
	@i=0; while [ $$i -lt 40 ]; do \
		if curl -sf "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" >/dev/null 2>&1; then \
			echo "  Elasticsearch: ready"; \
			break; \
		fi; \
		sleep 3; \
		i=$$((i + 1)); \
	done; \
	if [ $$i -ge 40 ]; then \
		echo "ERROR: Elasticsearch failed to become ready after 120s (possible OOM or startup failure)"; \
		rm -f .env; \
		exit 1; \
	fi
	rm -f .env
	@echo "Starting background database log capture..."
	@$(MAKE) dblogs-start
	@echo "Database services are healthy and running."

dbdirs:
	mkdir -p postgres-data esdata1 elastic_backup
	sudo chmod -R a+rwx postgres-data esdata1 elastic_backup

backups:
	mkdir -p .backups/${DATE_SUFFIX}
	sudo cp -r ${DATAROOT}/postgres-data ".backups/${DATE_SUFFIX}/postgres-data"
	sudo cp -r ${DATAROOT}/esdata1 ".backups/${DATE_SUFFIX}/esdata1"
	sudo cp -r ${DATAROOT}/elastic_backup ".backups/${DATE_SUFFIX}/elastic_backup"

install:
	@echo "Running DagKnows installation wizard..."
	@python3 install.py

reconfigure:
	@echo "Running DagKnows reconfiguration tool..."
	@python3 reconfigure.py

status:
	@echo "Checking DagKnows installation status..."
	@python3 check-status.py

uninstall:
	@echo "Running DagKnows uninstall script..."
	@./uninstall.sh

help:
	@echo "DagKnows Management Commands"
	@echo "============================"
	@echo ""
	@echo "Installation & Setup:"
	@echo "  make install      - Run the automated installation wizard"
	@echo "  make prepare      - Install Docker and dependencies (Ubuntu)"
	@echo "  make uninstall    - Remove DagKnows installation"
	@echo ""
	@echo "Configuration:"
	@echo "  make encrypt      - Encrypt the .env file"
	@echo "  make reconfigure  - Update configuration without reinstalling"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs         - View application logs (follow mode)"
	@echo "  make dblogs       - View database logs (follow mode)"
	@echo "  make dblogs-today - View today's captured DB logs"
	@echo "  make dblogs-errors- View DB errors (includes OOM detection)"
	@echo "  make status       - Check installation status"
	@echo ""
	@echo "Log Management:"
	@echo "  make logs-start        - Start background log capture"
	@echo "  make logs-stop         - Stop background log capture"
	@echo "  make logs-today        - View today's captured logs"
	@echo "  make logs-errors       - View errors from captured logs"
	@echo "  make logs-service SERVICE=req-router - View specific service"
	@echo "  make logs-search PATTERN='text' - Search logs for pattern"
	@echo "  make logs-rotate       - Compress old, delete >7 days"
	@echo "  make logs-status       - Show log disk usage"
	@echo "  make logs-clean        - Delete all captured logs"
	@echo "  make logs-cron-install - Setup daily auto-rotation (cron)"
	@echo "  make logs-cron-remove  - Remove auto-rotation cron job"
	@echo ""
	@echo "Database Log Management:"
	@echo "  make dblogs-start       - Start background DB log capture"
	@echo "  make dblogs-stop        - Stop background DB log capture"
	@echo "  make dblogs-today       - View today's captured DB logs"
	@echo "  make dblogs-errors      - View DB errors (OOM, killed, etc.)"
	@echo "  make dblogs-service SERVICE=postgres - View specific DB service"
	@echo "  make dblogs-search PATTERN='text' - Search DB logs"
	@echo "  make dblogs-rotate      - Compress old, delete >7 days"
	@echo "  make dblogs-status      - Show DB log disk usage"
	@echo "  make dblogs-clean       - Delete all captured DB logs"
	@echo "  make dblogs-cron-install - Setup daily DB log rotation"
	@echo "  make dblogs-cron-remove  - Remove DB log rotation cron job"
	@echo ""
	@echo "Service Control (Recommended):"
	@echo "  make start        - Start all services (health checks, versioning, log capture)"
	@echo "  make stop         - Stop all services and log capture processes"
	@echo "  make restart      - Restart all services"
	@echo "  make update       - Pull latest images and restart"
	@echo ""
	@echo "Maintenance:"
	@echo "  make pull         - Pull images from version manifest"
	@echo "  make pull-latest  - Pull latest images (ignores manifest)"
	@echo "  make build        - Build Docker images"
	@echo "  make backups      - Backup all data"
	@echo ""
	@echo "Version Management:"
	@echo "  make version       - Show current deployed versions"
	@echo "  make check-updates - Check for available updates"
	@echo "  make update-safe   - Safe update with backup and rollback"
	@echo "  make rollback      - Rollback to previous versions"
	@echo "  make help-version  - Show all version management commands"
	@echo ""
	@echo "Auto-Restart (System Boot):"
	@echo "  make setup-autorestart   - Setup auto-start on system reboot"
	@echo "  make disable-autorestart - Disable auto-start and remove services"
	@echo "  make autorestart-status  - Check auto-restart configuration"
	@echo ""
	@echo "Legacy Commands (manual passphrase entry):"
	@echo "  make updb         - Start databases only (prompts for passphrase)"
	@echo "  make up           - Start app services only (prompts for passphrase)"
	@echo "  make down         - Stop all containers and log captures"
	@echo ""
	@echo "Tip: Use 'make start/stop/restart/update' for simplified operations"

# ============================================
# VERSION MANAGEMENT
# ============================================

# Show current deployed versions
version:
	@python3 version-manager.py show

# Show version history
version-history:
	@python3 version-manager.py history $(SERVICE)

# Pull specific version for a service
# Usage: make version-pull SERVICE=taskservice TAG=1.42
version-pull:
	@if [ -z "$(SERVICE)" ] || [ -z "$(TAG)" ]; then \
		echo "Error: SERVICE and TAG are required."; \
		echo "Usage: make version-pull SERVICE=taskservice TAG=1.42"; \
		echo ""; \
		echo "Each service has its own version. Examples:"; \
		echo "  make version-pull SERVICE=req_router TAG=1.35"; \
		echo "  make version-pull SERVICE=taskservice TAG=1.42"; \
		exit 1; \
	fi
	@python3 version-manager.py pull --service=$(SERVICE) --tag=$(TAG)

# Set custom version for hotfixes
# Usage: make version-set SERVICE=taskservice TAG=v1.2.3-hotfix
version-set:
	@if [ -z "$(SERVICE)" ] || [ -z "$(TAG)" ]; then \
		echo "Error: SERVICE and TAG are required."; \
		echo "Usage: make version-set SERVICE=taskservice TAG=v1.2.3-hotfix"; \
		exit 1; \
	fi
	@python3 version-manager.py set --service=$(SERVICE) --tag=$(TAG)

# Rollback all services to previous version
rollback:
	@python3 version-manager.py rollback --all

# Rollback specific service to previous version
# Usage: make rollback-service SERVICE=taskservice
rollback-service:
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: SERVICE is required. Usage: make rollback-service SERVICE=taskservice"; \
		exit 1; \
	fi
	@python3 version-manager.py rollback --service=$(SERVICE)

# Rollback to specific tag
# Usage: make rollback-to SERVICE=taskservice TAG=v1.2.1
rollback-to:
	@if [ -z "$(SERVICE)" ] || [ -z "$(TAG)" ]; then \
		echo "Error: SERVICE and TAG are required."; \
		echo "Usage: make rollback-to SERVICE=taskservice TAG=v1.2.1"; \
		exit 1; \
	fi
	@python3 version-manager.py rollback --service=$(SERVICE) --tag=$(TAG)

# Safe update to latest with automatic backup and rollback on failure
# For updating specific service to specific tag: make version-pull SERVICE=x TAG=y
update-safe:
	@python3 version-manager.py update-safe

# Check for available updates
check-updates:
	@python3 version-manager.py check-updates

# Login to private ECR
ecr-login:
	@python3 version-manager.py ecr-login

# Migrate existing deployment to versioned
migrate-versions:
	@python3 migrate-to-versioned.py

# Generate versions.env from manifest
generate-env:
	@python3 version-manager.py generate-env

# Resolve 'latest' tags to semantic versions from ECR
resolve-tags:
	@python3 version-manager.py resolve-tags

# Friendly aliases
upgrade: update-safe
downgrade: rollback
whatversion: version
info: status version
health: status check-updates

# Version management help
help-version:
	@echo "DagKnows Version Management Commands"
	@echo "====================================="
	@echo ""
	@echo "NOTE: Each service has its own version (e.g., req_router:1.35, taskservice:1.42)"
	@echo ""
	@echo "View Versions:"
	@echo "  make version                         - Show current deployed versions"
	@echo "  make version-history                 - Show version history for all services"
	@echo "  make version-history SERVICE=x       - Show history for specific service"
	@echo ""
	@echo "Update:"
	@echo "  make pull                            - Pull latest for all services"
	@echo "  make pull-latest                     - Pull latest (ignores manifest)"
	@echo "  make update-safe                     - Safe update to latest with backup"
	@echo "  make version-pull SERVICE=x TAG=y   - Pull specific version for one service"
	@echo "  make version-set SERVICE=x TAG=y    - Set custom version (for hotfixes)"
	@echo "  make check-updates                   - Check for available updates"
	@echo ""
	@echo "Rollback:"
	@echo "  make rollback                        - Rollback all services to previous"
	@echo "  make rollback-service SERVICE=x      - Rollback specific service"
	@echo "  make rollback-to SERVICE=x TAG=y     - Rollback to specific version"
	@echo ""
	@echo "Migration & Setup:"
	@echo "  make migrate-versions                - Migrate existing deployment to versioned"
	@echo "  make generate-env                    - Regenerate versions.env from manifest"
	@echo "  make resolve-tags                    - Resolve 'latest' tags to versions from ECR"
	@echo "  make ecr-login                       - Login to private ECR (optional)"
	@echo ""
	@echo "Examples:"
	@echo "  make version-pull SERVICE=taskservice TAG=1.42"
	@echo "  make version-set SERVICE=req_router TAG=1.35-hotfix"
	@echo "  make rollback-service SERVICE=settings"
	@echo ""
	@echo "Aliases:"
	@echo "  make upgrade      = make update-safe"
	@echo "  make downgrade    = make rollback"
	@echo "  make whatversion  = make version"
	@echo "  make info         = make status version"
	@echo "  make health       = make status check-updates"

# ==============================================
# AUTO-RESTART MANAGEMENT
# ==============================================

# Setup automatic restart on system boot
setup-autorestart:
	@echo "Setting up automatic restart on system boot..."
	@sudo bash ./setup-autorestart.sh

# Disable automatic restart
disable-autorestart:
	@echo "Disabling automatic restart..."
	@sudo systemctl disable dkapp-db.service dkapp.service 2>/dev/null || true
	@sudo systemctl stop dkapp-db.service dkapp.service 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/dkapp-db.service /etc/systemd/system/dkapp.service
	@sudo rm -f /root/.dkapp-passphrase
	@sudo systemctl daemon-reload
	@echo "Auto-restart disabled. Services removed."

# Check auto-restart status
autorestart-status:
	@echo "=== Auto-Restart Status ==="
	@echo ""
	@echo "Docker service:"
	@systemctl is-enabled docker 2>/dev/null && echo "  Enabled" || echo "  Disabled"
	@echo ""
	@echo "DagKnows Database Service (dkapp-db):"
	@if [ -f /etc/systemd/system/dkapp-db.service ]; then \
		systemctl is-enabled dkapp-db.service 2>/dev/null && echo "  Enabled" || echo "  Disabled"; \
		echo "  Status: $$(systemctl is-active dkapp-db.service 2>/dev/null || echo 'not running')"; \
	else \
		echo "  Not installed"; \
	fi
	@echo ""
	@echo "DagKnows Application Service (dkapp):"
	@if [ -f /etc/systemd/system/dkapp.service ]; then \
		systemctl is-enabled dkapp.service 2>/dev/null && echo "  Enabled" || echo "  Disabled"; \
		echo "  Status: $$(systemctl is-active dkapp.service 2>/dev/null || echo 'not running')"; \
	else \
		echo "  Not installed"; \
	fi
	@echo ""
	@echo "Passphrase file:"
	@if sudo test -f /root/.dkapp-passphrase 2>/dev/null; then \
		echo "  Present (auto-decrypt enabled)"; \
	else \
		echo "  Not present (manual password entry required)"; \
	fi

# ==============================================
# SMART START/STOP/RESTART (Auto-detects mode)
# ==============================================

# Smart start: uses systemctl if auto-restart configured, otherwise traditional method
# Note: Use 'sudo test' for /root/.dkapp-passphrase since it's only readable by root
# Features: network creation, directory setup, health checks, version management, log capture
start: stop logdirs dblogdirs
	@if [ -f /etc/systemd/system/dkapp-db.service ] && sudo test -f /root/.dkapp-passphrase; then \
		echo "Starting services via systemd (auto-restart mode)..."; \
		sudo systemctl start dkapp-db.service; \
		echo "Waiting for databases to be ready..."; \
		sleep 5; \
		sudo systemctl start dkapp.service; \
		echo "Services started. Starting background log capture..."; \
		$(MAKE) dblogs-start; \
		$(MAKE) logs-start; \
		echo "Done. Use 'make status' to check."; \
	elif [ -f .env ]; then \
		echo "Starting services (unencrypted .env mode)..."; \
		echo ""; \
		echo "=== Setting up directories ==="; \
		mkdir -p postgres-data esdata1 elastic_backup 2>/dev/null || true; \
		sudo chmod -R a+rwx postgres-data esdata1 elastic_backup 2>/dev/null || true; \
		echo ""; \
		echo "=== Creating Docker network ==="; \
		docker network create saaslocalnetwork 2>/dev/null || true; \
		echo ""; \
		echo "=== Starting database services ==="; \
		docker compose -f db-docker-compose.yml down --remove-orphans 2>/dev/null || true; \
		docker compose -f db-docker-compose.yml up -d; \
		echo ""; \
		echo "=== Waiting for PostgreSQL (up to 60s) ==="; \
		i=0; while [ $$i -lt 30 ]; do \
			if docker compose -f db-docker-compose.yml exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then \
				echo "  PostgreSQL: ready"; \
				break; \
			fi; \
			echo "  Waiting for PostgreSQL... ($$i/30)"; \
			sleep 2; \
			i=$$((i + 1)); \
		done; \
		if [ $$i -ge 30 ]; then \
			echo "ERROR: PostgreSQL failed to become ready after 60s"; \
			exit 1; \
		fi; \
		echo ""; \
		echo "=== Waiting for Elasticsearch (up to 120s) ==="; \
		i=0; while [ $$i -lt 40 ]; do \
			if curl -sf "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" >/dev/null 2>&1; then \
				echo "  Elasticsearch: ready"; \
				break; \
			fi; \
			echo "  Waiting for Elasticsearch... ($$i/40)"; \
			sleep 3; \
			i=$$((i + 1)); \
		done; \
		if [ $$i -ge 40 ]; then \
			echo "ERROR: Elasticsearch failed to become ready after 120s"; \
			exit 1; \
		fi; \
		echo ""; \
		echo "=== Setting up version management ==="; \
		if [ -f "version-manifest.yaml" ]; then \
			echo "  Generating versions.env from manifest..."; \
			python3 version-manager.py generate-env 2>/dev/null || true; \
		fi; \
		echo ""; \
		echo "=== Starting application services ==="; \
		if [ -f "versions.env" ]; then \
			echo "  Loading version overrides from versions.env"; \
			set -a && . ./versions.env && set +a && \
			docker compose -f docker-compose.yml up -d; \
		else \
			echo "  Using default image tags (no versions.env)"; \
			docker compose -f docker-compose.yml up -d; \
		fi; \
		echo ""; \
		echo "=== Starting background log capture ==="; \
		$(MAKE) dblogs-start; \
		$(MAKE) logs-start; \
		echo ""; \
		echo "Services started. Use 'make status' to check."; \
	else \
		echo "Starting services (manual mode - passphrase required)..."; \
		echo "Run: make updb && make up"; \
	fi

# Smart stop: stops all services and log capture processes
stop: logs-stop dblogs-stop
	@echo "Stopping all services..."
	@if [ -f /etc/systemd/system/dkapp.service ]; then \
		sudo systemctl stop dkapp.service 2>/dev/null || true; \
		sudo systemctl stop dkapp-db.service 2>/dev/null || true; \
	fi
	@docker compose down 2>/dev/null || true
	@docker compose -f db-docker-compose.yml down 2>/dev/null || true
	@echo "All services stopped."

# Smart restart: stop then start
restart: stop start

# Smart update: pull new images and restart
update:
	@echo "=== Updating DagKnows ==="
	@echo ""
	@echo "Stopping services..."
	@$(MAKE) stop
	@echo ""
	@echo "Pulling latest images..."
	@$(MAKE) pull-latest
	@echo ""
	@echo "Starting services..."
	@$(MAKE) start
	@echo ""
	@echo "Update complete. Use 'make status' to verify."
