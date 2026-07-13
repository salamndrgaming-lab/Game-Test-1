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

---

## Phase 3 — The tornado & the core loop (2026-07-13)

### What was built

- **Tornado** (`scenes/tornado/tornado.tscn`) — stacked translucent funnel
  segments (placeholder for billboarded layers), rotating debris column and
  ground dust skirt (GPU particles), looping wind whose volume ramps with
  proximity and intensity. Host-simulated noise-driven wander that steers
  back inside the map; intensity climbs F1 → F4 across the run and the sky
  darkens with it. Position/intensity synced; clients only run visuals.
- **Three-ring suction** (host): outer 200 m — loose props (cones, crates,
  planks, van doors) slide toward the funnel; middle 80 m — players shoved,
  light props go airborne, van pushed; inner 25 m — standing players
  ragdoll, ragdolls orbit up the funnel (lift fades near the top, so bodies
  get flung out ballistically), and at F3+ the van itself lifts and tumbles.
- **Real filming scoring** (host, replaces the HUD stub): points/sec =
  base × tornado-in-frame × proximity × intensity, plus subject bonuses
  (friend being flung, VAN AIRBORNE), times a steadiness multiplier.
  Best-single-second and its caption tracked for the results screen.
- **HP / death / drama**: ragdoll impact decelerations deal fall damage
  (heavy, not instant death). At 0 HP you're dead: your unsaved footage
  drops as a glowing camera pickup any teammate can E-grab; you respawn by
  the van after 10 s. HP + dead state on the HUD.
- **Run structure**: NetTest lobby → host presses ENTER → storm run
  (10 min chase, timer + F-rating on screen) → storm dissipates →
  "GET TO EXTRACTION" (green beacon, 90 s) → footage banks inside the
  zone → RESULTS screen: per-player footage, best-clip caption, views,
  money, crew total → back to lobby. Scene transitions are host-broadcast
  RPCs on the Game autoload.
- **Map**: 1 km² placeholder — farmhouse, barn with loose plank debris
  (scatters in the outer ring), gas station with props, water tower,
  trailer park, corn field patch, extraction beacon at the garage corner,
  van parked at spawn. Real layout, placeholder boxes.

### How to test (gate)

Two instances as usual. **Gate 1 (solo is fine):** HOST LOCAL alone →
ENTER → drive toward the funnel → film it (C) → survive → extraction →
results screen shows money. **Gate 2 (the clip):** two players; one stands
in the middle ring filming while the other walks into the inner ring —
the filmer's footage counter should visibly spike when the victim starts
orbiting ("P2 getting yeeted"). Then both drive back and bank it.

Practical testing notes:
- 10 minutes is long for a test loop — drop `run_chase_seconds` to ~120 in
  `config/balance.tres` while testing.
- Tornado starts at the far corner (~900 m away); drive toward the dark sky.

### Known jank / honesty section

- **Still nothing executed** — same environment limits. This phase has the
  most hand-tuned numbers yet (suction forces, lift, damage scale); expect
  the first run to need balance.tres passes. The structure is sound; the
  values are educated guesses.
- Scene transitions mid-session will briefly log synchronizer errors as
  in-flight packets hit freed nodes — cosmetic, known Godot behavior.
- Van↔tornado interaction with seated players untested territory: being
  in a lifted van should hold you in your seat (seats teleport you), which
  is either great or nauseating on camera. Report back.
- Corn field is a flat green rectangle. Lightning strikes and barn
  "pre-broken pieces" beyond the plank pile were skipped — noted for the
  Phase 6 polish list or a Phase 3.5 if you want them sooner.
- Dead players spectate their own corpse (camera follows the ragdoll).
  Acceptable for now; a proper spectate cam can come with Phase 5 polish.

---

## Static review pass #2 (2026-07-13, post-Phase 3)

Re-read of the Phase 3 code and its interactions with earlier phases.
Fixed:

1. **Floating footage pickups** — dying mid-orbit dropped the camera at
   your death position, i.e. potentially 40 m up inside the funnel,
   unreachable forever. Pickups now drop at ground level under the death
   point (map is flat; a rooftop death drops it beside the building).
2. **No ESC in storm runs** — the run scene had no input handler: mouse
   stayed captured and there was no way to leave a run. Same ESC
   convention as the lobby now (free mouse → leave session).
