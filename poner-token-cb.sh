#!/bin/bash
# Guarda el token del bot de Telegram de Cordoba Bets en el .env de esta carpeta
# sin que se vea en pantalla. Uso: bash poner-token-cb.sh
# Despues: docker compose up -d --no-deps cordobabets-api
ENV="$(cd "$(dirname "$0")" && pwd)/.env"
echo
read -rsp 'Pega el token del bot y pulsa Enter (al pegar no se ve nada, es normal): ' T
echo
T=$(printf %s "$T" | tr -d '\r[:space:]')
if [ -z "$T" ]; then
  echo 'No ha llegado nada. Vuelve a ejecutar el comando y pega con clic derecho.'
  exit 1
fi
if ! printf %s "$T" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]{30,}$'; then
  echo "Eso no parece un token de BotFather (${#T} caracteres). No se ha guardado nada."
  exit 1
fi
sed -i '/^CORDOBABETS_TELEGRAM_TOKEN=/d' "$ENV"
echo "CORDOBABETS_TELEGRAM_TOKEN=$T" >> "$ENV"
echo "Guardado correctamente (bot ${T%%:*})."
