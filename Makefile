.PHONY: install-git-hooks

LEFTHOOK ?= lefthook

install-git-hooks:
	$(LEFTHOOK) install
