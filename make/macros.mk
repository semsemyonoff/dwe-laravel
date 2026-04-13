# All user-visible output must go through these macros so that formatting
# and color are controlled by devbox-cli, not by Make recipes directly.
#
# Macro argument conventions:
#   <1> — required argument
#   [2] — optional argument
#   [2] (default) — optional argument with default value
#
# Usage:
#   @$(call ok,Done)
#   @$(call err,Something failed,1)
#   @$(call warn,Check your config)
#   @$(call inf,Starting up...)

# print successful (green) message
#   <1> — message
define ok
$(DEVBOX_BIN) print success "$(1)"
endef

# print error (red) message
#   <1> — message
#   [2] — exit code; if provided, execution stops with that code
define err
$(DEVBOX_BIN) print error "$(1)"$(if $(strip $(2)), --exit-code $(2),)
endef

# print warning (yellow) message
#   <1> — message
define warn
$(DEVBOX_BIN) print warning "$(1)"
endef

# print info (blue) message
#   <1> — message
define inf
$(DEVBOX_BIN) print info "$(1)"
endef

# Check if a container is running. Exits 0 if running, 1 if not.
#   <1> — container name (without project prefix, e.g. app-main)
define container-running
docker ps -q --filter "name=^$(PROJECT_FULL)-$(1)$$" --filter "status=running" | grep -q .
endef
