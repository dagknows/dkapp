
DATE_SUFFIX=${shell date +"%Y%m%d%H%M%S"}
DATAROOT=.
LOG_DIR=./logs
LOG_PID_FILE=./logs/.capture.pid

.PHONY: logs logs-start logs-stop logs-today logs-errors logs-service logs-search logs-rotate logs-status logs-clean logs-cron-install logs-cron-remove logdirs
.PHONY: version version-history version-pull version-set rollback rollback-service rollback-to update-safe check-updates ecr-login migrate-versions

encrypt:
	gpg -c .env
	rm -f .env

logs:
	docker compose logs -f --tail 300

# Log Management - Capture and filter logs
logdirs:
	@mkdir -p $(LOG_DIR)

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
	@grep "^$(SERVICE)" $(LOG_DIR)/$$(date +%Y-%m-%d).log 2>/dev/null || echo "No logs for $(SERVICE). Try: make logs-service SERVICE=req-router"

logs-search:
	@grep -i "$(PATTERN)" $(LOG_DIR)/*.log 2>/dev/null || echo "Pattern '$(PATTERN)' not found"

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

restart: down updb up logs

down:
	docker compose -f docker-compose.yml down --remove-orphans

update: down pull build
	echo "App updated.  Bring it up again with `make updb up logs`"

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
	@nohup docker compose logs -f >> $(LOG_DIR)/$$(date +%Y-%m-%d).log 2>&1 & echo $$! > $(LOG_PID_FILE)


ensurenetworks:
	-@docker network create saaslocalnetwork

pull:
	@# Pull images from manifest if available, otherwise pull latest
	@if [ -f "version-manifest.yaml" ]; then \
		python3 version-manager.py pull-from-manifest; \
	else \
		docker pull public.ecr.aws/n5k3t9x2/wsfe:latest; \
		docker pull public.ecr.aws/n5k3t9x2/ansi_processing:latest; \
		docker pull public.ecr.aws/n5k3t9x2/jobsched:latest; \
		docker pull public.ecr.aws/n5k3t9x2/apigateway:latest; \
		docker pull public.ecr.aws/n5k3t9x2/conv_mgr:latest; \
		docker pull public.ecr.aws/n5k3t9x2/settings:latest; \
		docker pull public.ecr.aws/n5k3t9x2/taskservice:latest; \
		docker pull public.ecr.aws/n5k3t9x2/req_router:latest; \
		docker pull public.ecr.aws/n5k3t9x2/dagknows_nuxt:latest; \
	fi

# Pull latest images (ignores manifest)
pull-latest:
	docker pull public.ecr.aws/n5k3t9x2/wsfe:latest
	docker pull public.ecr.aws/n5k3t9x2/ansi_processing:latest
	docker pull public.ecr.aws/n5k3t9x2/jobsched:latest
	docker pull public.ecr.aws/n5k3t9x2/apigateway:latest
	docker pull public.ecr.aws/n5k3t9x2/conv_mgr:latest
	docker pull public.ecr.aws/n5k3t9x2/settings:latest
	docker pull public.ecr.aws/n5k3t9x2/taskservice:latest
	docker pull public.ecr.aws/n5k3t9x2/req_router:latest
	docker pull public.ecr.aws/n5k3t9x2/dagknows_nuxt:latest

updb: dbdirs ensurenetworks
	gpg -o .env -d .env.gpg
	docker compose -f db-docker-compose.yml down --remove-orphans
	docker compose -f db-docker-compose.yml up -d
	sleep 5
	rm -f .env

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
	@echo "Service Management:"
	@echo "  make updb         - Start database services (postgres, elasticsearch)"
	@echo "  make up           - Start application services (+ auto log capture)"
	@echo "  make down         - Stop all services"
	@echo "  make restart      - Restart all services"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs         - View application logs (follow mode)"
	@echo "  make dblogs       - View database logs (follow mode)"
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
	@echo "Maintenance:"
	@echo "  make pull         - Pull latest Docker images"
	@echo "  make build        - Build Docker images"
	@echo "  make update       - Update to latest version"
	@echo "  make backups      - Backup all data"
	@echo ""
	@echo "Version Management:"
	@echo "  make version       - Show current deployed versions"
	@echo "  make check-updates - Check for available updates"
	@echo "  make update-safe   - Safe update with backup and rollback"
	@echo "  make rollback      - Rollback to previous versions"
	@echo "  make help-version  - Show all version management commands"
	@echo ""
	@echo "Note: Commands that access encrypted files will prompt for password"

# ============================================
# VERSION MANAGEMENT
# ============================================

# Show current deployed versions
version:
	@python3 version-manager.py show

# Show version history
version-history:
	@python3 version-manager.py history $(SERVICE)

# Pull specific version
# Usage: make version-pull TAG=v1.2.3 [SERVICE=taskservice]
version-pull:
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG is required. Usage: make version-pull TAG=v1.2.3"; \
		exit 1; \
	fi
	@python3 version-manager.py pull --tag=$(TAG) $(if $(SERVICE),--service=$(SERVICE),)

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

# Safe update with automatic backup and rollback on failure
update-safe:
	@python3 version-manager.py update-safe $(if $(TAG),--tag=$(TAG),)

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
	@echo "View Versions:"
	@echo "  make version                         - Show current deployed versions"
	@echo "  make version-history                 - Show version history for all services"
	@echo "  make version-history SERVICE=x       - Show history for specific service"
	@echo ""
	@echo "Update:"
	@echo "  make update-safe                     - Safe update with backup (recommended)"
	@echo "  make update-safe TAG=v1.2.3          - Update to specific version"
	@echo "  make version-pull TAG=v1.2.3         - Pull specific version for all services"
	@echo "  make version-pull TAG=v1.2.3 SERVICE=x  - Pull for specific service"
	@echo "  make version-set SERVICE=x TAG=y     - Set custom version (for hotfixes)"
	@echo "  make check-updates                   - Check for available updates"
	@echo ""
	@echo "Rollback:"
	@echo "  make rollback                        - Rollback all services to previous"
	@echo "  make rollback-service SERVICE=x      - Rollback specific service"
	@echo "  make rollback-to SERVICE=x TAG=y     - Rollback to specific version"
	@echo ""
	@echo "Migration & ECR:"
	@echo "  make migrate-versions                - Migrate existing deployment to versioned"
	@echo "  make ecr-login                       - Login to private ECR"
	@echo "  make generate-env                    - Regenerate versions.env from manifest"
	@echo ""
	@echo "Aliases:"
	@echo "  make upgrade      = make update-safe"
	@echo "  make downgrade    = make rollback"
	@echo "  make whatversion  = make version"
	@echo "  make info         = make status version"
	@echo "  make health       = make status check-updates"
