# Deploy targets.

.PHONY: deploy deploy_reset

deploy:
	@$(call inf,Running deploy plan...)
	@$(DEVBOX_BIN) deploy plan --format=shell > /tmp/.devbox-plan.sh && sh /tmp/.devbox-plan.sh; _code=$$?; rm -f /tmp/.devbox-plan.sh; exit $$_code
	@$(call ok,Deploy complete)

deploy_reset:
	@printf "This will stop containers and remove all service data. Continue? [y/N] " && \
		read -r ans && \
		if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then \
			$(call err,Aborted); exit 1; \
		fi
	@$(MAKE) stop || true
	@VOLS=$$(docker volume ls -q --filter name=$(PROJECT_FULL)_); \
		[ -z "$$VOLS" ] || docker volume rm $$VOLS
	@rm -rf services/*
	@$(call ok,Reset complete)
