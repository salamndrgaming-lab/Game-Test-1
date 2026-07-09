# TWISTER CHASERS — DEVLOG

Appended at the end of every phase: what was built, known jank, what to test.

---

## Phase 0 — Project skeleton & GodotSteam (2026-07-09)

### What was built

- **Godot 4.4 project** (Forward+, GDScript only). Layout: `scenes/` (ui,
  net_test, plus empty main/garage/storm_run), `scripts/`, `config/`,
  `assets/`, `addons/`.
- **`config/balance.tres`** (`BalanceConfig` custom Resource) — every tunable
  gameplay number lives here, including placeholders for future phases
  (tornado ring radii 200/80/25 m, van torque, payouts). Tweak in the
  inspector, no code edits.
- **Autoload `SteamManager`** — Steam init (Spacewar appid 480 via
  `steam_appid.txt`), friends-only lobby create/join, overlay invite
  handling, and multiplayer peer setup. All Steam calls go through
  `Engine.get_singleton("Steam")`, so the project loads and runs fine with no
  GodotSteam installed (Steam buttons then report a friendly error).
- **Autoload `Game`** — state machine MENU → LOBBY → GARAGE → STORM_RUN →
  RESULTS. Phase 0 wires MENU and LOBBY (NetTest stands in for the lobby).
- **Main menu** — HOST GAME (Steam), JOIN by lobby ID, HOST LOCAL /
  JOIN LOCAL (dev-only ENet loopback for same-machine testing), SETTINGS
  (stub), QUIT. Ugly, functional.
- **NetTest scene** — flat plane, one colored capsule per player with a name
  tag, host-authoritative movement (clients stream input to the server at
  60 Hz unreliable; server simulates; `MultiplayerSynchronizer` syncs
  transforms back). `MultiplayerSpawner` handles join/leave spawning.
- Input map established for later phases: WASD, Space jump, E interact,
  C film, X flop, Q emote wheel.

### How to run the two-instance gate test

**Local test (do this first — no Steam required):**

1. Open the project in Godot **4.4.x** and let it import.
2. Editor menu **Debug → Customize Run Instances…** → check
   **Enable Multiple Instances**, set count to **2**, OK.
   (This is Godot 4.4's built-in "multirun".)
3. Press **F5**. Two game windows open.
4. Window A: click **HOST LOCAL**. Window B: click **JOIN LOCAL**
   (leave `127.0.0.1`).
5. **Working looks like:** both windows show 2 capsules with name tags
   (P1 = host). WASD/Space in one window moves that capsule in *both*
   windows (the client's own capsule reacts with a few ms delay — expected,
   no prediction yet). ESC in the client window despawns its capsule on the
   host; ESC on the host kicks the client back to the menu.

**Steam test (after installing GodotSteam — see `addons/godotsteam/INSTALL.md`):**

- One Steam account cannot P2P-connect to itself, so this needs **two
  machines with two different Steam accounts** (or one machine + a second
  account in a sandboxed Steam). Both must have Steam running and logged in;
  appid 480 (Spacewar) requires no ownership.
- Host: **HOST GAME** → in the test scene press **F1** to copy the lobby ID →
  send it to the second player, who pastes it into the JOIN field. Or press
  **F2** for the Steam overlay invite dialog; accepting the invite joins
  automatically.

### Known jank / honesty section

- **Nothing here has been executed.** This environment has no Godot binary
  and network access was restricted (couldn't download the engine or
  GodotSteam), so every `.tscn`/`.gd` file is hand-authored and unverified.
  Expect the editor to possibly flag a small typo or property name on first
  open — please paste any red errors back to me verbatim.
- GodotSteam binaries are **not** in the repo (couldn't be downloaded from
  here). Follow `addons/godotsteam/INSTALL.md`; until then only Local Test
  works, by design.
- `SteamManager` targets the current GodotSteam 4.x API (`steamInitEx`) and
  a `SteamMultiplayerPeer` with `create_host(port)` /
  `create_client(steam_id, port)`. Extension versions vary; if the Steam
  path errors, this integration point is the prime suspect — INSTALL.md
  pins recommended versions.
- Local ENet mode is a **dev tool only**; ship networking stays Steam P2P
  per the design pillars.
- NetTest camera is a fixed chase cam, no mouse look — the real third-person
  camera is Phase 1.
- Clients have no prediction for their own capsule (server round-trip on
  input). Fine on LAN/loopback; revisit when Phase 1 movement lands.

### What to test (gate)

Run the local two-instance test above and confirm capsule sync. If that
passes, optionally run the Steam test with a friend. **Do not proceed to
Phase 1 until you confirm.**
