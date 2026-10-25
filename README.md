# Alis-Intergration

Optional small and medium application integrations for Alis: TLP, Thinkfan
and Obsidian. Alis owns generic Battery, Power Profiles, Todo, Notes,
configuration and UI primitives. Alis-Intergration owns the integration workers,
application-specific settings, byte-safe vault helpers and privileged helper
payloads. Existing integration preferences and application data are retained.

Install a committed revision with `make install`. Installation does not enable
an integration, launch Obsidian, change fan/charge policies, or stop existing
system services. Each integration loads one disposable QML tree when explicitly
enabled in Alis. Missing packages report unavailable rather than claiming an
operation succeeded. `make uninstall` deactivates only this package's owned
link; releases, user configuration, vaults and system services are preserved.

The supported Alis host entrypoint for system provisioning is
`./setup integrations install` (or `reinstall`, `update`, `rollback`, `remove`).
Use `./setup integrations install --dry-run` to review the stages and
`./setup integrations status` to reconcile package/helper receipts. Mutations
require explicit confirmation and native Polkit permission. Core Alis
`./setup install`, `reinstall` and `update` accept `--integration-helpers` as an
explicit opt-in; ordinary setup never provisions these helpers. Interrupted
or uncertain transactions require inspection and an explicit
`status --acknowledge-uncertain` before retry; they are never replayed.

For distribution packaging, `make install-helpers DESTDIR=/staging/root`
installs helper/polkit/schema files without enabling services or creating
TLP configuration overrides. Prefixes and `DESTDIR` are supported for packaging.
`LIBEXECDIR`, `POLKIT_ACTIONS_DIR`, `INIR_SYSTEM_SHAREDIR` and `TLP_CONFDIR`
control helper, policy, schema and profile locations; helper installation does
not create profile directories or overrides. TLP (including its optional
Radio Device Wizard), Thinkfan and Obsidian remain separately installed apps.

Run `make test` for scoped filesystem/helper and installation contracts.
Native tests prefer a sibling `Alis` host checkout, with a sibling `Hadalis`
checkout accepted for legacy fixtures. Set `ALIS_ROOT=/path/to/Alis` to pin the
native-test host explicitly (`HADALIS_ROOT` is a supported legacy override).
They require Quickshell, Qt 6 and private Niri, and use synthetic vaults and
injected status helpers.
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
here. Alis retains navigation, optional loaders, generic Battery controls
and the preserved internal Todo store. Version 0.3 adds declarative `plugins` metadata to host API 1: each installed
plugin names its capabilities by validated `settings` keys, with an optional
`waffleSettings` presentation. Obsidian exposes Theming, Quicknotes and Todo;
its combined legacy editor remains supported. Discovery reads metadata and
verifies the complete immutable payload without loading QML. Hosts without
this navigation extension retain the existing API 1 entrypoints. Integration
enable switches remain off by default.

## Compatibility and preserved data

The public package name is Alis-Intergration. API 1 retains its `hadalird`
machine identity, `HadalisSession.qml`, installed release/config locations,
saved preferences and existing note markers. New hosts expose
`alis ipc integrations refresh`; older clients/hosts can keep using
`alis ipc hadalird refresh`. Both targets use one package owner.

The fixed-hash helper/Polkit payload, including its legacy native policy
wording, remains an explicit security compatibility exception. This rebrand
does not reinstall helpers, move directories or rewrite notes. See
[compatibility contracts](docs/COMPATIBILITY.md) and the
[pre-edit identifier inventory](docs/compatibility/INT-R05-identifiers.json).
