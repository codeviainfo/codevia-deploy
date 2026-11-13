# Codevia — Orquestación Docker de producción

Todos los comandos se ejecutan **dentro de esta carpeta `deploy/`**. En el servidor actual
(máquina virtual `vm-hugo` del Proxmox compartido, desde 2026-11-13) vive en
`~/stacks/codevia/deploy`, junto a los repos de cada proyecto (`../codeviacrm`,
`../CORDOBA-BETS`, etc.: el compose los construye con rutas relativas).

---

## Arquitectura

```
Internet ─► Cloudflare (HTTPS, DNS de codeviaesp.com)
              └─► Cloudflare Tunnel "tunnel-hugo"
                    └─► cloudflared (stack aparte: ~/stacks/cloudflared)
                          └─► nginx-proxy:80   (reparte por Host header)
          ├─► codeviaesp.com / www  → codevia-landing:80   (Vite+React / nginx)
          ├─► demo-restaurante.codeviaesp.com  ┐
          ├─► demo-clinica.codeviaesp.com      ├─► codevia-demos:80  (nginx, estáticas por Host header)
          ├─► demo-tienda.codeviaesp.com       │
          ├─► demo-asesoria.codeviaesp.com     ┘
          ├─► hugo.codeviaesp.com  → codevia-portfolio-hugo:80 (nginx, estático)
          ├─► crm.codeviaesp.com
          │     ├─► /api/*  → codevia-crm-backend:4000     (Express API)
          │     └─► /*      → codevia-crm-frontend:5173    (Vite preview)
          ├─► cordobabets.codeviaesp.com → cordobabets-web:80
          │         (su propio nginx hace /api/ → cordobabets-api:3000)
          └─► breakpoint.codeviaesp.com  → breakpoint-web:80
                    (su propio nginx hace /api/ → breakpoint-api:3000)

Un solo motor de PostgreSQL 16 (codevia-crm-db:5432) con una base por proyecto:
    codevia_crm · cordobabets · breakpoint
```

- **No hay puertos abiertos a internet.** `cloudflared` abre una conexión de salida hacia
  Cloudflare; el HTTPS lo pone Cloudflare. `nginx-proxy` solo escucha en
  `127.0.0.1:8088` para pruebas desde la propia máquina:
  `curl -H "Host: crm.codeviaesp.com" http://127.0.0.1:8088/`
- **IP real del visitante:** `cloudflare-realip.conf` hace que `nginx-proxy` se fíe de la
  cabecera `CF-Connecting-IP`. Sin él, todas las visitas parecen venir de `cloudflared`
  y los frenos por IP (login de Córdoba Bets / Breakpoint, tracking del CRM) meten a
  todo el mundo en el mismo saco.

---

## Requisitos previos

1. **Docker** y **Docker Compose** v2. El usuario del servidor, en el grupo `docker`.
2. El contenedor **`cloudflared`** del túnel corriendo y unido a la red `codevia-proxy-net`
   (en su `compose.yaml`: `networks: [default, codevia-proxy-net]` y la red como `external: true`).
3. Cada dominio publicado como ruta del túnel (ver abajo).

---

## Primer despliegue

```bash
# 1. Desde la carpeta deploy/
cp .env.example .env
chmod 600 .env
nano .env          # rellena passwords, JWT secrets, etc.

# 2. Levanta todo
make up

# 3. Comprueba el estado (todos "healthy")
make ps

# 4. Solo la primera vez: crea y siembra la base de Córdoba Bets
make cb-init
```

Para **mudar** el despliegue a otra máquina no hace falta sembrar: se copia la carpeta, se
levanta `crm-db`, se restaura un `pg_dumpall` (ver "Copias") y después `make up`.

---

## Publicar un dominio

En Cloudflare → **Networking → Tunnels → tunnel-hugo → Routes → Add route →
Published application**:

| Campo | Valor |
|---|---|
| Subdomain | `crm` (vacío para `codeviaesp.com`) |
| Domain | `codeviaesp.com` |
| Service URL | `http://nginx-proxy:80` |

Cloudflare crea solo el registro DNS. Si ya existe un registro `A`/`AAAA`/`CNAME` con ese
nombre, hay que borrarlo antes. Además, el contenedor tiene que declarar el dominio en
`VIRTUAL_HOST` para que `nginx-proxy` lo enrute.

---

## Comandos del día a día

### Todo junto
```bash
make up              # Levanta todos los servicios
make down            # Para y elimina contenedores (los datos persisten)
make ps              # Estado
```

### Landing page (codeviaesp.com)
```bash
make landing-up       # Levantar
make landing-down     # Parar (sin tocar el CRM)
make landing-restart  # Reiniciar
make landing-logs     # Logs en tiempo real  (Ctrl+C para salir)
make rebuild-landing  # Tras un git pull: reconstruye imagen y redeploya
```

