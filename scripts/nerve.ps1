<#
.SYNOPSIS
    Nerve dev launcher for Windows — the counterpart to scripts/nerve.sh.

.DESCRIPTION
    Explicit flags only, like the bash one: nothing here runs unless it was
    asked for by name. Written for Windows PowerShell 5.1, which every
    Windows 10 and 11 ships — requiring pwsh 7 would mean a second install
    before the first run.

    scripts/nerve.sh stays the launcher on macOS and Linux; it is bash,
    xcodebuild and tmux, none of which apply here.
#>
[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Build,
    [switch]$Run,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Demo,
    [switch]$VerifyLoop,
    [switch]$VerifySurface,
    [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Release = Join-Path $Root 'target\release'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Nerve'
$StartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$Aumid = 'Nerve.Surface'
$Ingest = 'http://127.0.0.1:17890'

# The portable crates. nerve-tmux-surface is unix-only by design — tmux has no
# Windows port — so it is never named here.
$Crates = @('-p', 'nerve-platform', '-p', 'nerve-hub',
            '-p', 'nerve-surface-core', '-p', 'nerve-windows-surface')

function Show-Help {
    @'
Nerve (Windows)

  -Build           cargo build --release, the portable crates
  -Run             build, then start the tray surface
  -Install         copy to %LOCALAPPDATA%\Programs\Nerve, Start Menu shortcut
  -Uninstall       remove all of the above, including the Run key
  -Demo            POST the demo fixture (the hub must already be up)
  -VerifyLoop      ingest contract end to end
  -VerifySurface   headless surface self-test against a real hub
  -Test            cargo test, the portable crates
  -Help            this

Nothing runs without a flag.
'@ | Write-Host
}

function Invoke-Cargo {
    param([string[]]$Arguments)
    Push-Location $Root
    try {
        & cargo @Arguments
        if ($LASTEXITCODE -ne 0) { throw "cargo $($Arguments -join ' ') failed" }
    } finally {
        Pop-Location
    }
}

function Build-All {
    Invoke-Cargo (@('build', '--release') + $Crates)
}

function Wait-Hub {
    param([int]$Seconds = 10)
    for ($i = 0; $i -lt ($Seconds * 10); $i++) {
        try {
            Invoke-RestMethod -Uri "$Ingest/v1/health" -TimeoutSec 1 | Out-Null
            return $true
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    return $false
}

function Install-Nerve {
    Build-All
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($exe in @('nerve-hub.exe', 'nerve-windows-surface.exe')) {
        Copy-Item (Join-Path $Release $exe) (Join-Path $InstallDir $exe) -Force
    }

    # The shortcut is what carries the AppUserModelID, and the AUMID is what
    # lets an unpackaged app raise a toast under its own name. Written here
    # rather than by the surface because setting the property needs a shell
    # link, and doing that from Rust would mean COM and unsafe.
    $link = Join-Path $StartMenu 'Nerve.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = Join-Path $InstallDir 'nerve-windows-surface.exe'
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = 'Nerve'
    $shortcut.Save()

    # DisplayName for the toast; the surface writes this too, idempotently.
    $key = "HKCU:\Software\Classes\AppUserModelId\$Aumid"
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name 'DisplayName' -Value 'Nerve'

    Write-Host "Installed to $InstallDir"
    Write-Host "Shortcut: $link"
    Write-Host ''
    Write-Host 'Windows 11 hides new tray icons in the overflow by default —'
    Write-Host 'drag it out of the chevron to keep it visible.'
}

function Uninstall-Nerve {
    Remove-Item (Join-Path $StartMenu 'Nerve.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Classes\AppUserModelId\$Aumid" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'Nerve' -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Removed the binaries, the shortcut, the AUMID and the Run key.'
}

function Invoke-Demo {
    $fixture = Join-Path $Root 'fixtures\demo_snapshot.json'
    $body = Get-Content $fixture -Raw
    Invoke-RestMethod -Uri "$Ingest/v1/snapshot" -Method Post `
        -ContentType 'application/json' -Body $body | ConvertTo-Json -Depth 6
}

function Invoke-VerifyLoop {
    Build-All
    $hub = Start-Process (Join-Path $Release 'nerve-hub.exe') -ArgumentList 'serve' `
        -PassThru -WindowStyle Hidden
    try {
        if (-not (Wait-Hub)) { throw 'the hub never answered /v1/health' }

        $fixture = Join-Path $Root 'fixtures\demo_snapshot.json'
        Invoke-RestMethod -Uri "$Ingest/v1/snapshot" -Method Post `
            -ContentType 'application/json' -Body (Get-Content $fixture -Raw) | Out-Null

        $jobs = Invoke-RestMethod -Uri "$Ingest/v1/jobs"
        if ($jobs.Count -lt 1) { throw 'the hub accepted a snapshot and listed no jobs' }

        # An unknown route must be a 404, not a body — the same thing the
        # surface's own transport test asserts.
        try {
            Invoke-RestMethod -Uri "$Ingest/v1/nope" -TimeoutSec 2 | Out-Null
            throw 'an unknown route answered instead of 404'
        } catch [System.Net.WebException] {
            $code = [int]$_.Exception.Response.StatusCode
            if ($code -ne 404) { throw "unknown route answered $code" }
        }

        Write-Host "ALL OK — $($jobs.Count) job(s) through the loop"
    } finally {
        Stop-Process -Id $hub.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-VerifySurface {
    Build-All
    $hub = Start-Process (Join-Path $Release 'nerve-hub.exe') -ArgumentList 'serve' `
        -PassThru -WindowStyle Hidden
    try {
        if (-not (Wait-Hub)) { throw 'the hub never answered /v1/health' }
        Invoke-RestMethod -Uri "$Ingest/v1/snapshot" -Method Post `
            -ContentType 'application/json' `
            -Body (Get-Content (Join-Path $Root 'fixtures\demo_snapshot.json') -Raw) | Out-Null

        # The surface's own tests already cover the icon and the tooltip; what
        # only a real Windows box can add is that the binary starts, takes its
        # lock, and holds a stream against a live hub.
        $surface = Start-Process (Join-Path $Release 'nerve-windows-surface.exe') `
            -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        if ($surface.HasExited) { throw "the surface exited with $($surface.ExitCode)" }

        # A second copy must stand down rather than take a second stream.
        $second = Start-Process (Join-Path $Release 'nerve-windows-surface.exe') `
            -PassThru -WindowStyle Hidden -Wait
        if ($second.ExitCode -ne 0) { throw "the second instance exited $($second.ExitCode)" }
        if ($surface.HasExited) { throw 'the second instance killed the first' }

        Stop-Process -Id $surface.Id -Force
        Write-Host 'ALL OK — surface attaches, and a second instance stands down'
    } finally {
        Stop-Process -Id $hub.Id -Force -ErrorAction SilentlyContinue
    }
}

if ($Help -or -not ($Build -or $Run -or $Install -or $Uninstall -or $Demo -or
                    $VerifyLoop -or $VerifySurface -or $Test)) {
    Show-Help
    return
}

if ($Build)         { Build-All }
if ($Test)          { Invoke-Cargo (@('test') + $Crates) }
if ($Install)       { Install-Nerve }
if ($Uninstall)     { Uninstall-Nerve }
if ($Demo)          { Invoke-Demo }
if ($VerifyLoop)    { Invoke-VerifyLoop }
if ($VerifySurface) { Invoke-VerifySurface }
if ($Run) {
    Build-All
    Start-Process (Join-Path $Release 'nerve-windows-surface.exe')
}
