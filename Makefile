LIBEXECDIR ?= /usr/libexec
POLKIT_ACTIONS_DIR ?= /usr/share/polkit-1/actions
ALIS_SYSTEM_SHAREDIR ?= /usr/share/alis
TLP_CONFDIR ?= /etc/tlp.d

.PHONY: test build-nexus install uninstall install-helpers
build-nexus:
	@CARGO_TARGET_DIR=/tmp/alis-nexus-target cargo build --manifest-path native/Cargo.toml --release --offline --locked
	@mkdir -p assets/bin
	@cp /tmp/alis-nexus-target/release/alis-nexus assets/bin/alis-nexus
	@chmod 0755 assets/bin/alis-nexus

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
	@python3 scripts/test-nexus-todo-settings.py
	@python3 scripts/test-fan-worker-contract.py
	@python3 scripts/test-thinkfan-settings.py
	@python3 scripts/test-todo-nexus-helper.py
	@python3 scripts/test-todo-nexus-daily-helper.py
	@python3 scripts/test-todo-nexus-tasks-runtime.py
	@python3 scripts/test-nexus-theme.py
	@python3 scripts/test-nexus-worker-contracts.py
	@python3 scripts/test-nexus-path-settings-runtime.py
	@python3 scripts/test-zettelkasten-quicknote.py
	@python3 scripts/test-zettelkasten-images.py
	@python3 scripts/test-zettelkasten-image-runtime.py
	@python3 scripts/test-nexus.py
	@python3 scripts/test-nexus-graph-freeze-runtime.py
	@python3 scripts/test-nexus-globe-freeze-runtime.py
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
	 if [ "$(TLP_CONFDIR)" = "/etc/tlp.d" ] && [ "$(ALIS_SYSTEM_SHAREDIR)" = "/usr/share/alis" ]; then \
	     cp assets/helpers/alis-battery-charge-limit "$$stage/battery"; \
	 else \
	     sed -e 's|^config_dir=.*|config_dir=$(TLP_CONFDIR)|' \
	         -e 's|^tlp_settings_config_file=.*|tlp_settings_config_file=$(TLP_CONFDIR)/99-alis-tlp-settings.conf|' \
	         -e 's|^tlp_settings_schema=.*|tlp_settings_schema=$(ALIS_SYSTEM_SHAREDIR)/tlp-settings-schema.json|' \
	         -e '/^\[ -r "\$$tlp_settings_schema" \]/d' \
	         assets/helpers/alis-battery-charge-limit > "$$stage/battery"; \
	 fi; \
	 install -Dm755 "$$stage/battery" "$(DESTDIR)$(LIBEXECDIR)/alis-battery-charge-limit"; \
	 install -Dm755 assets/helpers/alis-thinkfan "$(DESTDIR)$(LIBEXECDIR)/alis-thinkfan"; \
	 sed 's|/usr/libexec/alis-battery-charge-limit|$(LIBEXECDIR)/alis-battery-charge-limit|g' assets/polkit/org.alis.battery-charge-limit.policy > "$$stage/tlp.policy"; \
	 install -Dm644 "$$stage/tlp.policy" "$(DESTDIR)$(POLKIT_ACTIONS_DIR)/org.alis.battery-charge-limit.policy"; \
	 sed 's|/usr/libexec/alis-thinkfan|$(LIBEXECDIR)/alis-thinkfan|g' assets/polkit/org.alis.thinkfan.policy > "$$stage/fan.policy"; \
	 install -Dm644 "$$stage/fan.policy" "$(DESTDIR)$(POLKIT_ACTIONS_DIR)/org.alis.thinkfan.policy"; \
	 install -Dm644 assets/tlp/tlp-settings-schema.json "$(DESTDIR)$(ALIS_SYSTEM_SHAREDIR)/tlp-settings-schema.json"
