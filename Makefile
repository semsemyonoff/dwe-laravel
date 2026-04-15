MAKEFLAGS += --no-print-directory

DEVBOX_BIN := ./bin/devbox

-include .env

all: help

include make/macros.mk

.PHONY: all help env up down stop restart logs cli cli-root deploy deploy-plan reset print-test

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

up:
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
