# Deploy targets.

.PHONY: deploy deploy-reset

deploy:
	@$(call inf,Running deploy plan...)
	@_plan=$$(mktemp) || exit 1; $(DEVBOX_BIN) deploy plan --format=shell > $$_plan && sh $$_plan; _code=$$?; rm -f $$_plan; exit $$_code
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
