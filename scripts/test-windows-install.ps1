# Runs without Rust, a desktop, registry writes, or installed Nerve binaries.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [IO.Path]::GetTempPath() }
if (-not $env:APPDATA) { $env:APPDATA = [IO.Path]::GetTempPath() }
. (Join-Path $PSScriptRoot 'nerve.ps1') -Help

function Assert-True($condition, $message) {
    if (-not $condition) { throw $message }
}
function Assert-Throws($action, $message) {
    $caught = $false
    try { & $action } catch {
        $caught = $true
        Assert-True ($_.Exception.Message -like "*$message*") "Unexpected error: $_"
    }
    Assert-True $caught "Expected failure containing: $message"
}
function Invoke-Cargo { throw 'Prebuilt installation must not invoke Cargo' }

$temp = Join-Path ([IO.Path]::GetTempPath()) ('nerve-installer-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $Root = $temp
    $BinaryDirectory = $null
    foreach ($exe in @('nerve-hub.exe', 'nerve-windows-surface.exe')) {
        New-Item -ItemType File -Path (Join-Path $temp $exe) | Out-Null
    }
    $BinariesReady = $false
    Prepare-Binaries
    Assert-True ($Release -eq $temp) 'Downloaded bundle should be detected automatically'

    $BinaryDirectory = $temp
    $Root = Join-Path $temp 'checkout'
    $BinariesReady = $false
    Prepare-Binaries
    Assert-True ($Release -eq $temp) 'Explicit binary directory should work outside a bundle'

    Remove-Item (Join-Path $temp 'nerve-hub.exe')
    $BinariesReady = $false
    Assert-Throws { Prepare-Binaries } 'Missing nerve-hub.exe'

    $InstallDir = $temp
    function Get-Process { [pscustomobject]@{ Path = (Join-Path $InstallDir 'nerve-hub.exe') } }
    Assert-Throws { Assert-InstallStopped } 'Quit Nerve'

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 17890)
    try {
        $listener.Start()
        Assert-Throws { Assert-VerifyIsolated } 'already in use'
    } finally {
        $listener.Stop()
    }
    Assert-VerifyIsolated
    Write-Host 'ALL OK - prebuilt discovery, incomplete bundle, running install and verification isolation'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
