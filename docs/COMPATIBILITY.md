# Alis-Intergration compatibility

The public product name is **Alis-Intergration** and its host is **Alis**.
`manifest.json` exposes these names through `name` and `host`. API 1 keeps its
existing machine identity and file layout. Changing display text requires no
data migration, backfill, directory move, permission change or worker restart.

| Contract | Preserved value and reason |
|---|---|
| Package/API identity | `id: hadalird`, API 1 and `HadalisSession.qml`; existing hosts validate these exact entrypoints. |
| Release ownership | `$XDG_DATA_HOME/hadalird/releases/<sourceSha>`, `current`, `.previous`, `.install.lock` and bundled `optional/hadalird`; one store and one active package. |
| Saved preferences | `integrations.hadalird.{tlp,thinkfan,obsidian}` remains authoritative. An enabled choice survives update/removal; a missing package stays unavailable and never starts workers. |
| IPC | `alis ipc integrations refresh` and `status` are the public commands. Existing `alis ipc hadalird` clients address the same singleton and retain identical behavior. Older API 1 hosts can use the legacy target. |
| QML identities | Existing singleton names, `objectName` values, settings/backend entrypoints and machine test receipt tokens remain compatible. |
| Notes and Tasks | Existing `Hadalis/Todo.md` choices, `hadalis:todo` section markers, `hadalis_import_id`, Obsidian Tasks protocol tokens and backup/lock names retain their exact bytes and meaning. Custom paths are never renamed. |
| Theme ownership | Recognized `99_Hadalis_Theme` snippets and their ownership headers remain legacy data contracts; the rebrand never rewrites or deletes a vault. A separately installed theme revision may support `99_Alis_Theme`. |
| Host selection | `ALIS_ROOT` is preferred; `HADALIS_ROOT` and a legacy sibling host checkout remain supported test overrides. |
| System helpers | `inir-*` executables, `org.inir.*` action IDs, `/usr/share/inir`, `99-inir-*` overrides, `INIR_SYSTEM_SHAREDIR` and the `alis-hadalird-*` gateway names are installed security/ownership contracts. |

The helpers, policies and schema remain byte-identical to the approved pre-patch
payload. Their fixed-hash native Polkit messages still contain legacy names;
this is an explicit compatibility exception, not a new public product name.
Authorization IDs, active/inactive permissions, paths, service ownership and
gateway allowlists do not change. Display-only rebranding never silently
reinstalls system policy or changes fan/charge state.

Install, update, reinstall, rollback and remove use the existing immutable
release inventory and atomic `current` link. Removal preserves releases,
preferences, Todo/notes, credentials, custom profiles and vault data. Failed or
interrupted activation preserves the previous owner; an explicit retry reuses
only a fully verified release. Setup receipts with uncertain system effects
still require inspection and acknowledgement before another action.

The [identifier inventory](compatibility/INT-R05-identifiers.json) records the
pre-patch source locations, hashes, provenance and replace/retain rationale.
Fixtures in `scripts/fixtures/rebrand-v1/` contain an authentic pre-patch package
and settings/Todo files persisted by the pinned pre-patch host. All records and
vault paths are synthetic; native hardware and Owner acceptance are separate.
