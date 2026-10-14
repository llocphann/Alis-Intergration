# Alis-Intergration agent workflow — repository-owned GitHub Issues

These rules apply to Local and Cloud AI editing Integration (Hadalird). The canonical tracker is **[Alis-Intergration GitHub Issues](https://github.com/llocphann/Alis-Intergration/issues)** (not Alis Issues). Prior Alis `AI-*`, `HELPER-*` and `INT-*` Issues marked MOVED are closed historical pointers.

1. Work on **Alis-Intergration `main`**. Refetch HEAD and affected files before each edit; do not modify Alis `stable`. Host-side Alis shell files are maintained on `Alis/dev` and must be coordinated separately.
2. Create/update Integration-owned tasks **in this repo's Issues**. Search open and closed Issues by code/behavior and follow any historical MOVED pointer before creating a new one; never write active tasks or statuses into Markdown.
3. Keep stable codes `AI-I##`, `INT-R##`, `HELPER-I##` and related original codes. Use `bug` / `enhancement` / `documentation`, primary `area:integration`, and risk/status labels only as grounded.
4. Describe concise **Goal / Constraints / Done when**. Record meaningful milestones with exact Integration and Alis host SHAs, scoped `make test` results, truthful PASS/FAIL/SKIP and outstanding native/Owner acceptance.
5. Bot-reported complete remains open awaiting Owner verification; only explicit Owner approval closes as completed. Cross-repository host work should link a distinct Alis Issue rather than maintaining duplicate active Issues.
6. Preserve optional/default-disabled integration boundaries, TLP/Thinkfan fail-safe behavior, user-owned configs, notes/vault bytes, Polkit permissions and safe install/uninstall. No silent privileged actions, model loading, vault writes or fan/charging changes. Native Niri/Quickshell/hardware and Owner tests are separate from fixtures.

[Integration Issues](https://github.com/llocphann/Alis-Intergration/issues) · [Alis host Issues](https://github.com/llocphann/Alis/issues) · [Companion Issues](https://github.com/llocphann/Alis-Companion/issues).
