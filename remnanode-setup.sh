#!/bin/bash
set -euo pipefail

# ─── Pre-flight checks ────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo bash $0)"
    exit 1
fi

echo "=== [1/8] Установка Docker ==="
curl -fsSL https://get.docker.com | sh
echo "Docker установлен: $(docker --version)"

echo "=== [2/8] Подготовка Remnanode ==="
mkdir -p /opt/remnanode
cat > /opt/remnanode/docker-compose.yml << 'EOF'
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=""
    volumes:
      # - /dev/shm:/dev/shm:rw
      - ./geoip.dat:/usr/local/share/xray/geoip.dat:ro
      - ./geosite.dat:/usr/local/share/xray/geosite.dat:ro
      - ./ru-geoip.dat:/usr/local/share/xray/ru-geoip.dat:ro
      - ./ru-geosite.dat:/usr/local/share/xray/ru-geosite.dat:ro
      # - ./certs/cert.crt:/etc/xray/certs/cert.crt:ro
      # - ./certs/key.key:/etc/xray/certs/key.key:ro
EOF

echo "=== [3/8] Скрипт обновления геобаз + cron ==="
cat > /opt/remnanode/update-geo.sh << 'SCRIPT'
#!/bin/bash

GEO_DIR="/opt/remnanode"
LOG_FILE="/var/log/xray-geo-update.log"

echo "$(date): Starting geo update" >> "$LOG_FILE"

# Скачиваем все файлы во временные
if wget -q -O "$GEO_DIR/geoip.dat.new" \
     https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && \
   wget -q -O "$GEO_DIR/geosite.dat.new" \
     https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && \
   wget -q -O "$GEO_DIR/ru-geoip.dat.new" \
     https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat && \
   wget -q -O "$GEO_DIR/ru-geosite.dat.new" \
     https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat; then

  # Все скачалось — делаем атомарную замену
  mv "$GEO_DIR/geoip.dat.new" "$GEO_DIR/geoip.dat"
  mv "$GEO_DIR/geosite.dat.new" "$GEO_DIR/geosite.dat"
  mv "$GEO_DIR/ru-geoip.dat.new" "$GEO_DIR/ru-geoip.dat"
  mv "$GEO_DIR/ru-geosite.dat.new" "$GEO_DIR/ru-geosite.dat"

  docker restart remnanode
  echo "$(date): Update successful, container restarted" >> "$LOG_FILE"
else
  # Что-то не скачалось — чистим временные файлы
  rm -f "$GEO_DIR"/*.new
  echo "$(date): Download failed, no changes made" >> "$LOG_FILE"
fi
SCRIPT

chmod +x /opt/remnanode/update-geo.sh

# Добавляем в cron (каждый день в 4:00)
CRON_JOB="0 4 * * * /opt/remnanode/update-geo.sh"
(crontab -l 2>/dev/null | grep -v "update-geo.sh"; echo "$CRON_JOB") | crontab -

# Первый запуск геобаз
echo "Скачиваю геобазы (первый запуск)..."
/opt/remnanode/update-geo.sh

echo ""
echo "============================================"
echo "  Remnanode Готова!"
echo "============================================"
echo ""
echo "  Remnanode:      cd /opt/remnanode"
echo "  Редактировать:  nano /opt/remnanode/docker-compose.yml"
echo "  Запуск:         docker compose -f /opt/remnanode/docker-compose.yml up -d"
echo ""
echo "============================================"
