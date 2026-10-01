COMPOSE := docker compose -f docker-compose.yml

.DEFAULT_GOAL := help

.PHONY: help up down ps \
        landing-up landing-down landing-restart landing-logs rebuild-landing \
        demos-up demos-down demos-restart demos-logs rebuild-demos \
        hugo-up hugo-down hugo-restart hugo-logs rebuild-hugo \
        crm-up crm-down crm-restart crm-logs rebuild-crm \
        cb-up cb-down cb-restart cb-logs rebuild-cb cb-init cb-importar \
        ia-up ia-down ia-restart ia-logs rebuild-ia ia-init ia-migrar ia-sembrar \
        certs proxy-logs

# ─────────────────────────────────────────────
# Ayuda
# ─────────────────────────────────────────────
help:
	@echo ""
	@echo "  Comandos globales:"
	@echo "    make up              Levanta todos los servicios"
	@echo "    make down            Para y elimina todos los contenedores"
	@echo "    make ps              Estado de los servicios"
	@echo ""
	@echo "  Landing (codeviaesp.com):"
	@echo "    make landing-up      Levanta la landing"
	@echo "    make landing-down    Para la landing"
	@echo "    make landing-restart Reinicia la landing"
	@echo "    make landing-logs    Logs en tiempo real"
	@echo "    make rebuild-landing Reconstruye imagen y redeploya"
	@echo ""
	@echo "  Demos en vivo (demo-*.codeviaesp.com):"
	@echo "    make demos-up        Levanta las 3 plantillas demo"
	@echo "    make demos-down      Para las demos"
	@echo "    make demos-restart   Reinicia las demos"
	@echo "    make demos-logs      Logs en tiempo real"
	@echo "    make rebuild-demos   Reconstruye imagen y redeploya"
	@echo ""
	@echo "  Portfolio de Hugo (hugo.codeviaesp.com):"
	@echo "    make hugo-up         Levanta el portfolio"
	@echo "    make hugo-down       Para el portfolio"
	@echo "    make hugo-restart    Reinicia el portfolio"
	@echo "    make hugo-logs       Logs en tiempo real"
	@echo "    make rebuild-hugo    Reconstruye imagen y redeploya"
	@echo ""
	@echo "  CRM (crm.codeviaesp.com):"
	@echo "    make crm-up          Levanta DB + backend + frontend del CRM"
	@echo "    make crm-down        Para backend + frontend (DB queda activa)"
	@echo "    make crm-restart     Reinicia backend + frontend"
	@echo "    make crm-logs        Logs en tiempo real de backend y frontend"
	@echo "    make rebuild-crm     Reconstruye imágenes y redeploya"
	@echo ""
	@echo "  Córdoba Bets (cordobabets.codeviaesp.com):"
	@echo "    make cb-up           Levanta API + web"
	@echo "    make cb-down         Para web + API (DB queda activa)"
	@echo "    make cb-restart      Reinicia API + web"
	@echo "    make cb-logs         Logs en tiempo real"
	@echo "    make rebuild-cb      Reconstruye imágenes y redeploya"
	@echo "    make cb-init         Crea la BD, migra y siembra"
	@echo "    make cb-importar     Carga el histórico de Pickeando"
	@echo ""
	@echo "  Auditoría de IA (auditoria + gw .codeviaesp.com):"
	@echo "    make ia-up           Levanta API + gateway + panel"
	@echo "    make ia-down         Para panel + gateway + API (DB queda activa)"
	@echo "    make ia-restart      Reinicia los tres"
	@echo "    make ia-logs         Logs en tiempo real"
	@echo "    make rebuild-ia      Reconstruye imágenes y redeploya"
	@echo "    make ia-init         Crea la BD, migra y siembra (primera vez)"
	@echo "    make ia-migrar       Aplica migraciones pendientes"
	@echo "    make ia-sembrar      Recarga catálogo de modelos y consejos"
	@echo ""
	@echo "  Proxy / Certificados:"
	@echo "    make certs           Últimas 100 líneas de logs del acme-companion"
	@echo "    make proxy-logs      Logs en tiempo real del proxy y acme"
	@echo ""

# ─────────────────────────────────────────────
# Globales
# ─────────────────────────────────────────────
up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

ps:
	$(COMPOSE) ps

# ─────────────────────────────────────────────
# Landing
# ─────────────────────────────────────────────
landing-up:
	$(COMPOSE) up -d landing

landing-down:
	$(COMPOSE) stop landing

landing-restart:
	$(COMPOSE) restart landing

landing-logs:
	$(COMPOSE) logs -f landing

rebuild-landing:
	$(COMPOSE) build landing
	$(COMPOSE) up -d --no-deps landing

# ─────────────────────────────────────────────
# Demos en vivo
# ─────────────────────────────────────────────
demos-up:
	$(COMPOSE) up -d demos

demos-down:
	$(COMPOSE) stop demos

demos-restart:
	$(COMPOSE) restart demos

demos-logs:
	$(COMPOSE) logs -f demos

rebuild-demos:
	$(COMPOSE) build demos
	$(COMPOSE) up -d --no-deps demos

