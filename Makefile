
DATE_SUFFIX=${shell date +"%Y%m%d%H%M%S"}
DATAROOT=.

logs:
	docker-compose logs -f --tail 100

dblogs:
	docker-compose logs -f db-docker-compose.yml --tail 100

down:
	sudo docker-compose down --remove-orphans 

build: down
	sudo chmod -R a+rwx postgres-data
	docker-compose build --no-cache

update: down pull build
	echo "App updated.  Bring it up again with `make up logs`"

up: down dbdirs ensurenetworks
	docker-compose up -d

rundb: dbdirs ensurenetworks
	docker-compose -f db-docker-compose.yml down --remove-orphans
	docker-compose -f db-docker-compose.yml up -d

ensurenetworks:
	-docker network create saaslocalnetwork

backups:
	mkdir -p .backups/${DATE_SUFFIX}
	sudo cp -r ${DATAROOT}/postgres-data ".backups/${DATE_SUFFIX}/postgres-data"
	sudo cp -r ${DATAROOT}/esdata1 ".backups/${DATE_SUFFIX}/esdata1"
	sudo cp -r ${DATAROOT}/elastic_backup ".backups/${DATE_SUFFIX}/elastic_backup"

dbdirs:
	mkdir -p postgres-data esdata1 elastic_backup
