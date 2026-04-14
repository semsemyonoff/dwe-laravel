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

.PHONY: all help env up down stop restart logs cli cli-root deploy deploy-plan deploy-reset print-test

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

up:
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
	@$(DEVBOX_BIN) command run services.main.cli

cli-root:
	@$(DEVBOX_BIN) command run services.main.cli --set user=root

deploy-plan:
	@$(DEVBOX_BIN) deploy plan

deploy:
	@$(DEVBOX_BIN) deploy run
	@$(call ok,Deploy complete)

deploy-reset:
	@printf "This will stop containers and remove all service data. Continue? [y/N] " && \
		read -r ans && \
		if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then \
			$(call err,Aborted); exit 1; \
		fi
	@$(MAKE) down || true
	@[ -n "$(PROJECT_FULL)" ] || { $(call err,PROJECT_FULL is empty — cannot remove volumes safely,1); }
	@VOLS=$$(docker volume ls -q | grep "^$(PROJECT_FULL)_"); \
		[ -z "$$VOLS" ] || docker volume rm $$VOLS
	@rm -rf services/
	@$(call ok,Reset complete)

# Demonstrate all output macros
print-test:
	@$(call ok,Everything looks good)
	@$(call warn,This is a warning message)
	@$(call inf,Starting some process...)
	@$(call err,Non-fatal error — execution continues)
	@$(call err,Fatal error — stopping now,1)