# ─────────────────────────────────────────────
# Portfolio de Hugo
# ─────────────────────────────────────────────
hugo-up:
	$(COMPOSE) up -d portfolio-hugo

hugo-down:
	$(COMPOSE) stop portfolio-hugo

hugo-restart:
	$(COMPOSE) restart portfolio-hugo

hugo-logs:
	$(COMPOSE) logs -f portfolio-hugo

rebuild-hugo:
	$(COMPOSE) build portfolio-hugo
	$(COMPOSE) up -d --no-deps portfolio-hugo

# ─────────────────────────────────────────────
# Córdoba Bets (web + API; la DB del CRM se inicia si hace falta)
# ─────────────────────────────────────────────
cb-up:
	$(COMPOSE) up -d cordobabets-api cordobabets-web

cb-down:
	$(COMPOSE) stop cordobabets-web cordobabets-api

cb-restart:
	$(COMPOSE) restart cordobabets-api cordobabets-web

cb-logs:
	$(COMPOSE) logs -f cordobabets-api cordobabets-web

rebuild-cb:
	$(COMPOSE) build cordobabets-api cordobabets-web
	$(COMPOSE) up -d --no-deps cordobabets-api cordobabets-web

# Crea la base de datos (solo la primera vez; si ya existe no pasa nada),
# aplica el esquema y da de alta al usuario del panel.
cb-init:
	$(COMPOSE) exec -T crm-db psql -U $$POSTGRES_USER -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$$CORDOBABETS_DB'" | grep -q 1 || \
		$(COMPOSE) exec -T crm-db psql -U $$POSTGRES_USER -d postgres -c "CREATE DATABASE $$CORDOBABETS_DB"
	$(COMPOSE) exec -T cordobabets-api npm run prisma:migrate
	$(COMPOSE) exec -T cordobabets-api npm run seed

# Carga el histórico rescatado de Pickeando. Es idempotente: relanzarlo
# actualiza los picks existentes en vez de duplicarlos.
cb-importar:
	$(COMPOSE) exec -T cordobabets-api npm run importar

# ─────────────────────────────────────────────
# CRM (backend + frontend; la DB se inicia si hace falta)
# ─────────────────────────────────────────────
crm-up:
	$(COMPOSE) up -d crm-db crm-backend crm-frontend

crm-down:
	$(COMPOSE) stop crm-frontend crm-backend

crm-restart:
	$(COMPOSE) restart crm-backend crm-frontend

crm-logs:
	$(COMPOSE) logs -f crm-backend crm-frontend

rebuild-crm:
	$(COMPOSE) build crm-backend crm-frontend
	$(COMPOSE) up -d --no-deps crm-backend crm-frontend

# ─────────────────────────────────────────────
# Auditoría de IA (API + gateway + panel)
#
# El gateway se arranca EL PRIMERO y se para EL ÚLTIMO: es el camino
# crítico de los empleados del cliente, y cada segundo que está abajo
# es gente que no puede trabajar. Además tiene stop_grace_period 60s
# en el compose, así que `ia-down` tarda: es a propósito, está
# esperando a que terminen los streams en curso.
# ─────────────────────────────────────────────
ia-up:
	$(COMPOSE) up -d crm-db auditoria-gateway auditoria-api auditoria-web

ia-down:
	$(COMPOSE) stop auditoria-web auditoria-api auditoria-gateway

ia-restart:
	$(COMPOSE) restart auditoria-api auditoria-web auditoria-gateway

ia-logs:
	$(COMPOSE) logs -f auditoria-api auditoria-gateway auditoria-web

rebuild-ia:
	$(COMPOSE) build auditoria-api auditoria-gateway auditoria-web
	$(COMPOSE) up -d --no-deps auditoria-api auditoria-gateway auditoria-web

# Crea la base de datos dentro del PostgreSQL del CRM (solo la primera
# vez; si ya existe no pasa nada), aplica el esquema y siembra el
# catálogo de modelos, los consejos y el administrador del panel.
ia-init:
	$(COMPOSE) exec -T crm-db psql -U $$POSTGRES_USER -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$$AUDITORIA_DB'" | grep -q 1 || \
		$(COMPOSE) exec -T crm-db psql -U $$POSTGRES_USER -d postgres -c "CREATE DATABASE $$AUDITORIA_DB"
	$(COMPOSE) exec -T auditoria-api npm run prisma:migrate
	$(COMPOSE) exec -T auditoria-api npm run seed

ia-migrar:
	$(COMPOSE) exec -T auditoria-api npm run prisma:migrate

# Idempotente. NO pisa precios ya existentes: si un proveedor cambia
# sus tarifas hay que añadir una fila nueva con vigenteDesde, porque
# editar la vigente reescribiría el coste histórico de los clientes.
ia-sembrar:
	$(COMPOSE) exec -T auditoria-api npm run seed

# ─────────────────────────────────────────────
# Proxy / Certificados
# ─────────────────────────────────────────────
certs:
	docker logs nginx-acme-companion --tail 100

proxy-logs:
	$(COMPOSE) logs -f nginx-proxy acme-companion
