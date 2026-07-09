# Installing GodotSteam (required for Steam lobbies & P2P)

The GodotSteam binaries could not be bundled in this repo (they were not
downloadable from the build environment). The project **runs without them**
— Steam buttons show a friendly error and Local Test mode works — but for
actual Steam play, install both pieces below.

## 1. GodotSteam GDExtension (the `Steam` singleton)

1. Go to <https://godotsteam.com/> → Downloads, or
   <https://github.com/GodotSteam/GodotSteam/releases>.
2. Download the **GDExtension** zip matching **Godot 4.4** (GodotSteam 4.15
   or newer).
3. Extract so that this folder (`addons/godotsteam/`) contains the
   `godotsteam.gdextension` file and the `win64` / `linux64` binaries.
4. Restart the editor. The output console should show Steam initializing
   (with Steam running and logged in).

## 2. SteamMultiplayerPeer (Godot high-level multiplayer over Steam P2P)

`SteamManager` expects a `SteamMultiplayerPeer` class with
`create_host(virtual_port)` and `create_client(steam_id, virtual_port)` —
that's the API of:

- **expressobits/steam-multiplayer-peer**:
  <https://github.com/expressobits/steam-multiplayer-peer/releases> —
  extract its addon folder into `addons/`.

GodotSteam's own MultiplayerPeer flavor has a different API; if you use that
instead, `scripts/autoload/steam_manager.gd` → `_create_steam_peer()` is the
one function to adapt.

## 3. App ID

`steam_appid.txt` in the project root contains `480` (Spacewar, Valve's
public test appid — free to use, no ownership needed). Ship time (Phase 6):
replace with the real appid and delete the txt from shipped builds.

## Notes

- Committing the extension binaries to this (private) repo after installing
  is fine and recommended so every checkout just works.
- Both extensions must be present on every machine that plays via Steam.