### Demos en vivo (demo-*.codeviaesp.com)
```bash
make demos-up          # Levantar las plantillas
make demos-down        # Parar
make demos-restart     # Reiniciar
make demos-logs        # Logs en tiempo real
make rebuild-demos     # Tras un git pull: reconstruye imagen y redeploya
```

### Portfolio de Hugo (hugo.codeviaesp.com)
```bash
make hugo-up          # Levantar
make hugo-down        # Parar
make hugo-restart     # Reiniciar
make hugo-logs        # Logs en tiempo real
make rebuild-hugo     # Tras un git pull: reconstruye imagen y redeploya
```

### CRM (crm.codeviaesp.com)
```bash
make crm-up           # Levantar DB + backend + frontend
make crm-down         # Parar backend + frontend (DB sigue activa)
make crm-restart      # Reiniciar backend + frontend
make crm-logs         # Logs en tiempo real de backend y frontend
make rebuild-crm      # Tras un git pull: reconstruye y redeploya
```

### Córdoba Bets (cordobabets.codeviaesp.com)
```bash
make cb-up            # API + web
make cb-logs
make rebuild-cb
make cb-init          # solo la primera vez: crea la BD, migra y siembra
make cb-importar      # carga el histórico de Pickeando
bash poner-token-cb.sh   # guarda el token del bot de Telegram sin que se vea
```

⚠️ El bot de Telegram lee con *long polling*: **nunca puede haber dos copias con el mismo
token** (por ejemplo, el servidor y un `npm run dev` local). Telegram las hace pelear y se
pierden mensajes del canal.

### Breakpoint Tennis (breakpoint.codeviaesp.com)
```bash
make bp-up            # API + web
make bp-logs
make rebuild-bp
```
La contraseña del panel no va en `.env`: ver `BREAKPOINT-TENNIS/README.md`.

### Proxy
```bash
make proxy-logs       # Logs en tiempo real de nginx-proxy
```

---

## Actualizar tras un cambio de código

```bash
# En el servidor, dentro del directorio del proyecto:
git pull

# Luego, desde deploy/:
make rebuild-landing   # solo si cambió la landing
make rebuild-demos     # solo si cambió alguna plantilla demo
make rebuild-hugo      # solo si cambió el portfolio de Hugo
make rebuild-crm       # solo si cambió el CRM
make rebuild-cb        # solo si cambió Córdoba Bets
make rebuild-bp        # solo si cambió Breakpoint
```

`rebuild-*` reconstruye la imagen y hace `up --no-deps` del servicio, sin tocar
el proxy ni la base de datos.

---

## Datos persistentes y copias

| Volumen Docker | Contenido |
|----------------|-----------|
| `crm-postgres-data` | PostgreSQL con las tres bases: `codevia_crm`, `cordobabets`, `breakpoint` |

Sobrevive a `make down`. Solo se pierde con `docker compose down -v` (**¡BORRA los datos!**).

**Copia diaria:** `backup-bd.sh` hace un `pg_dumpall` de todas las bases en `../backups`
(`diaria-AAAAMMDD-HHMM.sql.gz`) y guarda las 14 últimas. Está en el crontab del usuario:

```
30 4 * * * /home/hugo/stacks/codevia/deploy/backup-bd.sh >> /home/hugo/stacks/codevia/backups/backup.log 2>&1
```

`make backup` lanza una copia en el momento. Restaurar (borra y recrea las bases; parar
antes las API para que no haya conexiones abiertas):

```bash
make crm-down cb-down bp-down
zcat ../backups/diaria-XXXX.sql.gz | docker exec -i codevia-crm-db sh -c 'psql -U "$POSTGRES_USER" -d postgres'
make up
```

Los dos únicos errores esperables al restaurar son `current user cannot be dropped` y
`role "codevia" already exists`.

---

## Notas técnicas

- **API routing del CRM**: `crm.codeviaesp.com/api/*` se enruta al backend (puerto 4000)
  mediante un override en `vhost.d/crm.codeviaesp.com`. El resto del tráfico va al
  frontend (puerto 5173).
- **Límite de 100 s de Cloudflare**: Cloudflare corta cualquier petición que tarde más de
  100 segundos (no es configurable en el plan gratuito). Por eso las búsquedas del
  Scraper del CRM corren en segundo plano y el frontend consulta su estado. Cualquier
  endpoint nuevo que pueda tardar debe seguir el mismo patrón.
- **Primera build del CRM backend**: la imagen lleva Chromium (Playwright) y pesa
  ~3,5 GB. La primera vez tardará varios minutos.
- **Migraciones y seed**: el backend del CRM ejecuta `prisma migrate deploy && npm run seed`
  en cada arranque. El seed es idempotente (no crea duplicados).
- **Google Places API**: si `GOOGLE_PLACES_API_KEY` está vacía, el scraper usa
  Playwright como fallback automáticamente (más lento, varios minutos por búsqueda).
