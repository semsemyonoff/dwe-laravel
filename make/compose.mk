# Compose file list is computed by the CLI based on enabled tools/services.
# This avoids hardcoding overlay logic in Make.
COMPOSE_FILES := $(shell $(DEVBOX_BIN) compose files | sed 's/^/-f /' | tr '\n' ' ')
ifeq ($(strip $(COMPOSE_FILES)),)
$(error $(DEVBOX_BIN) compose files returned empty — binary missing or config invalid. Build with: cd devbox-cli && make build)
endif

DOCKER_COMPOSE = docker compose -p $(PROJECT_FULL) $(COMPOSE_FILES)

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
