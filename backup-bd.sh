#!/bin/bash
# Copia diaria de TODAS las bases del PostgreSQL compartido (CRM, Cordoba Bets,
# Breakpoint) en ../backups, junto a esta carpeta deploy/. Guarda las 14 ultimas.
#
# Instalada en el crontab del usuario del servidor:
#   30 4 * * * <ruta>/deploy/backup-bd.sh >> <ruta>/backups/backup.log 2>&1
#
# Restaurar (borra y recrea las bases; parar antes las API):
#   zcat FICHERO.sql.gz | docker exec -i codevia-crm-db sh -c 'psql -U "$POSTGRES_USER" -d postgres'
set -euo pipefail
DIR="${BACKUP_DIR:-$(cd "$(dirname "$0")/.." && pwd)/backups}"
mkdir -p "$DIR"
F="$DIR/diaria-$(date +%Y%m%d-%H%M).sql.gz"
docker exec codevia-crm-db sh -c 'pg_dumpall -U "$POSTGRES_USER" --clean --if-exists' | gzip > "$F.tmp"
mv "$F.tmp" "$F"
chmod 600 "$F"
find "$DIR" -name "diaria-*.sql.gz" -mtime +14 -delete
echo "$(date "+%F %T") ok $(du -h "$F" | cut -f1) $F"
