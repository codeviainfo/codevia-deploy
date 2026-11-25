#!/bin/bash
# Activa el bot de Telegram de Breakpoint Tennis. Uso: bash poner-bot-bp.sh
#
#  1. Pide el token de BotFather sin que se vea en pantalla y lo comprueba.
#  2. Espera a que le escribas /start al bot para saber tu id de chat: ese chat
#     sera el UNICO que pueda manejarlo (ver pendientes, resolver, borrar).
#  3. Opcional: espera a que le reenvies un mensaje del canal para saber su id.
#     Con el, cada pick que se publique en el canal se registra solo en la web
#     (el bot tiene que ser administrador del canal).
#  4. Lo guarda en el .env (con copia antes), reinicia breakpoint-api y el bot
#     te saluda.
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
# El ultimo canal del que se le ha reenviado un mensaje: "id titulo".
canal_reenviado() {
  python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit()
for u in reversed(d.get("result", [])):
    m = u.get("message") or {}
    o = m.get("forward_origin") or {}
    c = o.get("chat") if o.get("type") == "channel" else m.get("forward_from_chat")
    if c and c.get("type") == "channel":
        print(c["id"], c.get("title", ""))
        break
'
}
# Id del ultimo update, para darlos todos por leidos al terminar.
ultimo_update() {
  python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit()
r = d.get("result", [])
if r: print(r[-1]["update_id"])
'
}
# Repite getUpdates hasta que `$1` (una de las funciones de arriba) encuentre
# algo o pasen `$2` segundos.
esperar() {
  local fin=$((SECONDS + $2)) r=''
  while [ -z "$r" ] && [ $SECONDS -lt $fin ]; do
    r=$(telegram getUpdates '{"timeout":20,"allowed_updates":["message"]}' | "$1")
    # Si Telegram o la red fallan, curl vuelve al instante: sin esto, bucle a tope.
    [ -z "$r" ] && sleep 2
  done
  printf %s "$r"
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

CHAT=$(esperar quien_escribio 180)
if [ -z "$CHAT" ]; then
  echo "No me ha llegado ningún mensaje en 3 minutos. Escríbele /start a @$BOT y vuelve a ejecutar el comando."
  exit 1
fi
ID=${CHAT%% *}
echo "Me ha escrito: ${CHAT#* } (id $ID)."
read -rp '¿Eres tú? Solo ese chat podrá manejar el bot [s/N]: ' OK
case "$OK" in s|S|si|Si|sí|Sí) ;; *) echo 'No se ha guardado nada.'; exit 1 ;; esac

echo
echo 'Opcional, para que cada pick que publiques en el canal se registre solo en la web:'
echo "  1. Añade a @$BOT como administrador del canal (en el canal: Administradores > Añadir)."
echo "  2. Reenvíale a @$BOT cualquier mensaje del canal."
read -rp 'Pulsa Enter cuando lo hayas reenviado, o escribe no para saltártelo: ' R
CANAL=''
case "$R" in
  n|N|no|No|NO) echo 'Sin canal: los picks se dan de alta en el panel o escribiéndoselos al bot.' ;;
  *)
    CANAL=$(esperar canal_reenviado 120)
    if [ -n "$CANAL" ]; then echo "Canal: ${CANAL#* } (id ${CANAL%% *})."
    else echo 'No me ha llegado ningún mensaje reenviado del canal. Sigo sin canal; se puede añadir luego.'; fi
    ;;
esac

cp -p "$ENV" "$ENV.bak-$(date +%Y%m%d%H%M%S)"
sed -i '/^BREAKPOINT_TELEGRAM_TOKEN=/d;/^BREAKPOINT_TELEGRAM_AVISOS=/d' "$ENV"
printf 'BREAKPOINT_TELEGRAM_TOKEN=%s\nBREAKPOINT_TELEGRAM_AVISOS=%s\n' "$T" "$ID" >> "$ENV"
if [ -n "$CANAL" ]; then
  sed -i '/^BREAKPOINT_TELEGRAM_CANAL=/d' "$ENV"
  printf 'BREAKPOINT_TELEGRAM_CANAL=%s\n' "${CANAL%% *}" >> "$ENV"
fi
docker compose -f "$DIR/docker-compose.yml" config --quiet || { echo 'El .env ha quedado mal: revisa la copia .bak.'; exit 1; }

# Lo escrito durante la configuracion (/start, el reenvio) ya esta atendido:
# se da por leido para que la API no lo procese otra vez al arrancar.
U=$(telegram getUpdates '{"timeout":0}' | ultimo_update)
[ -n "$U" ] && telegram getUpdates "{\"offset\":$((U + 1)),\"timeout\":0}" >/dev/null

echo 'Guardado. Reiniciando la API de Breakpoint...'
docker compose -f "$DIR/docker-compose.yml" up -d --no-deps breakpoint-api >/dev/null 2>&1
for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' breakpoint-api 2>/dev/null)" = healthy ] && break
  sleep 2
done
docker logs --since 2m breakpoint-api 2>&1 | grep '\[telegram\]'
telegram sendMessage "{\"chat_id\":$ID,\"text\":\"✅ Bot de Breakpoint activado.\\n\\n/pendientes para ver y resolver los picks.\\n/ayuda para ver cómo registrarlos desde aquí.\"}" >/dev/null
echo
echo "Listo. Te he escrito en @$BOT: /pendientes para resolver y /stats para las cifras."
