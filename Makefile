LIBEXECDIR ?= /usr/libexec
POLKIT_ACTIONS_DIR ?= /usr/share/polkit-1/actions
ALIS_SYSTEM_SHAREDIR ?= /usr/share/alis
TLP_CONFDIR ?= /etc/tlp.d

.PHONY: test install uninstall install-helpers
test:
	@python3 scripts/test-public-branding.py
	@python3 scripts/test-rebrand-compatibility.py
	@python3 scripts/test-plugin-metadata.py
	@python3 scripts/test-zettelkasten-failure-runtime.py
	@python3 scripts/test-host-location.py
	@python3 scripts/test-install.py
	@sh scripts/test-battery-charge-limit-helper.sh
	@bash scripts/test-thinkfan-helper.sh
	@bash scripts/test-worker-lifecycle.sh
	@sh scripts/test-tlp-settings-ui-guards.sh
	@python3 scripts/test-tlp-vendor-probes.py
	@node scripts/test-tlp-allowed-limits-parity.cjs
	@python3 scripts/test-obsidian-todo-settings.py
	@python3 scripts/test-fan-worker-contract.py
	@python3 scripts/test-thinkfan-settings.py
	@python3 scripts/test-todo-obsidian-helper.py
	@python3 scripts/test-todo-obsidian-daily-helper.py
	@python3 scripts/test-todo-obsidian-tasks-runtime.py
	@python3 scripts/test-obsidian-theme.py
	@python3 scripts/test-obsidian-worker-contracts.py
	@python3 scripts/test-obsidian-path-settings-runtime.py
	@python3 scripts/test-zettelkasten-quicknote.py
	@python3 scripts/test-zettelkasten-images.py
	@python3 scripts/test-zettelkasten-image-runtime.py
	@python3 scripts/test-qml.py
	@python3 scripts/test-host-runtime.py
	@python3 scripts/test-settings-host-runtime.py
	@python3 scripts/test-rebrand-persistence-runtime.py

install:
	@python3 scripts/install.py install
uninstall:
	@python3 scripts/install.py uninstall

# Installation never changes hardware state, stops services or writes profiles.
install-helpers:
	@set -eu; stage=$$(mktemp -d); trap 'rm -rf "$$stage"' EXIT HUP INT TERM; \
	 sed -e 's|^config_dir=.*|config_dir=$(TLP_CONFDIR)|' \
	     -e 's|^tlp_settings_schema=.*|tlp_settings_schema=$(ALIS_SYSTEM_SHAREDIR)/tlp-settings-schema.json|' \
	     assets/helpers/alis-battery-charge-limit > "$$stage/battery"; \
	 install -Dm755 "$$stage/battery" "$(DESTDIR)$(LIBEXECDIR)/alis-battery-charge-limit"; \
	 install -Dm755 assets/helpers/alis-thinkfan "$(DESTDIR)$(LIBEXECDIR)/alis-thinkfan"; \
	 sed 's|/usr/libexec/alis-battery-charge-limit|$(LIBEXECDIR)/alis-battery-charge-limit|g' assets/polkit/org.alis.battery-charge-limit.policy > "$$stage/tlp.policy"; \
	 install -Dm644 "$$stage/tlp.policy" "$(DESTDIR)$(POLKIT_ACTIONS_DIR)/org.alis.battery-charge-limit.policy"; \
	 sed 's|/usr/libexec/alis-thinkfan|$(LIBEXECDIR)/alis-thinkfan|g' assets/polkit/org.alis.thinkfan.policy > "$$stage/fan.policy"; \
	 install -Dm644 "$$stage/fan.policy" "$(DESTDIR)$(POLKIT_ACTIONS_DIR)/org.alis.thinkfan.policy"; \
	 install -Dm644 assets/tlp/tlp-settings-schema.json "$(DESTDIR)$(ALIS_SYSTEM_SHAREDIR)/tlp-settings-schema.json"
