.PHONY: install-git-hooks ship

LEFTHOOK ?= lefthook

install-git-hooks:
	$(LEFTHOOK) install

ship:
	@test -n "$(strip $(SVC))" || { echo "SVC is required" >&2; exit 2; }
	./scripts/local/ship.sh $(SVC)
