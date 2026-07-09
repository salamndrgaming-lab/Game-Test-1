# TWISTER CHASERS

1–4 player co-op physics comedy for Steam (Windows + Linux). Broke amateur
storm chasers drive a barely-functional van into tornado weather to film
footage. Better footage → more views → money for van and camera upgrades.
Getting too close gets you (or the van, or your friend) sucked into the
funnel.

**Status: Phase 0** — project skeleton, main menu, Steam lobby plumbing, and
a networked capsule test scene. See `DEVLOG.md` for what to test right now.

## Requirements

- **Godot 4.4.x** (Forward+). Open `project.godot`.
- For Steam play: GodotSteam GDExtension + SteamMultiplayerPeer — install
  steps in `addons/godotsteam/INSTALL.md`. Not needed for local testing.

## Quick start

Open in Godot → **Debug → Customize Run Instances…** → 2 instances → F5 →
one window **HOST LOCAL**, the other **JOIN LOCAL**. Full steps in
`DEVLOG.md`.

## Repo layout

- `scenes/` — ui, net_test, (main / garage / storm_run arrive in later phases)
- `scripts/` — autoloads (`SteamManager`, `Game`), scene scripts, `BalanceConfig`
- `config/balance.tres` — **all** tunable gameplay values, editable in the inspector
- `assets/` — models / audio / materials (placeholders; CC0 credits in `assets/audio/CREDITS.md`)
- `addons/` — GodotSteam goes here (see INSTALL.md)
- `DEVLOG.md` — per-phase build notes, known jank, and test instructions
