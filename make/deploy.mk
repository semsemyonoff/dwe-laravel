# Deploy targets.

.PHONY: deploy deploy-plan deploy-reset

deploy-plan:
	@$(DEVBOX_BIN) deploy plan

deploy:
	@$(DEVBOX_BIN) deploy run
	@$(call ok,Deploy complete)

deploy-reset:
	@printf "This will stop containers and remove all service data. Continue? [y/N] " && \
		read -r ans && \
		if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then \
			$(call err,Aborted); exit 1; \
		fi
	@$(MAKE) down || true
	@[ -n "$(PROJECT_FULL)" ] || { $(call err,PROJECT_FULL is empty — cannot remove volumes safely,1); }
	@VOLS=$$(docker volume ls -q | grep "^$(PROJECT_FULL)_"); \
		[ -z "$$VOLS" ] || docker volume rm $$VOLS
	@rm -rf services/
	@$(call ok,Reset complete)
