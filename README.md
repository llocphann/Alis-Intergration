# Hadalird

Optional small and medium application integrations for Hadalis: TLP, Thinkfan
and Obsidian. Hadalis owns generic Battery, Power Profiles, Todo, Notes,
configuration and UI primitives. Hadalird owns the integration workers,
application-specific settings, byte-safe vault helpers and privileged helper
payloads. Existing integration preferences and application data are retained.

Install a committed revision with `make install`. Installation does not enable
an integration, launch Obsidian, change fan/charge policies, or stop existing
system services. Each integration loads one disposable QML tree when explicitly
enabled in Hadalis. Missing packages report unavailable rather than claiming an
operation succeeded. `make uninstall` deactivates only this package's owned
link; releases, user configuration, vaults and system services are preserved.

Privileged helper installation is separate: `sudo make install-helpers`.
This installs helper/polkit/schema files and does not enable services or create
TLP configuration overrides. Prefixes and `DESTDIR` are supported for packaging.
`LIBEXECDIR`, `POLKIT_ACTIONS_DIR`, `INIR_SYSTEM_SHAREDIR` and `TLP_CONFDIR`
control helper, policy, schema and profile locations; helper installation does
not create profile directories or overrides. TLP (including its optional
Radio Device Wizard), Thinkfan and Obsidian remain separately installed apps.

Run `make test` for scoped filesystem/helper and installation contracts.
Native tests use the sibling `Hadalis` checkout by default; set
`HADALIS_ROOT=/path/to/Hadalis` for another location. They require Quickshell,
Qt 6 and private Niri, and use synthetic vaults and injected status helpers.
Initial provenance is recorded in `manifest.json`. All active Integration feature, rework and bug tasks are tracked **in
[Alis-Intergration GitHub Issues](https://github.com/llocphann/Alis-Intergration/issues?q=is%3Aissue+is%3Aopen)**. Alis core shell/host Issues and Companion Issues stay in their own repositories; link cross-repo dependencies rather than creating duplicate Issues.
Search existing Alis-Intergration Issues first (including closed and historical Alis MOVED links); create one only for a new outcome. Keep its Goal,
necessary constraints and Done-when criteria brief; reuse `bug`, `enhancement`
or `documentation` plus the primary `area:integration`. Add colored
`complexity:high` only for genuinely difficult native, privileged or cross-repo
work, and a `status:*` label only when applicable; do not use obsolete `type:*`. Update it directly at
meaningful milestones with actual Alis `dev` / Integration `main` SHAs, test
results and any Owner/permission gate. A bot-complete Issue remains open until
Owner verification. **Do not write task progress to Markdown.** This repository
still owns its optional QML services, Settings, helpers and package-local tests;
no user vault, privileged settings or existing data is changed by task tracking.

Classic and Waffle TLP editors and Obsidian task/capture settings are owned
here. Hadalis retains navigation, optional loaders, generic Battery controls
and the preserved internal Todo store. The version 0.2 settings entrypoints
are additive for host API 1; update Hadalird before the corresponding host
cutover. Integration enable switches remain off by default.
