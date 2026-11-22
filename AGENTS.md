# Alis-Intergration agent workflow — repository-owned GitHub Issues

These rules apply to Local and Cloud AI editing Alis-Intergration. The canonical tracker is **[Alis-Intergration GitHub Issues](https://github.com/llocphann/Alis-Intergration/issues)** (not Alis Issues). Prior Alis `AI-*`, `HELPER-*` and `INT-*` Issues marked MOVED are closed historical pointers.

1. Work on **Alis-Intergration `main`**. Refetch HEAD and affected files before each edit; do not modify Alis `stable`. Host-side Alis shell files are maintained on `Alis/dev` and must be coordinated separately.
2. Create/update Integration-owned tasks **in this repo's Issues**. Search open and closed Issues by code/behavior and follow any historical MOVED pointer before creating a new one; never write active tasks or statuses into Markdown.
3. Keep stable codes `AI-I##`, `INT-R##`, `HELPER-I##` and related original codes. Use `bug` / `enhancement` / `documentation`, primary `area:integration`, and risk/status labels only as grounded.
4. Describe concise **Goal / Constraints / Done when**. Record meaningful milestones with exact Integration and Alis host SHAs, scoped `make test` results, truthful PASS/FAIL/SKIP and outstanding native/Owner acceptance.
5. Bot-reported complete remains open awaiting Owner verification; only explicit Owner approval closes as completed. Cross-repository host work should link a distinct Alis Issue rather than maintaining duplicate active Issues.
6. Preserve optional/default-disabled integration boundaries, TLP/Thinkfan fail-safe behavior, user-owned configs, notes/vault bytes, Polkit permissions and safe install/uninstall. No silent privileged actions, model loading, vault writes or fan/charging changes. Native Niri/Quickshell/hardware and Owner tests are separate from fixtures.

7. **Strict functional preservation for optimizations and improvements:** Inventory existing optional-plugin functions, host/API boundaries, native lifecycles, permissions, fail-safe modes, visual/settings flows and all supported configurations. Baseline before/after at pinned Integration + Alis SHAs; rerun affected behavior and cross-plugin tests. Preserve every working or Owner-accepted capability, including absent-plugin behavior. Do not silently remove a feature, lower quality or weaken an oracle; obtain prior explicit Owner approval for an intentional trade-off.
8. **Bugfix must cover pre-existing stored data:** Trace all consumers of plugin settings, cached indexes, Todo/notes/vault and legacy records. A patch must apply to existing installations/data, not solely newly created records. If older records need repair, implement versioned, idempotent and restart-safe migration/backfill or read-time compatibility while preserving IDs, timestamps, user edits and unrelated bytes. Respect vault/user-data consent and Polkit boundaries; never silently overwrite, duplicate, reset or delete old records. Test sanitized pre-patch fixtures, new/old mixed data, repeated update, failure/retry, restart and rollback without modifying real vault/user files.
9. **Verification/Owner gate:** Record affected-feature inventory, exact source/host SHA, explicit migrated-old-data readbacks, and scoped/full PASS/FAIL/SKIP/UNRUN results. Known compatibility/data regressions block DONE/Owner-ready; a subset PASS is not whole-product acceptance. Native hardware/Quickshell and separate Owner approval remain mandatory when impacted.
10. **Zero-Stutter Nexus Lifecycle, Graph Optimization, Concise UI & Silent Verification:** Keep heavy `Loader`s in `NexusWorkspace`, `NexusCustomViews`, and `NexusGlobeWidget` asynchronous (`asynchronous: status !== Loader.Ready`), defer Canvas/Graph paints until `transitionSettled === true`, schedule vault/calendar CLI refreshes after the opening slide completes (`openRefreshTimer`), deduplicate identical background scan payloads via `_lastAppliedScanDigest`, use reusable `Float32Array` Canvas buffers + memoized folder colors + batched Pass-0 leaf fills in `NexusGraphCanvas`, and stagger Vault Graph initial reveal (`revealStaggerMs`). Keep UI copy concise and center button icon+label pairs cleanly (`anchors.centerIn: parent`). Run all tests in 100% Silent / Zero-Focus mode (`Alis/.agents/skills/alis-silent-verify/SKILL.md`).
11. **Exercises Tracker Borderless Tonal Cards, Active Pill WCAG Contrast, Journal Sync, Thinkfan Recovery & User-Facing `README.md`:** Keep `DashboardExercisesTracker` visually consistent with `DashboardSpacedRepetition` using clean borderless interior cards matching Home Dashboard `DashCard` (`AbyssStyle.contentLayer` / `Appearance.colors.colLayer1Base` over `colLayer0Base`) with nested layers stepped gently by **~2.0%–2.2% HSL per tier** via `ColorUtils.tonalStep` (lightening while headroom exists and subtly deepening when `hslLightness > 0.86`; zero per-box `Gradient` and zero `#ffffff`/neutral-gray washing), explicit `colBackgroundToggled` + WCAG `>= 5.0` contrast across all toggled `PillButton`/`dayChip`/`routineChip`/`catBtn` pills, universal centered button alignment, dedicated **Integrations** settings (`DashboardExercisesTrackerSettings.qml`), and two-way weight check-in compatibility with `Body Tracker` / Nexus Journal entries. Keep managed `Thinkfan` service health checks and fail-safe recovery reliable alongside concise single-row System Monitor status. Keep `README.md` strictly user-facing with real visual screenshots in `docs/screenshots/` (outside runtime `PAYLOAD`), free of internal regression ledgers or retired doc references.
12. **Periodic Docs/Notes Hygiene, Human-Only Author Attribution & Mature Auto-Push:** Refresh `README.md`, `docs/`, `AGENTS.md`, and shared work notes whenever features/tools change and periodically every `~5–8` commits / before every push so zero stale docs, dead links, or retired features remain while preserving `docs/COMPATIBILITY.md` API 1 legacy contracts. Require both `Author` and `Committer` on every commit to match the maintainer's human `git config user.name` / `git config user.email` with zero bot accounts or `Co-Authored-By:` AI/bot trailers, audited on `git log @{u}..HEAD` (repairing only unpushed local commits if needed; never force-push published history without Owner approval). Proactively evaluate commit maturity on `origin/main` (`>= 1` large verified wave, `>= 3–5` cohesive milestone commits, or `>= 5–10` routine commits) and auto-push once the tree is clean, non-diverged (`behind == 0`), scoped silent tests + docs hygiene pass, and attribution checks pass (see `Alis/.agents/skills/alis-repo-hygiene-and-push/SKILL.md`).

## Behavioral guidelines to reduce common LLM coding mistakes

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

Tradeoff: These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

These guidelines are working if: fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

[Integration Issues](https://github.com/llocphann/Alis-Intergration/issues) · [Alis host Issues](https://github.com/llocphann/Alis/issues) · [Companion Issues](https://github.com/llocphann/Alis-Companion/issues).
