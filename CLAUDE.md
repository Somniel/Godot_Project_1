# Steam Multiplayer PoC

## Overview

Proof-of-concept for multi-server multiplayer architecture using Godot 4.5 and Steam networking. Players can host servers, join via Steam lobbies, and travel between independently hosted server instances through portals.

## Tech Stack

- Godot 4.5.1 Steam version (v4.5.1.stable.steam)
- GodotSteam 4.17 (GDExtension from Asset Library)
- Steamworks SDK 1.63
- Steam P2P networking (NAT traversal + SDR fallback)

## Project Structure

```
autoload/           # Singleton managers
  steam_manager.gd    - Steam init, callbacks, identity
  lobby_manager.gd    - Create/join/leave/query lobbies
  network_manager.gd  - MultiplayerPeer, RPC routing, travel

scenes/
  main_menu/          - Menu, server browser, host options
  world/              - Server scenes, portals
  player/             - Networked player

scripts/              # Shared utilities and data classes
```

## Code Standards

- **Static typing required**: `var x: int = 0` or `var x := 0`
- **Private members**: prefix with underscore `_internal_var`
- **Signals**: past tense naming `player_connected`, `lobby_created`
- **RPCs**: always specify authority `@rpc("any_peer")` or `@rpc("authority")`
- **Line length**: max 100 characters
- **Escape sequences**: GDScript does not support `\x` hex escapes. Use `char(code)` instead:
  ```gdscript
  # Wrong - parser error
  var s: String = "Hello\x00World"

  # Correct - use char() for special characters
  var s: String = "Hello" + char(0) + "World"
  ```

## Commands

```bash
gdformat .           # Format all GDScript files
gdlint .             # Lint all GDScript files
pre-commit run -a    # Run all pre-commit hooks
```

## Architecture Rules

### Autoload Responsibilities

| Autoload | Scope |
|----------|-------|
| steam_manager | Steam init, shutdown, local Steam ID only |
| lobby_manager | Lobby CRUD, metadata, queries only |
| network_manager | MultiplayerPeer, RPCs, travel coordination |

### Multiplayer Patterns

- Server-authoritative: server validates all state changes
- Use `MultiplayerSpawner` for networked scene instantiation
- Use `MultiplayerSynchronizer` for property replication
- RPCs live in autoloads, not scattered across scenes
- Check `multiplayer.is_server()` before authoritative actions

### Portal Travel

**Client travel:**
1. Server sends RPC with destination lobby ID
2. Client leaves current lobby
3. Client joins destination lobby
4. Load appropriate scene

**Host travel (future phase):**
1. Save server state to local file
2. Notify clients of shutdown
3. Close lobby
4. Transition to client, join destination

### Lobby Metadata Schema

```gdscript
{
  "server_type": "town" | "field",
  "server_name": String,
  "linked_portals": "lobby_id1,lobby_id2,...",
  "player_count": String,
  "origin_town": String  # For Field servers
}
```

## MVP Scope (Current Phase)

- Single server type (no Town/Field distinction)
- Anyone can host
- Client portal travel only (host blocked)
- No persistence
- Basic server browser (no filtering)

## File Boundaries

Do not mix concerns across autoloads. Each manager handles its domain exclusively. Cross-cutting operations go through network_manager which coordinates the others.

## Testing

- Set `STEAM_APP_ID` environment variable before running (required)
- Multi-client testing requires separate Steam accounts
- Test portal travel with two running instances

## Troubleshooting

### GodotSteam GDExtension fails to load on Steam version of Godot

**Symptoms:**
```
ERROR: Can't open dynamic library: .../libgodotsteam.windows.template_debug.x86_64.dll.
Error: Error 127: The specified procedure could not be found.
```

**Cause:** The Steam version of Godot ships with an outdated `steam_api64.dll` that conflicts with GodotSteam's newer SDK version.

**Fix:** Replace the Steam API DLL in Godot's installation with the one from GodotSteam:

1. Close Godot completely
2. Backup the original: `C:/Games/Steam/steamapps/common/Godot Engine/steam_api64.dll`
3. Copy from project: `addons/godotsteam/win64/steam_api64.dll` → Godot installation folder
4. Restart Godot

**Note:** Steam updates may restore the old DLL. If GodotSteam stops loading after a Godot update, repeat this fix.

### Asset Library returns 404 on standalone Godot

The standalone Godot 4.5.0 download had network/TLS issues preventing Asset Library access. Using the Steam version of Godot (v4.5.1) resolves this issue.

## Export & Deployment

### Automated Deployment (Recommended)

The project includes GitHub Actions workflows for automated builds and Steam deployment:

1. **On Pull Request**: Runs tests and linting
2. **On Release**: Builds for Windows/Linux and uploads to Steam

To enable automated Steam deployment:
1. Configure repository secrets (see `.github/SECRETS.md`)
2. Create a GitHub Release
3. The workflow automatically builds and uploads to Steam's beta branch

### Manual Export

1. **Project → Export** → Select Windows preset
2. Export as **Release** to `builds/windows/`
3. Copy `addons/godotsteam/win64/steam_api64.dll` to build folder
4. Ensure `steam_appid.txt` exists with app ID

### Manual Upload to Steam

