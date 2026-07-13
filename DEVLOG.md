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

---

## Phase 2 — The van (2026-07-12)

### What was built

- **`scenes/van/van.tscn`** — VehicleBody3D chassis under a `VanRig` wrapper
  (doors are physics *siblings*, not children — RigidBody-inside-RigidBody
  fights the solver). Four VehicleWheel3D wheels (front steer, rear drive),
  deliberately top-heavy via raised custom center of mass
  (`van_com_height` in balance.tres): fine at low speed, rolls if you get
  cocky. Host simulates; client vans freeze and receive synced transforms.
- **Seats** — driver, passenger, 2 rear, plus a **roof slot** (the roof rack
  is also just physically standable). E enters the nearest free seat within
  4 m / exits; exiting above ~6 m/s ragdolls you with the van's velocity.
  Flopping (X) or fainting while seated ejects you mid-drive. Seated players
  are placed at seat markers each tick and follow the van.
- **Driving** — driver's normal WASD stream doubles as throttle/steer,
  SHIFT is the brake. No extra input plumbing needed.
- **Doors** — two front doors on limited hinge joints with door-vs-chassis
  collision left ON so they can only swing outward; no latch, so hard
  acceleration and cornering flings them around. They're also grabbable.
  The side doorway is permanently open (broke-van fiction, and rear seats
  film out of it).
- **Van HP** — damage from sudden decelerations (crashes). Placeholder
  crumple: panels darken + body sags progressively; smoke particles and
  engine sputter (random pitch dropouts) below 25%; engine dies at 0 and
  the run continues on foot.
- **Interactables** — H horn (any seat, non-positional = always audible
  everywhere, as designed), R radio (front seats, cheesy synth loop for now;
  storm chatter is Phase 4), G glovebox (passenger only, one spare camcorder
  battery per run).
- Balance additions: torque, steer, brake, damage scale, exit-ragdoll speed.

### How to test (gate)

Two instances again (Debug → Customize Run Instances → 2). The Phase 2 gate
is the trailer shot: **pile in, drive the field, roll the van, everyone
ragdolls out.**

1. Both players E into the van (first gets driver). Drive: W/S throttle,
   A/D steer, SHIFT brake. If steering feels inverted, tell me — the sign
   is a coin flip until someone actually drives it.
2. Corner hard at top speed — the van should threaten to roll, and commit
   if you yank it. Passengers X-flop out mid-corner.
3. Ram a crate stack / the ground hard: HP drops, panels darken; keep
   crashing until smoke + sputter (<25%), then dead engine at 0.
4. H spam the horn from the back seat while the driver corners. R radio on.
   G glovebox battery as passenger after draining yours filming.
5. One player rides the roof (5th E slot or just climb/jump on) while the
   other drives. Film it from a rear seat with C.

### Known jank / honesty section

- **Still nothing executed** (no Godot binary here). On top of the usual,
  the highest-risk hand-authored bits this phase:
  - **Hinge axes**: door hinges use a hand-written rotated joint transform;
    if doors swing on the wrong axis (up/down instead of outward), that
    transform is the bug — tell me what you see and I'll flip it.
  - **Steering/throttle sign** — pure convention guess, one-line fix.
  - VehicleBody3D tuning is untested; per the design doc's risk note, if it
    fights us for more than a day we switch to a raycast car.
- Seated characters clip through the van box a bit and the camera treats
  the van as see-through (SpringArm ignores the vehicle layer, rides above
  the roof while seated). Placeholder-grade, revisit with art.
- Wheels don't visually spin/steer on clients (van transform syncs, wheel
  animation is host-side simulation state). Cosmetic; Phase 6 polish.
- Van sync is raw transform-at-net-rate, no interpolation buffer yet —
  fine on loopback, will stutter over real Steam P2P; noted for Phase 4/6.
- Riding the roof unseated (standing on the moving chassis) is physically
  possible but janky — the roof *seat slot* is the reliable option.

---

## Static code review pass (2026-07-13)

Full re-read of every script and scene before Phase 3, since nothing has
been executed yet. Found and fixed:

### Critical (would have failed the gate tests)

1. **Multiplayer spawn race** — `MultiplayerSpawner` pushes existing players
   to a peer the moment it *connects*, but clients connect while still in
   the menu (the NetTest scene loads after). The host-player spawn packet
   would arrive before the client's scene existed and be dropped — the
   client would never see the host. Replaced the spawner with explicit
   RPC spawning + a ready-handshake (client announces from `_ready()`,
   server sends the roster and broadcasts the newcomer).
2. **Ragdoll runaway feedback** — the player root followed the torso each
   tick, but the ragdoll parts are children of that root, and moving the
   parent of an active RigidBody3D teleports it by the same delta → the
   doll would rocket to infinity in ~1 second. Root now saves/restores the
   parts' global transforms around the move (`hold_root_to_torso`).

### High

3. **Collision masks missing the vehicle layer** — player capsule, ragdoll
   parts, cones and crates had mask 7 (world|players|props) but the van
   chassis is layer 8: players would walk/fall straight through the van and
   couldn't stand on the roof; the van would drive through props. All now 15.
4. **HUD controls off-screen** — `Control.position` is relative to the
   parent's origin regardless of anchors, so placing the footage label at
   `(-220, 22)` after a TOP_RIGHT preset put it off the left screen edge
   (same for the battery bar, bottom-left). Rewritten with explicit
   anchor+offset pairs.

### Medium / low

5. CharacterBody3D applies no forces on contact, so walking into a cone did
   nothing — added a manual kick impulse on slide collisions
   (`player_kick_impulse` in balance.tres). Same physics gap meant a
   speeding van just stopped against a pedestrian — the van now ragdolls
   any standing player within 2.8 m at speed (roof riders exempt).
6. Flop (X) discarded running momentum — now keeps velocity plus a hop.
7. Emote wheel was anchored as a zero-size box (CENTER preset applied
   before children existed) — now wrapped in a CenterContainer.
8. `_seat_marker` used ternary return with implicit Node→Node3D casts —
   made explicit.

### Still unverifiable from here (unchanged, flagged since earlier phases)

- GodotSteam `steamInitEx` signature and `SteamMultiplayerPeer`
  `create_host/create_client` API vary by extension version.
- Door hinge axis orientation and van steering/throttle sign are
  convention guesses — one-line flips if wrong.
- VehicleBody3D feel, pin-joint floppiness, and all "is it funny" checks
  need a real playtest.
