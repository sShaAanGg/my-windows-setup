<#
  install-apps.ps1 - Install my apps on Windows 11.

  Apps:
    Spotify          (winget)            - always
    Flameshot        (winget)            - always
    LINE             (winget)            - always
    Steam            (winget)            - always
    Discord          (winget)            - always
    VS Code          (winget)            - optional
    Pebrel terminal  (GitHub release)    - optional

  Run from a NORMAL (non-admin) PowerShell window. Spotify refuses to install
  from an elevated window, and Pebrel installs per-user.

    powershell -ExecutionPolicy Bypass -File .\install-apps.ps1             # asks about optional apps
    powershell -ExecutionPolicy Bypass -File .\install-apps.ps1 -All        # install everything, no questions
    powershell -ExecutionPolicy Bypass -File .\install-apps.ps1 -NoOptional # required apps only
    add -Upgrade to any of the above to also update apps already installed
#>

param(
    [switch]$All,
    [switch]$NoOptional,
    [switch]$Upgrade
)

# ---- App list ---------------------------------------------------------------
# Type 'winget' -> Id is the winget package ID
# Type 'github' -> Id is "owner/repo"; AssetPattern picks the installer from the latest release
$Apps = @(
    @{ Name = "Spotify";   Type = "winget"; Id = "Spotify.Spotify";            Optional = $false },
    @{ Name = "Flameshot"; Type = "winget"; Id = "Flameshot.Flameshot";        Optional = $false },
    @{ Name = "LINE";      Type = "winget"; Id = "LINE.LINE";                  Optional = $false },
    @{ Name = "Steam";     Type = "winget"; Id = "Valve.Steam";                Optional = $false },
    @{ Name = "Discord";   Type = "winget"; Id = "Discord.Discord";            Optional = $false },
    @{ Name = "VS Code";   Type = "winget"; Id = "Microsoft.VisualStudioCode"; Optional = $true  },
    @{ Name = "Pebrel";    Type = "github"; Id = "Kuddev/pebrel";              Optional = $true
       AssetPattern = '^Pebrel-v[\d\.]+-windows-x64-setup\.exe$'
       RegistryName = 'Pebrel*'
       # Inno Setup silent flags
       SilentArgs   = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' }
)
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "Note: running as Administrator. Spotify may fail to install; if so, rerun from a normal window." -ForegroundColor Yellow
}

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($name, $status) { $results.Add([pscustomobject]@{ App = $name; Result = $status }) }

# ---- Helpers ----------------------------------------------------------------
function Test-WingetInstalled($id) {
    winget list --id $id --exact --accept-source-agreements *> $null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetApp($app) {
    if (Test-WingetInstalled $app.Id) {
        if ($Upgrade) {
            Write-Host "Already installed - checking for update..."
            winget upgrade --id $app.Id --exact --silent --accept-package-agreements --accept-source-agreements
            Add-Result $app.Name "Checked for update"
        } else {
            Write-Host "Already installed - skipping." -ForegroundColor Yellow
            Add-Result $app.Name "Already installed"
        }
        return
    }
    winget install --id $app.Id --exact --silent --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Add-Result $app.Name "Installed" }
    else                     { Add-Result $app.Name "FAILED (winget exit $LASTEXITCODE)" }
}

function Get-InstalledVersion($displayNamePattern) {
    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entry = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like $displayNamePattern } |
             Select-Object -First 1
    if ($entry) { return [string]$entry.DisplayVersion }
    return $null
}

function Install-GitHubApp($app) {
    Write-Host "Checking latest release of $($app.Id)..."
    $release = Invoke-RestMethod "https://api.github.com/repos/$($app.Id)/releases/latest" `
               -Headers @{ 'User-Agent' = 'install-apps-script' }
    $latest  = $release.tag_name.TrimStart('v')

    $installed = Get-InstalledVersion $app.RegistryName
    if ($installed) {
        if (-not $Upgrade) {
            Write-Host "Already installed (v$installed) - skipping." -ForegroundColor Yellow
            Add-Result $app.Name "Already installed"
            return
        }
        if ($installed -eq $latest) {
            Write-Host "Already on latest (v$installed)." -ForegroundColor Yellow
            Add-Result $app.Name "Up to date"
            return
        }
        Write-Host "Updating v$installed -> v$latest"
    }

    $asset = $release.assets | Where-Object { $_.name -match $app.AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        Add-Result $app.Name "FAILED (no installer matching pattern in release $($release.tag_name))"
        return
    }

    $file = Join-Path $env:TEMP $asset.name
    Write-Host "Downloading $($asset.name)..."
    $ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster
    Invoke-WebRequest $asset.browser_download_url -OutFile $file

    # Verify SHA-256 if GitHub provides a digest for the asset
    if ($asset.digest -and $asset.digest -like 'sha256:*') {
        $expected = $asset.digest.Substring(7)
        $actual   = (Get-FileHash $file -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
            Remove-Item $file -Force
            Add-Result $app.Name "FAILED (checksum mismatch - file deleted)"
            return
        }
        Write-Host "Checksum OK."
    }

    Write-Host "Installing silently..."
    $p = Start-Process $file -ArgumentList $app.SilentArgs -Wait -PassThru
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -eq 0) { Add-Result $app.Name "Installed v$latest" }
    else                   { Add-Result $app.Name "FAILED (installer exit $($p.ExitCode))" }
}

# ---- Main -------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget not found. Install/update 'App Installer' from the Microsoft Store, then rerun." -ForegroundColor Red
    exit 1
}
winget source update *> $null

foreach ($app in $Apps) {
    Write-Host "`n=== $($app.Name) ===" -ForegroundColor Cyan

    if ($app.Optional) {
        if ($NoOptional) { Add-Result $app.Name "Skipped (optional)"; continue }
        if (-not $All) {
            $answer = Read-Host "Install optional app '$($app.Name)'? [y/N]"
            if ($answer -notmatch '^(y|yes)$') { Add-Result $app.Name "Skipped (optional)"; continue }
        }
    }

    try {
        switch ($app.Type) {
            'winget' { Install-WingetApp $app }
            'github' { Install-GitHubApp $app }
        }
    } catch {
        Add-Result $app.Name "FAILED ($($_.Exception.Message))"
    }
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
$results | Format-Table -AutoSize
if ($results.Result -match '^FAILED') { exit 1 }
