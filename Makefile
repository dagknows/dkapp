
DATE_SUFFIX=${shell date +"%Y%m%d%H%M%S"}
DATAROOT=.

logs:
	docker-compose logs -f --tail 100

prepare:
	sudo apt-get update
	sudo apt-get install -y docker.io docker-compose unzip python3-pip

dblogs:
	docker-compose -f db-docker-compose.yml logs -f --tail 100

build: down
	docker-compose build --no-cache

restart: down updb up logs

down:
	docker-compose -f docker-compose.yml down --remove-orphans

update: down pull build
	echo "App updated.  Bring it up again with `make updb up logs`"

up: ensurenetworks
	docker-compose -f docker-compose.yml up -d

ensurenetworks:
	-@docker network create saaslocalnetwork

pull: prepare
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
	docker-compose -f db-docker-compose.yml down --remove-orphans
	docker-compose -f db-docker-compose.yml up -d

dbdirs:
	mkdir -p postgres-data esdata1 elastic_backup
	sudo chmod -R a+rwx postgres-data esdata1 elastic_backup

backups:
	mkdir -p .backups/${DATE_SUFFIX}
	sudo cp -r ${DATAROOT}/postgres-data ".backups/${DATE_SUFFIX}/postgres-data"
	sudo cp -r ${DATAROOT}/esdata1 ".backups/${DATE_SUFFIX}/esdata1"
	sudo cp -r ${DATAROOT}/elastic_backup ".backups/${DATE_SUFFIX}/elastic_backup"
