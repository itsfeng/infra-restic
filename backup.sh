#!/usr/bin/env bash
set -euxo pipefail

# vars & setup
TELEGRAMTOKEN=$(cat /opt/restic/telegram-bot-token)
TELEGRAMCHATID=$(cat /opt/restic/telegram-chat-id)
TIMESTAMP=$(date +%F_%H-%M)
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
LOGFILE=/var/log/restic-${TIMESTAMP}.log
mkdir -p /var/log/restic && touch ${LOGFILE}

# error handling
trap 'catch $? $LINENO' EXIT
catch() {
  if [ "${1}" != "0" ]; then
      echo -e "\n[$(date +%Z-%F-%H:%M:%S)]: Error ${1} occurred" >> ${LOGFILE}
      telegram '"⚠️🛑   Backup aborted"'
  fi
}

# functions
log() {
  echo -e "[$(date +%Z-%F-%H:%M:%S)]: $*" >> ${LOGFILE}
}

telegram() {
  curl -sS -X POST \
	-H 'Content-Type: application/json' \
	-d '{"chat_id": '"${TELEGRAMCHATID}"', "text": '"$*"'}' \
	https://api.telegram.org/${TELEGRAMTOKEN}/sendMessage >> ${LOGFILE}
}

function divider {
  log "\n ${RED}# ----------------------------- #${NC} \n"
}

function restic_source_env {
  log "${YELLOW}sourcing${NC} $1"
  if [ -f /opt/restic/restic-pw-$1 ]; then
    source /opt/restic/restic-env.sh $1
    log "${GREEN}done: sourcing${NC}"
  else
    log "${RED}failed: sourcing${NC}"
    log ">/opt/restic/restic-pw-$1< is missing."
    exit 1
  fi
}

function restic_backup_app {
  log "${YELLOW}${RESTIC_SERVICE}-app${NC}"
  restic backup -v $1 --tag ${RESTIC_SERVICE}-app >> ${LOGFILE}
  log "${GREEN}done: ${RESTIC_SERVICE}-app${NC}"
}

function restic_backup_data {
  log "${YELLOW}${RESTIC_SERVICE}-data${NC}"
  restic backup -v $1 --tag ${RESTIC_SERVICE}-data >> ${LOGFILE}
  log "${GREEN}done: ${RESTIC_SERVICE}-data${NC}"
}

function restic_backup_db {
  log "${YELLOW}${RESTIC_SERVICE}-db${NC}"
  restic backup -v $1 --tag ${RESTIC_SERVICE}-db >> ${LOGFILE}
  log "${GREEN}done: ${RESTIC_SERVICE}-db${NC}"
}

function restic_cleanup {
  log "${RED}forget${NC}"
  restic forget -v --tag ${RESTIC_SERVICE}-app,${RESTIC_SERVICE}-data,${RESTIC_SERVICE}-db --keep-daily 63 --keep-monthly 12 --keep-yearly 3 >> ${LOGFILE}
  log "${GREEN}done: forget${NC}"
  log "${RED}prune${NC}"
  restic prune -v >> ${LOGFILE}
  log "${GREEN}done: prune${NC}"
}

divider
telegram '"💾🚀   Backup starting"'
divider

## create db dumps
# run test
# restic_source_env testor
# source /opt/docker/wp-db.env && docker-compose -f /opt/docker/docker-compose.yml exec wp-db mysqldump -uroot -p${MYSQL_PASSWORD} --databases wp > /storage-files/backups/backup-wp-db/wp-dump-${TIMESTAMP}.sql

# memos
sqlite3 /storage-files/memos/memos_prod.db .dump > /storage-files/backups/backup-memos-db/memos-dump-${TIMESTAMP}.sql
# photoprism
source /opt/docker/photoprism-db.env && docker compose -f /opt/docker/docker-compose.yml exec photoprism-db mysqldump -uphotoprism -p${MYSQL_PASSWORD} --databases photoprism > /storage-files/backups/backup-photoprism-db/photoprism-dump-${TIMESTAMP}.sql
# nextcloud
source /opt/docker/nextcloud-db.env && docker compose -f /opt/docker/docker-compose.yml exec nextcloud-mariadb mysqldump -unextcloud -p${MYSQL_PASSWORD} --databases nextcloud_db > /storage-files/backups/backup-nc-db/nc-dump-${TIMESTAMP}.sql
# paperless
source /opt/docker/paperless-db.env && PGPASSWORD=${POSTGRES_PASSWORD} && docker compose -f /opt/docker/docker-compose.yml exec paperless-db pg_dump -U ${POSTGRES_USER} -d paperless > /storage-files/backups/backup-paperless-db/paperless-dump-${TIMESTAMP}.sql
# influx
mkdir -p /storage-files/backups/backup-influx-db/${TIMESTAMP}
source /opt/docker/influx-db.env && docker compose -f /opt/docker/docker-compose.yml exec influx influx backup /srv/backup/${TIMESTAMP} --host http://localhost:8086 --org-id 284a5857f6a42616 --token ${INFLUX_API_TOKEN}
zip -jr /storage-files/backups/backup-influx-db/influxdb-dump-${TIMESTAMP}.zip /storage-files/backups/backup-influx-db/${TIMESTAMP} && rm -rf /storage-files/backups/backup-influx-db/${TIMESTAMP}

## run restic backups
# wp
#restic_source_env wp
#restic_backup_data "/storage-files/wordpress/data"
#restic_backup_db "/storage-files/backups/backup-wp-db/wp-dump-${TIMESTAMP}.sql"
#restic_cleanup
#divider

# nextcloud
restic_source_env nextcloud
restic_backup_app "/storage-files/nextcloud/app"
restic_backup_data "/storage-files/nextcloud/data"
restic_backup_db "/storage-files/backups/backup-nc-db/nc-dump-${TIMESTAMP}.sql"
restic_cleanup
divider

# memos
restic_source_env memos
restic_backup_db "/storage-files/backups/backup-memos-db/memos-dump-${TIMESTAMP}.sql"
restic_cleanup
divider

# zigbee
restic_source_env zigbee
restic_backup_app "/storage-files/zigbee2mqtt"
restic_cleanup
divider

# photoprism
restic_source_env photoprism
restic_backup_data "/storage-media/photoprism/app"
restic_backup_db "/storage-files/backups/backup-photoprism-db/photoprism-dump-${TIMESTAMP}.sql"
restic_cleanup
divider

# paperless
restic_source_env paperless
restic_backup_data "/storage-files/paperless/media"
restic_backup_app "/storage-files/paperless/data"
restic_backup_db "/storage-files/backups/backup-paperless-db/paperless-dump-${TIMESTAMP}.sql"
restic_cleanup
divider

# influx
restic_source_env influx
restic_backup_db "/storage-files/backups/backup-influx-db/influxdb-dump-${TIMESTAMP}.zip"
restic_cleanup
divider

## remove tars
# rm -rf /storage-files/backups/backup-wp-db/wp-dump-${TIMESTAMP}.sql
rm -rf /storage-files/backups/backup-nc-db/nc-dump-${TIMESTAMP}.sql
rm -rf /storage-files/backups/backup-photoprism-db/photoprism-dump-${TIMESTAMP}.sql
rm -rf /storage-files/backups/backup-memos-db/memos-dump-${TIMESTAMP}.sql
rm -rf /storage-files/backups/backup-paperless-db/paperless-dump-${TIMESTAMP}.sql
rm -rf /storage-files/backups/backup-influx-db/influxdb-dump-${TIMESTAMP}.zip

divider
telegram '"💾🏁   Backup finished"'
exit 0

