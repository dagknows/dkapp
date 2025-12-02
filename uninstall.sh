#!/bin/bash
# DagKnows Uninstall Script
# Safely removes DagKnows installation while preserving backups

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "\n${BOLD}${RED}DagKnows Uninstall Script${NC}\n"
echo -e "${YELLOW}⚠ WARNING: This will remove your DagKnows installation${NC}"
echo -e "${YELLOW}⚠ All data will be deleted unless you create a backup first${NC}\n"

# Ask for confirmation
read -p "$(echo -e ${BOLD}Do you want to create a backup before uninstalling? \(yes/no\): ${NC})" CREATE_BACKUP
if [[ "$CREATE_BACKUP" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${BLUE}Creating backup...${NC}"
    make backups || echo -e "${YELLOW}Backup failed, but continuing...${NC}"
fi

echo ""
read -p "$(echo -e ${BOLD}Are you sure you want to uninstall DagKnows? \(yes/no\): ${NC})" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${GREEN}Uninstall cancelled${NC}"
    exit 0
fi

echo -e "\n${BLUE}Stopping all services...${NC}"
docker compose -f docker-compose.yml down --remove-orphans 2>/dev/null || true
docker compose -f db-docker-compose.yml down --remove-orphans 2>/dev/null || true

echo -e "${BLUE}Removing Docker network...${NC}"
docker network rm saaslocalnetwork 2>/dev/null || true

# Ask about data removal
echo ""
read -p "$(echo -e ${BOLD}Remove data directories \(postgres-data, esdata1, elastic_backup\)? \(yes/no\): ${NC})" REMOVE_DATA
if [[ "$REMOVE_DATA" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${BLUE}Removing data directories...${NC}"
    sudo rm -rf postgres-data esdata1 elastic_backup
    echo -e "${GREEN}✓ Data directories removed${NC}"
fi

# Ask about config removal
echo ""
read -p "$(echo -e ${BOLD}Remove configuration files \(.env.gpg, SSL certs\)? \(yes/no\): ${NC})" REMOVE_CONFIG
if [[ "$REMOVE_CONFIG" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${BLUE}Removing configuration files...${NC}"
    rm -f .env.gpg .env sample-selfsigned.crt sample-selfsigned.key
    echo -e "${GREEN}✓ Configuration files removed${NC}"
fi

# Ask about Docker images
echo ""
read -p "$(echo -e ${BOLD}Remove Docker images? \(yes/no\): ${NC})" REMOVE_IMAGES
if [[ "$REMOVE_IMAGES" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${BLUE}Removing Docker images...${NC}"
    docker rmi -f \
        public.ecr.aws/n5k3t9x2/wsfe:latest \
        public.ecr.aws/n5k3t9x2/ansi_processing:latest \
        public.ecr.aws/n5k3t9x2/jobsched:latest \
        public.ecr.aws/n5k3t9x2/apigateway:latest \
        public.ecr.aws/n5k3t9x2/conv_mgr:latest \
        public.ecr.aws/n5k3t9x2/settings:latest \
        public.ecr.aws/n5k3t9x2/taskservice:latest \
        public.ecr.aws/n5k3t9x2/req_router:latest \
        public.ecr.aws/n5k3t9x2/dagknows_nuxt:latest \
        postgres:16.5 \
        docker.elastic.co/elasticsearch/elasticsearch:8.9.2 \
        nginx:latest \
        2>/dev/null || echo -e "${YELLOW}Some images could not be removed (may not exist)${NC}"
    echo -e "${GREEN}✓ Docker images removed${NC}"
fi

echo -e "\n${GREEN}${BOLD}DagKnows uninstall complete!${NC}\n"

if [[ "$REMOVE_DATA" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${YELLOW}Note: Your data has been removed.${NC}"
    if [ -d ".backups" ]; then
        echo -e "${GREEN}Backups are still available in the .backups/ directory${NC}"
    fi
else
    echo -e "${GREEN}Your data has been preserved in:${NC}"
    echo "  - postgres-data/"
    echo "  - esdata1/"
    echo "  - elastic_backup/"
fi

if [[ ! "$REMOVE_CONFIG" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${GREEN}Your configuration has been preserved in .env.gpg${NC}"
fi

echo ""
echo -e "${BLUE}To reinstall DagKnows, run: ./install.sh${NC}"
echo ""