3. **Mid-run joins weren't blocked** — the design doc forbids late joins
   (they break the spawn handshake and Godot's high-level multiplayer).
   The host now locks the session on leaving the lobby:
   `refuse_new_connections` on the peer + `setLobbyJoinable(false)` on the
   Steam lobby, unlocked on returning to the lobby.
4. **hp ignored balance.tres** — spawned players had a hardcoded 100
   regardless of `player_max_hp`; now initialized from balance.
5. **Best-clip bucket bleed** — the scoring second-bucket didn't reset when
   you stopped filming, so a stale partial second padded the next clip's
   first second. Reset on any non-scoring frame.
6. Cosmetic: storm_run.tscn load_steps count corrected.

Checked and fine (for the record): RPC ordering of results-then-scene-change
(same reliable channel), seat cleanup for disconnecting players, dead
players excluded from suction re-ragdoll and extraction checks,
tornado-immune seated players (the van takes the forces, as designed),
duck-typed cross-script access compiles as dynamic lookup with warnings
(not errors) under GDScript's UNSAFE_* rules.

---

## Phase 5 — Progression, garage, session glue (2026-07-13)

(Phase 4 — proximity voice — deliberately deferred: it needs the GodotSteam
extension live on a real machine to build against. It'll come after the
first playtest round.)

### What was built

- **The garage** (`scenes/garage/garage.tscn`) is the new lobby/hub — the
  only place players can join. Walkable room with the van (drivable,
  honkable, paintable), a cone to kick, and five E-interact stations:
  - **CONTRACTS BOARD** — cycles F1 "Dust Devil Daycare" → F4 "The Finger
    of God". The contract caps the storm's F-rating and multiplies the
    payout (×1.0 / ×1.6 / ×2.6 / ×4.0, in balance.tres).
  - **UPGRADES BENCH** — opens the shop overlay. Crew wallet,
    host-validated purchases: Bigger Engine (+35% torque), Roll Cage (half
    crash damage), Storm Tires (half tornado shove), **Winch** (E-grab the
    van or a downed friend to tow them — same floppy spring, 3× stronger),
    Wide Lens (+20° film cone), Stabilizer (no moving penalty), Big
    Battery (2× camcorder battery).
  - **PAINT BOOTH** — cycles van paint (5 colors, synced, persisted).
  - **HAT RACK** — cycles your hat (cone / bucket / crown). Hats
    physics-detach in the tornado's middle ring and become grabbable,
    chaseable props you can put back on. As designed.
  - **GARAGE DOOR** — host rolls the crew out to the storm run.
- **Persistence** — host's `user://twister_save.json` holds crew money,
  upgrades, and paint; loaded at boot, saved on every purchase and payout.
  Clients get progression synced on join (crew-wide wallet, no per-player
  economics, per the design doc).
- **Results screen polish** — auto-generated run title ("The Time The Van
  Learned To Fly" / "The Time Everybody Kept Dying" / ...), per-player
  stats: Best Cameraman, Most Airborne (ragdoll airtime + riding a flying
  van), Least Useful — plus the **CLIP THAT** button, which does exactly
  what the design doc says it does (nothing, loudly).
- **Pause menu** (ESC anywhere in a session; autoload overlay): Resume,
  Invite Friends (Steam overlay), Settings (master volume + mouse
  sensitivity sliders, saved to `user://settings.json`; push-to-talk
  toggle stubbed for Phase 4), Leave Session, Quit. The game does not
  pause — it's multiplayer, the storm doesn't care.
- **Refactor**: the three player-spawning scenes now share one
  `PlayerSpawnManager` base class (the ready-handshake logic lives once).
  NetTest is demoted to a dev sandbox; menu/session flow goes straight to
  the garage.

### How to test (gate)

The Phase 5 gate is the full session loop, two instances (4 ideally):

1. Host + join → both walk around the **garage**.
2. Cycle a **contract** (board label updates in both windows), everyone
   grabs a **hat**, host cycles **paint** (van repaints live everywhere).
3. **ENTER the storm run** via the garage door → hats get eaten by the
   middle ring (chase them!) → film → extract → **results** (check the run
   title and awards) → BACK TO THE GARAGE.
4. **Buy an upgrade** with the money you just made (both windows' shop
   should show OWNED) → run again → torque/lens/battery difference.
5. Quit the host entirely, restart: money/upgrades/paint should load from
   the save file.
6. ESC everywhere: pause menu opens over gameplay, sliders persist across
   restarts, Leave Session returns everyone to the menu cleanly.

### Known jank / honesty section

- **Still nothing executed** — the full stack (Phases 0/1/2/3/5) awaits its
  first playtest. Two static review passes are in, but expect editor
  warnings (duck-typed UNSAFE_* lookups are intentional) and possibly a
  stray tscn property typo.
- Winch-towing quality depends entirely on VehicleBody vs spring behavior —
  pure guesswork until driven. Same for whether the garage room is big
  enough to drive the van without instantly ramming a wall (it is not, and
  that is a feature).
- Hats: skins beyond three placeholder shapes, and per-player hat
  persistence, are punted to the art pass.
- Both local test instances share `user://` (same machine), so they share
  a save file — harmless because clients get host-synced values anyway.
- The pause menu doesn't block player movement while open (mouse-look
  stops, WASD doesn't). Design-adjacent; revisit if it annoys.
