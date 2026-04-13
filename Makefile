MAKEFLAGS += --no-print-directory

DEVBOX_BIN := ./bin/devbox

-include .env

PROJECT_PREFIX ?= devbox
PROJECT_NAME   ?= laravel
PROJECT_FULL    = $(PROJECT_PREFIX)-$(PROJECT_NAME)

all: help

include make/macros.mk
include make/compose.mk
include make/service.mk
include make/deploy.mk

.PHONY: all $(MAKECMDGOALS)

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

# Demonstrate all output macros
print-test:
	@$(call ok,Everything looks good)
	@$(call warn,This is a warning message)
	@$(call inf,Starting some process...)
	@$(call err,Non-fatal error — execution continues)
	@$(call err,Fatal error — stopping now,1)
