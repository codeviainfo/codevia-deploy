#!/bin/bash
# Despliegue automatico "tirando" de GitHub: cada 2 minutos, desde el cron del
# usuario, mira si algun proyecto tiene commits nuevos en origin/main y, si los
# hay, los baja y reconstruye solo ese servicio.
#
# Por que asi y no con GitHub Actions entrando por SSH: desde la migracion
# (2026-11-13) la VM no admite conexiones entrantes. Abrirle una puerta a
# GitHub costaba o una tarjeta en Cloudflare Zero Trust o tocar las reglas de
# la red de Tailscale que se comparte con otras personas. Tirando desde aqui no
# hay secretos en GitHub ni puertos abiertos: el servidor solo tiene deploy
# keys de LECTURA, una por repo privado (ver ~/.ssh/config, Host github-*).
#
# Cron (crontab -e):
#   */2 * * * * <ruta>/deploy/autodespliegue.sh >/dev/null 2>&1
# A mano:
#   ./autodespliegue.sh                  revisa todos, igual que el cron
#   ./autodespliegue.sh --forzar CARPETA reconstruye aunque no haya cambios
#                                        (CARPETA = codeviacrm, CORDOBA-BETS...)
# Registro: ../autodespliegue.log. Estado: ../.autodespliegue/
#
# deploy/ NO se actualiza solo, a proposito: un cambio de compose o de
# Makefile suele venir con variables nuevas en .env, que hay que poner a mano
# antes de aplicarlo.
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

DEPLOY="$(cd "$(dirname "$0")" && pwd)"
BASE="$(dirname "$DEPLOY")"
ESTADO="$BASE/.autodespliegue"
LOG="$BASE/autodespliegue.log"
COMPOSE=(docker compose -f "$DEPLOY/docker-compose.yml")
mkdir -p "$ESTADO"

# Un despliegue a la vez: con 865 MB de RAM, dos builds simultaneos tumban la
# maquina. Si hay uno en marcha (un build del CRM tarda minutos), esta vuelta
# del cron se salta sin hacer nada.
exec 9>"$ESTADO/cerrojo"
flock -n 9 || exit 0

# El registro incluye la salida de los builds, que es lo que hace falta para
# entender un fallo. Se rota al pasar de 5 MB.
[ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 5242880 ] && mv -f "$LOG" "$LOG.1"
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date '+%F %T') $*"; }

# carpeta | servicios del compose | servicio que migra la BD ("-" = no hace
# falta) | URLs que tienen que dar 200 despues.
# El CRM no migra aqui porque su CMD ya hace "prisma migrate deploy" al
# arrancar; Cordoba Bets y Breakpoint arrancan con "node src/server.js" a secas.
PROYECTOS=(
  "codevia-landing|landing|-|https://codeviaesp.com/"
  "CODEVIA-DEMOS|demos|-|https://demo-restaurante.codeviaesp.com/ https://demo-clinica.codeviaesp.com/ https://demo-tienda.codeviaesp.com/ https://demo-asesoria.codeviaesp.com/"
  "CODEVIA-PORTFOLIO-HUGO|portfolio-hugo|-|https://hugo.codeviaesp.com/"
  "codeviacrm|crm-backend crm-frontend|-|https://crm.codeviaesp.com/ https://crm.codeviaesp.com/api/health"
  "CORDOBA-BETS|cordobabets-api cordobabets-web|cordobabets-api|https://cordobabets.codeviaesp.com/ https://cordobabets.codeviaesp.com/api/salud"
  "BREAKPOINT-TENNIS|breakpoint-api breakpoint-web|breakpoint-api|https://breakpoint.codeviaesp.com/ https://breakpoint.codeviaesp.com/api/salud"
)

# Pasa por Cloudflare, como un visitante. Reintenta ~2 min porque el backend
# del CRM tarda hasta 60 s en estar sano (migraciones + seed al arrancar).
comprobar() {
  local url code fallos=0
  for url in "$@"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --retry 12 --retry-delay 10 \
                --retry-all-errors --max-time 20 "$url")
    if [ "$code" = 200 ]; then log "   ok    $url"
    else log "   FALLO $url -> $code"; fallos=$((fallos + 1)); fi
  done
  [ "$fallos" -eq 0 ]
}

