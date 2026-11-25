#!/bin/bash
# Activa el bot de Telegram de Breakpoint Tennis. Uso: bash poner-bot-bp.sh
#
#  1. Pide el token de BotFather sin que se vea en pantalla y lo comprueba.
#  2. Espera a que le escribas /start al bot para saber tu id de chat: ese chat
#     sera el UNICO que pueda manejarlo (ver pendientes, resolver, borrar).
#  3. Guarda los dos en el .env (con copia antes) y reinicia breakpoint-api.
#
# El canal (BREAKPOINT_TELEGRAM_CANAL) es aparte y opcional: sin el, el bot no
# registra solo lo que se publica, pero el chat privado funciona igual.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV="$DIR/.env"

# El token va por stdin a curl, nunca en la linea de comandos (la veria `ps`).
telegram() {
  local datos=${2:-'{}'}
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$T" "$1" \
    | curl -s --max-time 40 -K - -H 'content-type: application/json' -d "$datos"
}
# Sin jq en el servidor: el JSON de Telegram se lee con python3.
# Nombre del bot si el token vale; nada si no.
nombre_bot() {
  python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit()
if d.get("ok"): print(d["result"]["username"])
'
}
# El ultimo chat privado que le ha escrito al bot: "id nombre @usuario".
quien_escribio() {
  python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit()
for u in reversed(d.get("result", [])):
    c = (u.get("message") or {}).get("chat", {})
    if c.get("type") == "private":
        print(c["id"], c.get("first_name", ""), "@" + c.get("username", "-"))
        break
'
}

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

# Con long polling solo una copia puede leer cada bot: si fuese el de Cordoba
# Bets, los dos se pelearian y se perderian mensajes de los dos canales.
CB=$(sed -n 's/^CORDOBABETS_TELEGRAM_TOKEN=//p' "$ENV")
if [ -n "$CB" ] && [ "${CB%%:*}" = "${T%%:*}" ]; then
  echo 'Ese token es el del bot de Córdoba Bets. Crea otro bot en @BotFather para Breakpoint.'
  exit 1
fi

BOT=$(telegram getMe | nombre_bot)
if [ -z "$BOT" ]; then
  echo 'Telegram no acepta ese token. Cópialo otra vez de @BotFather. No se ha guardado nada.'
  exit 1
fi
echo "Token correcto: el bot es @$BOT."
echo
echo "Ahora, en Telegram, abre @$BOT y escríbele /start. Te espero 3 minutos..."

# Sin offset: getUpdates no confirma nada, asi que cuando arranque la API
# tambien le llegara tu /start y te contestara con la ayuda.
CHAT=''
FIN=$((SECONDS + 180))
while [ -z "$CHAT" ] && [ $SECONDS -lt $FIN ]; do
  CHAT=$(telegram getUpdates '{"timeout":25,"allowed_updates":["message"]}' | quien_escribio)
done
if [ -z "$CHAT" ]; then
  echo "No me ha llegado ningún mensaje en 3 minutos. Escríbele /start a @$BOT y vuelve a ejecutar el comando."
  exit 1
fi

ID=${CHAT%% *}
echo "Me ha escrito: ${CHAT#* } (id $ID)."
read -rp '¿Eres tú? Solo ese chat podrá manejar el bot [s/N]: ' OK
case "$OK" in s|S|si|Si|sí|Sí) ;; *) echo 'No se ha guardado nada.'; exit 1 ;; esac

cp -p "$ENV" "$ENV.bak-$(date +%Y%m%d%H%M%S)"
sed -i '/^BREAKPOINT_TELEGRAM_TOKEN=/d;/^BREAKPOINT_TELEGRAM_AVISOS=/d' "$ENV"
printf 'BREAKPOINT_TELEGRAM_TOKEN=%s\nBREAKPOINT_TELEGRAM_AVISOS=%s\n' "$T" "$ID" >> "$ENV"
docker compose -f "$DIR/docker-compose.yml" config --quiet || { echo 'El .env ha quedado mal: revisa la copia .bak.'; exit 1; }
echo 'Guardado. Reiniciando la API de Breakpoint...'

docker compose -f "$DIR/docker-compose.yml" up -d --no-deps breakpoint-api >/dev/null 2>&1
for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' breakpoint-api 2>/dev/null)" = healthy ] && break
  sleep 2
done
docker logs --since 2m breakpoint-api 2>&1 | grep '\[telegram\]'
echo
echo "Listo. En el chat con @$BOT: /pendientes para resolver y /stats para las cifras."
