# Deploy targets.

.PHONY: deploy deploy_reset

deploy:
	@$(call inf,Generating .env...)
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)
	@$(call inf,Running deploy plan...)
	@$(DEVBOX_BIN) deploy plan --format=shell | sh
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
