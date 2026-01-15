# Required GitHub Secrets

This document describes the GitHub repository secrets required for CI/CD workflows.

## Steam Deployment Secrets

These secrets are required for the `deploy-steam.yml` workflow to upload builds to Steam.

### `STEAM_USERNAME`
The Steam account username used for uploading builds via SteamCMD.

**Recommendation**: Create a dedicated Steam account for CI/CD uploads rather than using a personal account.

### `STEAM_CONFIG_VDF`
Base64-encoded Steam configuration file that contains authentication tokens. This bypasses the need for interactive Steam Guard authentication in CI.

**How to generate:**
1. Install SteamCMD locally
2. Login once with Steam Guard: `steamcmd +login YOUR_USERNAME +quit`
3. Complete Steam Guard verification
4. Find the config file at `~/.steam/config/config.vdf` (Linux) or `C:\Users\YOU\steamcmd\config\config.vdf` (Windows)
5. Base64 encode it: `base64 -w 0 config.vdf`
6. Store the output as the secret value

**Security Note**: This file contains authentication tokens. Rotate periodically and use a dedicated build account.

### `STEAM_APP_ID`
Your Steam application ID (e.g., `1234560`).

**Where to find**: Steamworks Partner Portal → Your App → App Admin

### `STEAM_DEPOT_WINDOWS`
The depot ID for Windows builds (e.g., `1234561`).

**Where to find**: Steamworks Partner Portal → Your App → SteamPipe → Depots

## Setting Up Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret listed above

## Environment Variables for Local Development

The `STEAM_APP_ID` environment variable is **required** to run the project locally:

```bash
# Windows (PowerShell)
$env:STEAM_APP_ID = "YOUR_APP_ID"

# Windows (CMD)
set STEAM_APP_ID=YOUR_APP_ID

# Linux/macOS
export STEAM_APP_ID=YOUR_APP_ID
```

The project will fail to initialize Steam without this variable set.

## Security Best Practices

1. **Use a dedicated Steam account** for CI/CD uploads, not your personal account
2. **Limit account permissions** to only what's needed for uploads
3. **Rotate credentials** periodically
4. **Never commit secrets** to the repository
5. **Use GitHub's secret scanning** to detect accidental commits
6. **Enable branch protection** to require reviews before merging to main
