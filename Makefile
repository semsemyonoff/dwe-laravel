MAKEFLAGS += --no-print-directory

DEVBOX_BIN := ./bin/devbox

include make/macros.mk

.PHONY: all $(MAKECMDGOALS)

all: help

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

# Demonstrate all output macros
print_test:
	@$(call ok,Everything looks good)
	@$(call warn,This is a warning message)
	@$(call inf,Starting some process...)
	@$(call err,Non-fatal error — execution continues)
	@$(call err,Fatal error — stopping now,1)
