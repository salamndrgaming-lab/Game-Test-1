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

---

## Phase 1 — Player character & physics feel (2026-07-10)

### What was built

- **Real player scene** (`scenes/player/player.tscn`) replacing the Phase 0
  capsule. Chunky low-poly body built from primitives — and the visible body
  *is* the ragdoll: six pin-jointed rigid bodies (torso, head, arms, legs)
  that stay frozen and pose-locked to the CharacterBody3D in normal play.
- **Ragdoll switch**: X ("flop") key, big sudden decelerations (sprinting
  into a wall, hard landings), the faint emote, or being clipped by a
  fast-flying ragdolled friend all unfreeze the doll. Host-simulated;
  recovery after ~2s of low torso velocity (`balance.tres`). Bone/part
  transforms sync to clients at 20 Hz — jitter accepted as comedy per the
  known-risks note.
- **Grab/carry**: E grabs the nearest `grabbable` prop within reach —
  deliberately floppy spring force (HL2-style), tunable spring/damping/break
  distance. Two players grabbing one prop apply independent springs and
  fight over it naturally. Traffic cones + crates placed in NetTest.
- **Camcorder stub**: hold C — viewfinder overlay with blinking REC dot,
  battery drain, and a stubbed Footage Score meter (flat tick; real frustum
  scoring is Phase 3). Slight FOV zoom while filming. Remote players see a
  red `[REC ●]` tag over the filmer's head.
- **Emote wheel**: hold Q (or press 1–4 while open) — POINT, THUMBS UP,
  PANIC SCREAM (loud, stupid, positional 3D audio), FAINT (instant ragdoll).
  Host-validated, broadcast to everyone as floating text over the head.
- **Third-person mouse-look camera** (SpringArm), pitch local, yaw streamed
  to host with movement input. Sprint on SHIFT. Player shoving on contact.
- Placeholder audio (scream/bonk/click) **synthesized in-repo** because the
  network policy blocked CC0 downloads — see `assets/audio/CREDITS.md`.

### How to test (gate)

Same two-instance setup as Phase 0 (Debug → Customize Run Instances → 2 →
F5, HOST LOCAL / JOIN LOCAL), then:

1. **Movement feel**: WASD + mouse look + SHIFT sprint + SPACE jump. The
   body should visibly face the direction of travel while the camera stays
   under your control.
2. **Flop**: press X — full ragdoll flop, get up ~2s after settling. Spam it.
3. **Impact ragdoll**: sprint-jump into the other player or land from a
   ledge — both should go down at speed.
4. **The gate**: both players grab the SAME traffic cone with E and fight
   over it. Shove each other (walk into them), flop onto them (a flying
   body knocks a standing player down).
5. **Camcorder**: hold C — REC overlay, battery drains, footage number goes
   up; the other window sees `[REC ●]` over your head.
6. **Emotes**: hold Q → PANIC SCREAM. The other player should hear it from
   your character's position in 3D.

**Working looks like:** that cone fight is genuinely funny. If it isn't, we
tune `grab_spring`/`grab_damping` and ragdoll thresholds in `balance.tres`
before Phase 2.

### Known jank / honesty section

- **Still nothing executed** — same environment limits as Phase 0 (no Godot
  binary, restricted network). Hand-authored scenes; report red errors
  verbatim, especially around `player.tscn` (it's the most complex file yet).
- Phase 0 gate has NOT been confirmed either — test both phases in one
  session; if Phase 0 sync is broken, fix that first.
- Pin joints have no limits — arms spin freely. Reads as comedy; revisit
  only if it reads as broken.
- Client's own character has no prediction (input round-trips to host).
  Fine on loopback; watch for sponginess over real Steam P2P.
- Battery/footage are client-side stubs; host validates nothing about
  filming yet (Phase 3 moves scoring host-side).
- No character model swap hooks yet — primitives are placeholders; part
  meshes live under `Ragdoll/*/Mesh` so .glb swaps later won't touch code.
