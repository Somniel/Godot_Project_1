# Steam Multiplayer PoC

A proof-of-concept for multi-server multiplayer architecture using Godot 4.5 and Steam networking. Players can host servers, join via Steam lobbies, and travel between independently hosted server instances.

## Tech Stack

- **Engine**: Godot 4.5.1 (Steam version)
- **Networking**: GodotSteam 4.17 (GDExtension)
- **Transport**: Steam P2P with NAT traversal + SDR fallback
- **Testing**: GUT 9.5.0 (Godot Unit Testing)

## Features

- Steam lobby system (create, join, browse)
- P2P networking with SteamMultiplayerPeer
- Server-authoritative multiplayer
- Interactive lobby totem with info display
- Portal travel between servers (planned)

## Quick Start

### Prerequisites

- Godot 4.5.1 (Steam version recommended)
- Steam client running
- Steam App ID (set via environment variable)

### Setup

1. Clone the repository
2. Set the `STEAM_APP_ID` environment variable:
   ```powershell
   # Windows (PowerShell)
   $env:STEAM_APP_ID = "YOUR_APP_ID"
   ```
3. Open the project in Godot
4. Run the main scene

### Running Tests

```bash
# Via Godot editor: Use the GUT panel in the bottom dock

# Via command line:
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -ginclude_subdirs
```

## Documentation

| Document | Description |
|----------|-------------|
| [CLAUDE.md](CLAUDE.md) | Architecture, code standards, patterns |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setup guide, PR guidelines |
| [.github/SECRETS.md](.github/SECRETS.md) | CI/CD configuration |

## Project Structure

```
autoload/           # Singleton managers (Steam, Lobby, Network)
scenes/             # Game scenes (menu, world, player)
scripts/            # Shared utilities and components
tests/              # GUT unit and integration tests
.github/workflows/  # CI/CD pipelines
```

## CI/CD

- **Pull Requests**: Automated tests and linting
- **Releases**: Builds and deploys to Steam (beta branch)

## License

This project is private. GUT testing framework is MIT licensed.
