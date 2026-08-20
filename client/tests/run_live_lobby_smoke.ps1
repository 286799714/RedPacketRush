param(
    [string]$GodotPath = $env:GODOT4,
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$clientDirectory = Split-Path -Parent $PSScriptRoot
$repositoryDirectory = Split-Path -Parent $clientDirectory
$serverDirectory = Join-Path $repositoryDirectory "server"
$tsxCli = Join-Path $serverDirectory "node_modules\tsx\dist\cli.mjs"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command "godot" -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        throw "Godot was not found. Pass -GodotPath or set GODOT4."
    }
    $GodotPath = $godotCommand.Source
}

$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$nodePath = (Get-Command "node" -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath $tsxCli -PathType Leaf)) {
    throw "Server dependencies are missing. Run npm install in $serverDirectory."
}

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback,
    0
)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$runDirectory = Join-Path $temporaryRoot (
    "red-packet-rush-smoke-" + [Guid]::NewGuid().ToString("N")
)
$runDirectory = [System.IO.Path]::GetFullPath($runDirectory)
$temporaryPrefix = $temporaryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $runDirectory.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a smoke-test directory outside the system temp root: $runDirectory"
}
$null = New-Item -ItemType Directory -Path $runDirectory
$serverStdout = Join-Path $runDirectory "server.stdout.log"
$serverStderr = Join-Path $runDirectory "server.stderr.log"
$godotStdout = Join-Path $runDirectory "godot.stdout.log"
$godotStderr = Join-Path $runDirectory "godot.stderr.log"
$serverProcess = $null
$godotProcess = $null

try {
    $previousPort = $env:PORT
    $env:PORT = [string]$port
    try {
        $serverProcess = Start-Process `
            -FilePath $nodePath `
            -ArgumentList @($tsxCli, "src/index.ts") `
            -WorkingDirectory $serverDirectory `
            -RedirectStandardOutput $serverStdout `
            -RedirectStandardError $serverStderr `
            -WindowStyle Hidden `
            -PassThru
    }
    finally {
        $env:PORT = $previousPort
    }

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $ready = $false
    while ([DateTime]::UtcNow -lt $readyDeadline) {
        if ($serverProcess.HasExited) {
            throw "Colyseus exited before becoming ready."
        }
        try {
            $response = Invoke-WebRequest `
                -Uri "http://127.0.0.1:$port/" `
                -TimeoutSec 1 `
                -UseBasicParsing
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if (-not $ready) {
        throw "Colyseus did not become ready within 10 seconds."
    }

    $godotProcess = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList @(
            "--headless",
            "--path", $clientDirectory,
            "--script", "res://tests/run_live_lobby_smoke.gd",
            "--",
            "--endpoint=ws://127.0.0.1:$port"
        ) `
        -WorkingDirectory $clientDirectory `
        -RedirectStandardOutput $godotStdout `
        -RedirectStandardError $godotStderr `
        -WindowStyle Hidden `
        -PassThru

    if (-not $godotProcess.WaitForExit($TimeoutSeconds * 1000)) {
        $godotProcess.Kill($true)
        $godotProcess.WaitForExit()
        throw "Godot smoke test exceeded its $TimeoutSeconds second process timeout."
    }

    Get-Content -LiteralPath $godotStdout
    if ((Get-Item -LiteralPath $godotStderr).Length -gt 0) {
        Get-Content -LiteralPath $godotStderr
    }
    if ($godotProcess.ExitCode -ne 0) {
        throw "Godot smoke test exited with code $($godotProcess.ExitCode)."
    }
}
catch {
    if (Test-Path -LiteralPath $serverStdout) {
        Write-Host "--- Colyseus stdout ---"
        Get-Content -LiteralPath $serverStdout
    }
    if (Test-Path -LiteralPath $serverStderr) {
        Write-Host "--- Colyseus stderr ---"
        Get-Content -LiteralPath $serverStderr
    }
    if (Test-Path -LiteralPath $godotStdout) {
        Write-Host "--- Godot stdout ---"
        Get-Content -LiteralPath $godotStdout
    }
    if (Test-Path -LiteralPath $godotStderr) {
        Write-Host "--- Godot stderr ---"
        Get-Content -LiteralPath $godotStderr
    }
    throw
}
finally {
    if ($null -ne $godotProcess -and -not $godotProcess.HasExited) {
        $godotProcess.Kill($true)
        $godotProcess.WaitForExit()
    }
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        $serverProcess.Kill($true)
        $serverProcess.WaitForExit()
    }
    if (Test-Path -LiteralPath $runDirectory) {
        $cleanupDirectory = (Resolve-Path -LiteralPath $runDirectory).Path
        if (-not $cleanupDirectory.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a directory outside the system temp root: $cleanupDirectory"
        }
        Remove-Item -LiteralPath $cleanupDirectory -Recurse -Force
    }
}