Using SteamCMD:
```bash
steamcmd +login <username> +run_app_build /path/to/steamworks_build.vdf +quit
```

Or use the Steamworks GUI from the SDK `tools/ContentBuilder/` folder.

### Adding Testers

1. Go to partner.steamgames.com
2. **Users & Permissions → Manage Users** → Add by email
3. Or generate keys: **App Admin → Request Steam Product Keys**

## Security Patterns

### RPC Authority Validation

Always validate the sender in RPCs that could affect game state:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func sync_player_data(data: Dictionary) -> void:
    # Validate sender matches the node's authority
    var sender_id: int = multiplayer.get_remote_sender_id()
    # sender_id is 0 for local calls
    if sender_id != 0 and sender_id != get_multiplayer_authority():
        push_warning("Rejected unauthorized sync from peer %d" % sender_id)
        return
    # Process data safely
```

### Input Sanitization

Always sanitize user-provided strings before display using `Utils.sanitize_display_string()`:

```gdscript
# Use the Utils class for consistent sanitization
var safe_name: String = Utils.sanitize_display_string(untrusted_input)
label.text = safe_name
```

### Scene Lifecycle Cleanup

Always disconnect signals in `_exit_tree()` to prevent orphaned connections:

```gdscript
func _exit_tree() -> void:
    if SomeAutoload.some_signal.is_connected(_handler):
        SomeAutoload.some_signal.disconnect(_handler)
```

### Null Safety for Scene Instantiation

Always validate scene instantiation results:

```gdscript
var instance: Node = SCENE.instantiate()
if instance == null:
    push_error("Failed to instantiate scene")
    return
```

### Lobby ID Validation

Use `Utils.is_valid_lobby_id()` before operations:

```gdscript
if not Utils.is_valid_lobby_id(lobby_id):
    return
```

## Collision Layers

| Layer | Purpose |
|-------|---------|
| 1 | Default/World geometry |
| 2 | Players |
| 4 | Interactables |

## Antipatterns to Avoid

### DON'T: Trust Client Authority for State Changes

```gdscript
# BAD - client decides damage without server validation
@rpc("any_peer")
func take_damage(amount: int) -> void:
    health -= amount  # Client could send negative damage!

# GOOD - server validates before applying
@rpc("any_peer", "call_local", "reliable")
func request_damage(amount: int) -> void:
    if not multiplayer.is_server():
        return
    if amount < 0 or amount > MAX_DAMAGE:
        return
    health -= amount
```

### DON'T: Store Sensitive Data in Lobby Metadata

```gdscript
# BAD - anyone can read lobby metadata via Steam API
set_lobby_metadata("admin_password", password)  # Never do this!

# GOOD - keep sensitive data server-side only, never in lobby metadata
# Use server-authoritative validation instead of shared secrets
```

### DON'T: Skip Sender Validation in RPCs

```gdscript
# BAD - any peer can impersonate any player
@rpc("any_peer")
func set_player_name(name: String) -> void:
    _name_label.text = name

# GOOD - validate sender matches authority
@rpc("any_peer", "call_local", "reliable")
func set_player_name(name: String) -> void:
    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id != 0 and sender_id != get_multiplayer_authority():
        return
    _name_label.text = Utils.sanitize_display_string(name)
```

### DON'T: Use `call_deferred` for Network-Critical Operations

```gdscript
# BAD - timing issues with replication
call_deferred("spawn_player")  # May miss replication window

# GOOD - spawn immediately when network is ready
_spawn_player(peer_id)
```

### DON'T: Hardcode Network IDs

```gdscript
# BAD - assumes peer 1 is always server
if peer_id == 1:
    # do server stuff

# GOOD - use proper API
if multiplayer.is_server():
    # do server stuff
```

### DON'T: Ignore Signal Disconnection

```gdscript
# BAD - signals remain connected after scene change
func _ready() -> void:
    SomeAutoload.signal.connect(_handler)
    # No cleanup!

# GOOD - always clean up
func _ready() -> void:
    SomeAutoload.signal.connect(_handler)

func _exit_tree() -> void:
    if SomeAutoload.signal.is_connected(_handler):
        SomeAutoload.signal.disconnect(_handler)
```

## Unit Testing

Tests use the GUT (Godot Unit Testing) framework located in `addons/gut/`.

### Running Tests

```bash
# Run all tests from command line
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/

# Or use the GUT panel in the editor (bottom dock)
```

### Test Structure

```
tests/
  unit/
    test_utils.gd           - Utils class tests
    test_lobby_manager.gd   - LobbyManager tests (mocked Steam)
    test_network_manager.gd - NetworkManager tests
  integration/
    test_lobby_flow.gd      - End-to-end lobby tests
```

### Writing Tests

```gdscript
extends GutTest

func test_sanitize_removes_control_chars() -> void:
    var test_string: String = "Hello" + char(0) + "World"
    var result: String = Utils.sanitize_display_string(test_string)
    assert_eq(result, "HelloWorld")

func test_valid_lobby_id() -> void:
    assert_true(Utils.is_valid_lobby_id(12345))
    assert_false(Utils.is_valid_lobby_id(0))
    assert_false(Utils.is_valid_lobby_id(-1))
```
