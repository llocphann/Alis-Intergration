LIBEXECDIR ?= /usr/libexec
POLKIT_ACTIONS_DIR ?= /usr/share/polkit-1/actions
ALIS_SYSTEM_SHAREDIR ?= /usr/share/alis
TLP_CONFDIR ?= /etc/tlp.d

.PHONY: test test-fast build-nexus install uninstall install-helpers
build-nexus:
	@CARGO_TARGET_DIR=/tmp/alis-nexus-target cargo build --manifest-path native/Cargo.toml --release --offline --locked
	@mkdir -p assets/bin
	@cp /tmp/alis-nexus-target/release/alis-nexus assets/bin/alis-nexus
	@chmod 0755 assets/bin/alis-nexus

test:
	@python3 scripts/run-tests.py

test-fast:
	@python3 scripts/run-tests.py --fast

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
