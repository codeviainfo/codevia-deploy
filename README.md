# Codevia — Orquestación Docker de producción

Todos los comandos se ejecutan **dentro de esta carpeta `deploy/`** (o con la ruta explícita `-f deploy/docker-compose.yml` desde la raíz).

---

## Arquitectura

```
Internet :80/:443
    └─► nginx-proxy
          ├─► codeviaesp.com / www  → codevia-landing:80   (Vite+React / nginx)
          ├─► demo-restaurante.codeviaesp.com  ┐
          ├─► demo-clinica.codeviaesp.com      ├─► codevia-demos:80  (nginx, 3 estáticas por Host header)
          ├─► demo-tienda.codeviaesp.com       ┘
          ├─► hugo.codeviaesp.com  → codevia-portfolio-hugo:80 (nginx, estático)
          ├─► crm.codeviaesp.com
          │     ├─► /api/*  → codevia-crm-backend:4000     (Express API)
          │     └─► /*      → codevia-crm-frontend:5173    (Vite preview)
          ├─► cordobabets.codeviaesp.com → cordobabets-web:80
          │         (su propio nginx hace /api/ → cordobabets-api:3000)
          ├─► auditoria.codeviaesp.com   → auditoria-web:80
          │         (su propio nginx hace /api/ → auditoria-api:3000)
          └─► gw.codeviaesp.com          → auditoria-gateway:3100
                    (SSE: proxy_buffering off en vhost.d/gw…_location)

acme-companion  emite/renueva certs Let's Encrypt automáticamente

Un solo motor de PostgreSQL 16 (codevia-crm-db:5432) con una base por proyecto:
    codevia_crm · cordobabets · auditoria_ia
```

El gateway de IA es el único servicio en el camino crítico de un tercero: si se cae, los
empleados del cliente no pueden trabajar. Por eso va en su propio contenedor, separado de
su API, y se para con 60 s de gracia para no cortar respuestas a medias.

Solo `nginx-proxy` publica los puertos 80 y 443. Las apps no exponen puertos al host.

---

## Requisitos previos

1. **Docker** y **Docker Compose** v2 instalados en el servidor.
2. **Registros DNS** apuntando a la IP pública del servidor:
   | Tipo | Nombre | Valor |
   |------|--------|-------|
   | A | `codeviaesp.com` | `<IP-servidor>` |
   | A | `www.codeviaesp.com` | `<IP-servidor>` |
   | A | `crm.codeviaesp.com` | `<IP-servidor>` |
   | A | `demo-restaurante.codeviaesp.com` | `<IP-servidor>` |
   | A | `demo-clinica.codeviaesp.com` | `<IP-servidor>` |
   | A | `demo-tienda.codeviaesp.com` | `<IP-servidor>` |
   | A | `hugo.codeviaesp.com` | `<IP-servidor>` |
   | A | `cordobabets.codeviaesp.com` | `<IP-servidor>` |
   | A | `auditoria.codeviaesp.com` | `<IP-servidor>` |
   | A | `gw.codeviaesp.com` | `<IP-servidor>` |
3. **Puertos 80 y 443 abiertos** en el firewall del servidor (ver sección Firewall).

---

## Primer despliegue

```bash
# 1. Desde la carpeta deploy/
cp .env.example .env
nano .env          # rellena passwords, JWT_SECRET, etc.

# 2. Levanta todo
make up
# o: docker compose -f docker-compose.yml up -d

# 3. Comprueba el estado
make ps

# 4. Observa la emisión de certificados (tarda 1-2 min tras propagar DNS)
make certs
```

