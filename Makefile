MAKEFLAGS += --no-print-directory

DEVBOX_BIN := ./bin/devbox

-include .env

all: help

include make/macros.mk

.PHONY: all help env up down stop restart logs cli cli-root deploy deploy-plan deploy-reset print-test private_ensure_composer_cache

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

up: private_ensure_composer_cache
	@$(DEVBOX_BIN) docker up

down:
	@$(DEVBOX_BIN) docker down

stop:
	@$(DEVBOX_BIN) docker stop

restart:
	@$(DEVBOX_BIN) docker restart

logs:
	@$(DEVBOX_BIN) docker logs

cli:
	@$(DEVBOX_BIN) services cli main

cli-root:
	@$(DEVBOX_BIN) services cli main --root

deploy-plan:
	@$(DEVBOX_BIN) deploy plan

deploy: private_ensure_composer_cache
	@$(DEVBOX_BIN) deploy run
	@$(call ok,Deploy complete)

deploy-reset:
	@$(call cnf,This will stop containers and remove all service data. Continue?,,,Aborted)
	@$(DEVBOX_BIN) docker down || true
	@PROJECT=$$($(DEVBOX_BIN) docker project-name); \
		[ -n "$$PROJECT" ] || { $(call err,Could not resolve project name — cannot remove volumes safely,1); }; \
		VOLS=$$(docker volume ls -q | awk -v p="$${PROJECT}_" 'substr($$0,1,length(p))==p'); \
		[ -z "$$VOLS" ] || docker volume rm $$VOLS
	@rm -rf services/
	@$(call ok,Reset complete)

private_ensure_composer_cache:
	@if docker volume inspect devbox_composer_cache >/dev/null 2>&1; then \
		$(call ok,Shared composer cache volume exists); \
	else \
		$(call inf,Creating shared composer cache volume...); \
		docker volume create devbox_composer_cache >/dev/null; \
		$(call ok,Shared composer cache volume created); \
	fi

# Demonstrate all output macros
print-test:
	@$(call ok,Everything looks good)
	@$(call warn,This is a warning message)
	@$(call inf,Starting some process...)
	@$(call err,Non-fatal error — execution continues)
	@$(call err,Fatal error — stopping now,1)
