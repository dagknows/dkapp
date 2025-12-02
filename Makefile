
DATE_SUFFIX=${shell date +"%Y%m%d%H%M%S"}
DATAROOT=.



encrypt:
	gpg -c .env
	rm -f .env

logs:
	docker compose logs -f

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

up: ensurenetworks
	gpg -o .env -d .env.gpg
	docker compose -f docker-compose.yml up -d
	sleep 5
	rm -f .env


ensurenetworks:
	-@docker network create saaslocalnetwork

pull:
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
	@echo "  make up           - Start application services"
	@echo "  make down         - Stop all services"
	@echo "  make restart      - Restart all services"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs         - View application logs (follow mode)"
	@echo "  make dblogs       - View database logs (follow mode)"
	@echo "  make status       - Check installation status"
	@echo ""
	@echo "Maintenance:"
	@echo "  make pull         - Pull latest Docker images"
	@echo "  make build        - Build Docker images"
	@echo "  make update       - Update to latest version"
	@echo "  make backups      - Backup all data"
	@echo ""
	@echo "Note: Commands that access encrypted files will prompt for password"
