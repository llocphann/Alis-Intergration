# Alis-Intergration

Optional workspace, study, fitness, and hardware integration plugins for the [**Alis**](https://github.com/llocphann/Alis) Wayland desktop shell (`hostApi: 1`). Every plugin is optional and disabled by default until you install and enable it.

## Included Plugins

### Nexus Knowledge Workspace (`nexus`)

Browse and edit your Markdown vault inside Alis with an Obsidian-style Soft Folder Tree, Tag Wrangler+ sidebar, 2D/3D Vault & Local Graph with virtual `#tag` hubs, Homepage overview, Daily Schedule, Obsidian Calendar with dual word-count & task indicators, interactive 3D Globe with smooth zoomed-in street/building Map mode & Alis auto-theming, Canvas board with inline Note Picker, Markdown editing shortcuts (`Ctrl+B`, `Ctrl+I`, `Ctrl+K`, smart list Enter) with external-edit conflict protection, persistent `alis-nexus --serve` vault & native revision-history backend, redesigned Bases decks, Quicknotes, Todo sync, native Wayland clipboard image paste, and adaptive Alis Vault theming.

<p align="center">
  <img src="docs/screenshots/nexus-workspace.png" alt="Nexus Workspace showing file tree, Vault Mini-Graph, Homepage overview, 3D Globe, and Today timeline" width="100%" />
</p>

### Alis Files (`alis_files`)

Native Rust + GTK4 file manager (`alis-files`) with an integrated Abyss Overlay workspace, bounded async thumbnail worker pool with directory-change cancellation, split dual-pane browsing, QuickLook previews, inspector metadata, archive tools, and live Alis palette synchronization.

### Spaced Repetition (`spaced_repetition`)

Review vocabulary directly on the Alis Dashboard with CEFR badges, morphology hints, word pronunciation audio (`en-US-AvaMultilingualNeural`), Multiple Choice prompts, mastery bars, an Analytics donut, and a 7-day review forecast.

<p align="center">
  <img src="docs/screenshots/spaced-repetition.png" alt="Dashboard Spaced Repetition card with CEFR mastery, morphology hints, and 7-day forecast" width="100%" />
</p>

### Exercises Tracker (`exercises_tracker`)

Track strength workouts and body metrics in clean borderless Dashboard cards synced with `Body Tracker` weight check-ins and configurable under **Alis Settings → Integrations**.

<p align="center">
  <img src="docs/screenshots/exercises-tracker.png" alt="Dashboard Exercises Tracker with Push Strength session and Body Tracker weight check-in" width="100%" />
</p>

### Hardware & Power (`tlp` · `thinkfan`)

- **TLP Power Management (`tlp`)** — Optional battery charge threshold and power profile controls for supported laptops.
- **Thinkfan Cooling (`thinkfan`)** — Optional managed fan-curve control and concise single-row status/toggle inside the System Monitor popup.

## Installation

Install all plugins into your user data directory from a clean git checkout without enabling any integration automatically:

```sh
python3 scripts/install.py install
```

Or manage individual plugins:

```sh
python3 scripts/install.py install-plugin nexus
python3 scripts/install.py remove-plugin nexus
python3 scripts/install.py uninstall
```

## Documentation & Links

- [Compatibility & Host Contract](docs/COMPATIBILITY.md) — host API boundary, saved preference guarantees, and safety defaults
- [Alis-Intergration GitHub Issues](https://github.com/llocphann/Alis-Intergration/issues) — active integration issues and milestones
- [Alis Core Shell](https://github.com/llocphann/Alis) — Wayland host shell (`dev` / `stable`)

---

- **License:** GPL-3.0-or-later; optional plugin isolation preserved.