desplegar() {
  local dir="$1" servicios="$2" migra="$3" urls="$4" destino="$5"
  git -C "$BASE/$dir" reset -q --hard "$destino" || return 1
  # shellcheck disable=SC2086  # $servicios es una lista a proposito
  "${COMPOSE[@]}" build $servicios || return 1
  if [ "$migra" != "-" ]; then
    # Con la imagen NUEVA y antes de cambiar el contenedor: si la migracion
    # falla, la web sigue sirviendo la version anterior. "migrate deploy" es
    # idempotente: sin migraciones pendientes no hace nada.
    "${COMPOSE[@]}" run --rm --no-deps -T "$migra" npm run prisma:migrate || return 1
  fi
  # shellcheck disable=SC2086
  "${COMPOSE[@]}" up -d --no-deps $servicios || return 1
  # shellcheck disable=SC2086
  comprobar $urls
}

FORZAR=""
[ "${1:-}" = "--forzar" ] && FORZAR="${2:-}"
limpiar=0

for p in "${PROYECTOS[@]}"; do
  IFS='|' read -r dir servicios migra urls <<<"$p"
  repo="$BASE/$dir"
  [ -d "$repo/.git" ] || { log "!! $dir no es un clon de git, se salta"; continue; }

  # Lo desplegado se apunta aparte en vez de fiarse de HEAD: si un build falla,
  # HEAD ya apunta al commit nuevo pero el contenedor sigue con el anterior.
  # La primera vez se da por buena la version que esta corriendo.
  [ -f "$ESTADO/$dir.desplegado" ] || git -C "$repo" rev-parse HEAD >"$ESTADO/$dir.desplegado"

  if ! timeout 60 git -C "$repo" fetch -q origin main 2>"$ESTADO/$dir.error"; then
    # Se avisa una vez, no cada 2 minutos, si GitHub o la red fallan.
    [ -f "$ESTADO/$dir.sin-red" ] || log "!! $dir: no se pudo leer GitHub: $(tail -1 "$ESTADO/$dir.error")"
    touch "$ESTADO/$dir.sin-red"
    continue
  fi
  rm -f "$ESTADO/$dir.sin-red"

  objetivo=$(git -C "$repo" rev-parse origin/main)
  desplegado=$(cat "$ESTADO/$dir.desplegado")
  if [ "$FORZAR" != "$dir" ]; then
    [ "$objetivo" = "$desplegado" ] && continue
    # Un commit que ya fallo no se reintenta en bucle (cada intento es un
    # build entero): se espera al siguiente commit o a --forzar.
    [ "$objetivo" = "$(cat "$ESTADO/$dir.fallido" 2>/dev/null)" ] && continue
  fi

  # Un fichero tocado a mano en el servidor no se pisa sin avisar.
  if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
    if [ "$(cat "$ESTADO/$dir.avisado" 2>/dev/null)" != "$objetivo" ]; then
      log "!! $dir: hay cambios hechos a mano en el servidor; no se despliega ${objetivo:0:7} hasta limpiarlos"
      echo "$objetivo" >"$ESTADO/$dir.avisado"
    fi
    continue
  fi

  # Commits que solo tocan CI o documentacion: se bajan sin reconstruir.
  if [ "$FORZAR" != "$dir" ] && git -C "$repo" cat-file -e "$desplegado^{commit}" 2>/dev/null &&
     [ -z "$(git -C "$repo" diff --name-only "$desplegado" "$objetivo" -- . \
             ':!.github' ':!*.md' ':!docs' ':!docker-compose.local.yml')" ]; then
    git -C "$repo" reset -q --hard "$objetivo"
    echo "$objetivo" >"$ESTADO/$dir.desplegado"
    log "== $dir: ${objetivo:0:7} solo cambia CI o documentacion, sin reconstruir"
    continue
  fi

  log "== $dir: desplegando ${desplegado:0:7} -> ${objetivo:0:7}"
  inicio=$(date +%s)
  if desplegar "$dir" "$servicios" "$migra" "$urls" "$objetivo"; then
    echo "$objetivo" >"$ESTADO/$dir.desplegado"
    rm -f "$ESTADO/$dir.fallido"
    log "== $dir: desplegado ${objetivo:0:7} en $(($(date +%s) - inicio)) s"
  else
    echo "$objetivo" >"$ESTADO/$dir.fallido"
    log "!! $dir: FALLO al desplegar ${objetivo:0:7}; no se reintenta hasta el proximo commit (o --forzar $dir)"
  fi
  limpiar=1
done

if [ "$limpiar" = 1 ]; then
  # Solo restos sin uso: no toca contenedores en marcha, imagenes en uso ni
  # volumenes. Se guarda 1 GB de cache para que el siguiente build sea rapido.
  docker image prune -f >/dev/null
  docker builder prune -f --reserved-space 1GB >/dev/null 2>&1 || true
fi
