MAKEFLAGS += --no-print-directory

DEVBOX_BIN := devbox

-include .env

all: help

include make/macros.mk

.PHONY: all help env run up down stop restart logs cli cli-root deploy deploy-plan reset print-test

help:
	@$(DEVBOX_BIN)

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

# run/stop/restart drive the full lifecycle pipeline (devbox/lifecycle.yml: update probe + hooks + message).
run:
	@$(DEVBOX_BIN) run

# up/down are thin compose passthroughs (no hooks, no probe).
up:
	@$(DEVBOX_BIN) docker up

down:
	@$(DEVBOX_BIN) docker down

# stop/restart delegate to lifecycle pipelines (devbox/lifecycle.yml: hooks + docker down/up + final message).
# For the raw compose stop/restart use: devbox docker stop / devbox docker restart.
stop:
	@$(DEVBOX_BIN) stop

restart:
	@$(DEVBOX_BIN) restart

logs:
	@$(DEVBOX_BIN) docker logs

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
	@$(call ok,Reset complete)

# Demonstrate all output macros
print-test:
	@$(call ok,Everything looks good)
	@$(call warn,This is a warning message)
	@$(call inf,Starting some process...)
	@$(call err,Non-fatal error — execution continues)
	@$(call err,Fatal error — stopping now,1)
