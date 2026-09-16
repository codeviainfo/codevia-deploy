COMPOSE := docker compose -f docker-compose.yml

.DEFAULT_GOAL := help

.PHONY: help up down ps \
        landing-up landing-down landing-restart landing-logs rebuild-landing \
        demos-up demos-down demos-restart demos-logs rebuild-demos \
        hugo-up hugo-down hugo-restart hugo-logs rebuild-hugo \
        crm-up crm-down crm-restart crm-logs rebuild-crm \
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
# Proxy / Certificados
# ─────────────────────────────────────────────
certs:
	docker logs nginx-acme-companion --tail 100

proxy-logs:
	$(COMPOSE) logs -f nginx-proxy acme-companion
