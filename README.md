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
          └─► crm.codeviaesp.com
                ├─► /api/*  → codevia-crm-backend:4000     (Express API)
                └─► /*      → codevia-crm-frontend:5173    (Vite preview)

acme-companion  emite/renueva certs Let's Encrypt automáticamente

codevia-crm-backend ──Prisma──► codevia-crm-db:5432 (PostgreSQL 16)
```

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

### CRM (crm.codeviaesp.com)
```bash
make crm-up           # Levantar DB + backend + frontend
make crm-down         # Parar backend + frontend (DB sigue activa)
make crm-restart      # Reiniciar backend + frontend
make crm-logs         # Logs en tiempo real de backend y frontend
make rebuild-crm      # Tras un git pull: reconstruye y redeploya
```

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

Los volúmenes **sobreviven** a `make down`. Solo se pierden con:
```bash
docker compose -f docker-compose.yml down -v   # ¡BORRA los datos!
```

Para hacer backup de la base de datos:
```bash
docker exec codevia-crm-db pg_dump -U codevia codevia_crm > backup_$(date +%Y%m%d).sql
```

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