> **Importante**: los certificados solo se emiten si los tres dominios ya resuelven
> a la IP del servidor. Si el DNS aún no ha propagado, arranca primero solo el proxy:
> ```bash
> docker compose -f docker-compose.yml up -d nginx-proxy acme-companion
> # Espera propagación DNS (~5-30 min), luego:
> make up
> ```

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
make demos-up          # Levantar las 3 plantillas
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
```

### Auditoría de IA (auditoria.codeviaesp.com + gw.codeviaesp.com)

```bash
make ia-up            # API + gateway + panel
make ia-logs
make rebuild-ia
make ia-init          # solo la primera vez: crea la BD, migra y siembra
make ia-migrar        # aplica migraciones pendientes
make ia-sembrar       # recarga catálogo de modelos y consejos (idempotente)
```

**Antes del primer `make ia-up` hay que crear la clave maestra**, que es lo que cifra las
claves de API de los clientes. No está en `.env` ni en git, es un fichero montado como
secreto de Docker para que no aparezca en `docker inspect`:

```bash
mkdir -p secretos
openssl rand -base64 32 | sed 's/^/g1:/' > secretos/clave_maestra
chmod 600 secretos/clave_maestra
```

⚠️ **Guardar una copia de ese fichero fuera del servidor**, en el gestor de contraseñas.
Si se pierde, las credenciales de proveedor de todos los clientes son irrecuperables y el
servicio cae para todos a la vez. Un backup de PostgreSQL sin la clave maestra no sirve
para restaurarlas — que es, de hecho, la propiedad que se busca.

El gateway tarda en parar: tiene `stop_grace_period: 60s` porque al recibir SIGTERM espera
a que terminen los streams en curso antes de cerrar. Es a propósito.

**Copiar también `vhost.d/auditoria.codeviaesp.com`** a `/opt/codevia/deploy/vhost.d/` (y
reiniciar `nginx-proxy`). Sube a 10 MB el límite de cuerpo del panel: sin él, cuando un
empleado envíe meses de uso con el comando de auditoría, nginx-proxy lo cortará con un 413
antes de llegar a la API.

### Proxy y certificados
```bash
make certs            # Ver logs del acme-companion (estado de certificados)
make proxy-logs       # Logs en tiempo real del proxy
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
```

`rebuild-*` reconstruye la imagen y hace `up --no-deps` del servicio, sin tocar
el proxy ni la base de datos.

---

## Datos persistentes

| Volumen Docker | Contenido |
|----------------|-----------|
| `crm-postgres-data` | Base de datos PostgreSQL del CRM |
| `nginx-certs` | Certificados TLS emitidos por Let's Encrypt |
| `nginx-html` | Archivos temporales de desafío ACME |
| `nginx-acme` | Estado interno de acme.sh |
| `auditoria-cola` | Cola en disco del gateway de IA: eventos que no pudieron llegar a PostgreSQL. Se reingiere al arrancar |

Los volúmenes **sobreviven** a `make down`. Solo se pierden con:
```bash
docker compose -f docker-compose.yml down -v   # ¡BORRA los datos!
```

Para hacer backup. Ojo: en el contenedor `codevia-crm-db` conviven **tres** bases de
datos, una por proyecto. `pg_dump` de una sola no las salva todas:
```bash
# Una base concreta
docker exec codevia-crm-db pg_dump -U codevia codevia_crm > crm_$(date +%Y%m%d).sql

# Todas de golpe, que es lo que casi siempre se quiere
docker exec codevia-crm-db pg_dumpall -U codevia > todo_$(date +%Y%m%d).sql
```
El backup de `auditoria_ia` contiene las claves de API de los clientes **cifradas**. Sin
el fichero `secretos/clave_maestra` no se pueden restaurar: hay que guardar los dos.

---

## Firewall (ejecutar en el servidor Linux vía SSH)

Antes de habilitar el firewall, **asegúrate de que SSH queda permitido**:

```bash
sudo ufw status                  # ver estado actual
sudo ufw allow 22/tcp            # SSH — imprescindible antes de enable
sudo ufw allow 80/tcp            # HTTP
sudo ufw allow 443/tcp           # HTTPS
sudo ufw enable                  # activar (pedirá confirmación)
sudo ufw status                  # verificar
```

> Si el servidor usa un puerto SSH distinto al 22, cámbialo en el comando `allow`.
> Verifica el puerto con: `sudo ss -tlnp | grep sshd`

---

## Verificar certificados HTTPS

```bash
# Estado de emisión
make certs

# Prueba de conectividad HTTPS
curl -I https://codeviaesp.com
curl -I https://crm.codeviaesp.com

# Verificar emisor Let's Encrypt
echo | openssl s_client -connect codeviaesp.com:443 -servername codeviaesp.com 2>/dev/null | grep issuer
echo | openssl s_client -connect crm.codeviaesp.com:443 -servername crm.codeviaesp.com 2>/dev/null | grep issuer
```

Los certificados se renuevan automáticamente cuando quedan menos de 30 días.

---

## Notas técnicas

- **API routing del CRM**: `crm.codeviaesp.com/api/*` se enruta al backend (puerto 4000)
  mediante un override en `vhost.d/crm.codeviaesp.com`. El resto del tráfico va al
  frontend (puerto 5173). El timeout de proxy es 300s para acomodar los jobs de
  scraping con Playwright.
- **Primera build del CRM backend**: la imagen base `playwright:v1.48.0-jammy` pesa
  ~1.5 GB. La primera vez tardará varios minutos.
- **Migraciones y seed**: el backend ejecuta `prisma migrate deploy && npm run seed`
  en cada arranque. El seed es idempotente (no crea duplicados).
- **Google Places API**: si `GOOGLE_PLACES_API_KEY` está vacía, el scraper usa
  Playwright como fallback automáticamente.
