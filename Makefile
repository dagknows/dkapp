
DATE_SUFFIX=${shell date +"%Y%m%d%H%M%S"}
DATAROOT=.

logs:
	docker compose logs -f

prepare:
	sudo apt-get update
	sudo apt-get install -y make docker.io docker docker-compose unzip python3-pip docker-compose-v2
	echo "Installing Docker Repos..."
	sudo apt-get install ca-certificates curl gnupg
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	echo "Adding the repository to Apt sources..."

p2:
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	echo "Adding user to docker user group..."
	sudo usermod -aG docker ${USER}

build: down
	docker compose build --no-cache

dblogs:
	docker compose -f db-docker-compose.yml logs -f --tail 100

restart: down updb up logs

down:
	docker compose down --remove-orphans

update: down pull build
	echo "App updated.  Bring it up again with `make updb up logs`"

up: ensurenetworks
	docker compose -f docker-compose.yml up -d

ensurenetworks:
	-@docker network create saaslocalnetwork

pull:
	docker pull gcr.io/dagknows-images/wsfe:latest
	docker pull gcr.io/dagknows-images/jobsched:latest
	docker pull gcr.io/dagknows-images/apigateway:latest
	docker pull gcr.io/dagknows-images/conv_mgr:latest
	docker pull gcr.io/dagknows-images/conv_sse:latest
	docker pull gcr.io/dagknows-images/proxy_sse:latest
	docker pull gcr.io/dagknows-images/settings:latest
	docker pull gcr.io/dagknows-images/taskservice:latest
	docker pull gcr.io/dagknows-images/req_router:latest
	docker pull gcr.io/dagknows-images/dagknows_nuxt:latest

updb: dbdirs ensurenetworks
	docker compose -f db-docker-compose.yml down --remove-orphans
	docker compose -f db-docker-compose.yml up -d

dbdirs:
	mkdir -p postgres-data esdata1 elastic_backup
	sudo chmod -R a+rwx postgres-data esdata1 elastic_backup

backups:
	mkdir -p .backups/${DATE_SUFFIX}
	sudo cp -r ${DATAROOT}/postgres-data ".backups/${DATE_SUFFIX}/postgres-data"
	sudo cp -r ${DATAROOT}/esdata1 ".backups/${DATE_SUFFIX}/esdata1"
	sudo cp -r ${DATAROOT}/elastic_backup ".backups/${DATE_SUFFIX}/elastic_backup"
