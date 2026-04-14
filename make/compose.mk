# Compose file list is computed by the CLI based on enabled tools/services.
# This avoids hardcoding overlay logic in Make.
ifneq ($(wildcard $(DEVBOX_BIN)),)
COMPOSE_FILES := $(shell $(DEVBOX_BIN) compose files | sed 's/^/-f /' | tr '\n' ' ')
ifeq ($(strip $(COMPOSE_FILES)),)
$(warning $(DEVBOX_BIN) compose files returned empty — config invalid.)
endif
else
COMPOSE_FILES :=
endif

# Force Compose's interactive progress renderer for local terminal usage.
DOCKER_COMPOSE_FLAGS ?= --ansi always --progress tty
DOCKER_COMPOSE = docker compose $(DOCKER_COMPOSE_FLAGS) -p $(PROJECT_FULL) $(COMPOSE_FILES)

.PHONY: up down stop restart logs

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
