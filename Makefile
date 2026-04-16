MAKEFLAGS += --no-print-directory

DEVBOX_BIN := ./bin/devbox

-include .env

all: help

include make/macros.mk

.PHONY: all help env up down stop restart logs cli cli-root deploy deploy-plan reset print-test

help:
	@$(DEVBOX_BIN)

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

up:
	@$(DEVBOX_BIN) up

down:
	@$(DEVBOX_BIN) down

stop:
	@$(DEVBOX_BIN) stop

restart:
	@$(DEVBOX_BIN) restart

logs:
	@$(DEVBOX_BIN) logs

cli:
	@$(DEVBOX_BIN) shell main

cli-root:
	@$(DEVBOX_BIN) shell main --root

deploy-plan:
	@$(DEVBOX_BIN) deploy plan

deploy:
	@$(DEVBOX_BIN) deploy run
	@$(call ok,Deploy complete)

reset:
	@$(DEVBOX_BIN) reset run

# Demonstrate all output macros
print-test:
	@$(call ok,Everything looks good)
	@$(call warn,This is a warning message)
	@$(call inf,Starting some process...)
	@$(call err,Non-fatal error — execution continues)
	@$(call err,Fatal error — stopping now,1)
