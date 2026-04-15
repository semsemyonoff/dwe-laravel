MAKEFLAGS += --no-print-directory

DEVBOX_BIN := ./bin/devbox

-include .env

PROJECT_PREFIX ?= devbox
PROJECT_NAME   ?= laravel
PROJECT_FULL    = $(PROJECT_PREFIX)-$(PROJECT_NAME)

all: help

include make/macros.mk

# Compose file list is computed by the CLI based on enabled tools/services.
ifneq ($(wildcard $(DEVBOX_BIN)),)
COMPOSE_FILES := $(shell $(DEVBOX_BIN) compose files | sed 's/^/-f /' | tr '\n' ' ')
ifeq ($(strip $(COMPOSE_FILES)),)
$(warning $(DEVBOX_BIN) compose files returned empty — config invalid.)
endif
else
COMPOSE_FILES :=
endif

DOCKER_COMPOSE_FLAGS ?= --ansi always --progress tty
DOCKER_COMPOSE = docker compose $(DOCKER_COMPOSE_FLAGS) -p $(PROJECT_FULL) $(COMPOSE_FILES)

.PHONY: all help env up down stop restart logs cli cli-root deploy deploy-plan deploy-reset print-test private_ensure_composer_cache

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

up: private_ensure_composer_cache
	@$(DOCKER_COMPOSE) up -d --remove-orphans

down:
	@$(DOCKER_COMPOSE) down

stop:
	@$(DOCKER_COMPOSE) stop

restart:
	@$(DOCKER_COMPOSE) restart

logs:
	@$(DOCKER_COMPOSE) logs -f

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
	@$(MAKE) down || true
	@[ -n "$(PROJECT_FULL)" ] || { $(call err,PROJECT_FULL is empty — cannot remove volumes safely,1); }
	@VOLS=$$(docker volume ls -q | awk -v p="$(PROJECT_FULL)_" 'substr($$0,1,length(p))==p'); \
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
