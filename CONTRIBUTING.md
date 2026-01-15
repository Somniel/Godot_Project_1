# Contributing to Steam Multiplayer PoC

> **Notice:** This project is not accepting external contributions. Pull requests from outside collaborators will not be reviewed or merged.

This document is retained for internal development reference only.

---

## CI/CD Overview

This project uses GitHub Actions for:
- **Automated Testing**: Runs GUT tests and linting on every PR
- **Steam Deployment**: Builds and uploads to Steam on release

See [.github/SECRETS.md](.github/SECRETS.md) for required repository secrets.

## Initial Setup

### 1. Steam Configuration (Required)

The `STEAM_APP_ID` environment variable must be set before running the project:

```bash
# Windows (PowerShell)
$env:STEAM_APP_ID = "YOUR_APP_ID"

# Windows (CMD)
set STEAM_APP_ID=YOUR_APP_ID

# Linux/macOS
export STEAM_APP_ID=YOUR_APP_ID
```

The project will not initialize Steam without this variable set.

### 2. Create steam_appid.txt

Create a file named `steam_appid.txt` in the project root containing your App ID:
```
480
```
This file is gitignored and required for Steam to initialize in the editor.

### 3. Steamworks Build Configuration (Optional)

If you plan to upload builds to Steam:

1. Copy `steamworks_build.vdf.template` to `steamworks_build.vdf`
2. Edit with your App ID and Depot ID
3. Copy `upload_to_steam.bat.template` to `upload_to_steam.bat`
4. Set the `STEAMCMD_PATH` environment variable

## Running Tests

1. Install GUT from the Godot Asset Library (search "Gut - Godot Unit Testing")
2. Enable the plugin: Project → Project Settings → Plugins → GUT
3. Run tests via the GUT panel in the bottom dock

Or from command line:
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/
```

## Code Standards

See [CLAUDE.md](CLAUDE.md) for detailed coding standards and patterns.

Key points:
- Static typing required for all variables
- Private members prefixed with `_`
- Always validate RPC senders
- Sanitize user input before display
- Disconnect signals in `_exit_tree()`

## Pull Request Guidelines

1. Ensure all tests pass
2. Follow the code standards in CLAUDE.md
3. Add tests for new functionality
4. Update documentation if needed
5. Do not commit sensitive information (API keys, personal paths, etc.)
