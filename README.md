# my-windows-setup
downloads my favorite windows apps by Poweshell scripting

## Apps
  - Spotify          (winget)            - always
  - Flameshot        (winget)            - always
  - LINE             (winget)            - always
  - Steam            (winget)            - always
  - Discord          (winget)            - always
  - VS Code          (winget)            - optional
  - Pebrel terminal  (GitHub release)    - optional

## How to Use the Script
- Run from a NORMAL (non-admin) PowerShell window.
  - Spotify refuses to install from an elevated window, and Pebrel installs per-user.

## Run in the Shell
- powershell -ExecutionPolicy Bypass -File .\install-apps.ps1             # asks about optional apps
- powershell -ExecutionPolicy Bypass -File .\install-apps.ps1 -All        # install everything, no questions
- powershell -ExecutionPolicy Bypass -File .\install-apps.ps1 -NoOptional # required apps only

Add -Upgrade to any of the above to also update apps already installed
