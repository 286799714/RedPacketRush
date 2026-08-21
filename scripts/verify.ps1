[CmdletBinding()]
param(
    [string]$GodotPath = "",
    [switch]$SkipInstall,
    [switch]$LiveSmoke,
    [switch]$RequireCleanTree,
    [switch]$CleanCheckout
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryDirectory = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$serverDirectory = Join-Path $repositoryDirectory "server"
$clientDirectory = Join-Path $repositoryDirectory "client"
$gitCommand = (Get-Command "git" -ErrorAction Stop).Source
$nodeCommand = (Get-Command "node" -ErrorAction Stop).Source
$npmCommand = (Get-Command "npm" -ErrorAction Stop).Source

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $FilePath @ArgumentList
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = @(
        $RequestedPath,
        $env:GODOT_PATH,
        $env:GODOT4,
        "godot",
        "godot4"
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "Godot was not found. Pass -GodotPath or set GODOT_PATH. GODOT4 is also supported."
}

function Get-GitOutput {
    param([string[]]$ArgumentList)

    $output = & $gitCommand -C $repositoryDirectory @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git -C $repositoryDirectory $($ArgumentList -join ' ')"
    }
    return @($output)
}

function Test-GitDiff {
    param([string[]]$ArgumentList)

    & $gitCommand -C $repositoryDirectory @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        return $false
    }
    if ($exitCode -eq 1) {
        return $true
    }
    throw "Git diff check failed: git -C $repositoryDirectory $($ArgumentList -join ' ')"
}

function Assert-CleanTree {
    $hasUnstagedChanges = Test-GitDiff @("diff", "--quiet", "--ignore-submodules", "--")
    $hasStagedChanges = Test-GitDiff @("diff", "--cached", "--quiet", "--ignore-submodules", "HEAD", "--")
    $untrackedFiles = @(Get-GitOutput @("ls-files", "--others", "--exclude-standard"))
    if ($hasUnstagedChanges -or $hasStagedChanges -or $untrackedFiles.Count -gt 0) {
        $status = @(Get-GitOutput @("status", "--porcelain", "--untracked-files=all"))
        throw "The Git worktree is not clean:`n$($status -join [Environment]::NewLine)"
    }
}

function Assert-TrackedArtifactHygiene {
    $trackedFiles = @(Get-GitOutput @("ls-files"))
    $violations = [System.Collections.Generic.List[string]]::new()
    $allowedSdkBinaries = @(
        "client/addons/colyseus/bin/colyseus_godot.windows.x86_64.debug.dll",
        "client/addons/colyseus/bin/colyseus_godot.windows.x86_64.release.dll"
    )

    foreach ($trackedFile in $trackedFiles) {
        $path = $trackedFile.Replace("\", "/")
        $isGeneratedOrLocal = (
            $path -match "(^|/)(node_modules|\.godot|\.mono|obj|\.vscode|\.idea)(/|$)" -or
            $path -match "^server/build/" -or
            $path -match "^client/bin/" -or
            $path -match "^\.scratch/[^/]+-visuals/" -or
            $path -match "(^|/)(\.DS_Store|Thumbs\.db)$" -or
            $path -match "\.log$"
        )
        $isSecret = (
            ($path -match "(^|/)\.env(?:\.|$)" -and $path -notmatch "\.example$") -or
            $path -match "(^|/)(id_rsa|id_ed25519|credentials\.json|secrets?\.json)$" -or
            $path -match "\.(pem|pfx|p12)$"
        )
        $isUnexpectedSdkBinary = (
            $path.StartsWith("client/addons/colyseus/bin/", [System.StringComparison]::Ordinal) -and
            $path -notin $allowedSdkBinaries
        )
        if ($isGeneratedOrLocal -or $isSecret -or $isUnexpectedSdkBinary) {
            $violations.Add($path)
        }
    }

    foreach ($requiredBinary in $allowedSdkBinaries) {
        if ($requiredBinary -notin $trackedFiles) {
            $violations.Add("missing required SDK binary: $requiredBinary")
        }
    }

    if ($violations.Count -gt 0) {
        throw "Tracked-artifact hygiene failed:`n$($violations -join [Environment]::NewLine)"
    }
}

function Assert-ToolVersions {
    $nodeVersion = (& $nodeCommand --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch "^v(?<major>\d+)\.") {
        throw "Unable to determine the Node.js version."
    }
    if ([int]$Matches.major -lt 22) {
        throw "Node.js 22 or newer is required; found $nodeVersion."
    }

    $godotVersion = (& $script:resolvedGodotPath --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $godotVersion -notmatch "^4\.7\.1\.stable(?:\.|$)") {
        throw "Godot 4.7.1 stable is required; found '$godotVersion'."
    }

    Write-Host "Node.js $nodeVersion"
    Write-Host "Godot $godotVersion"
}

function Invoke-CleanCheckoutVerification {
    Assert-CleanTree

    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $temporaryPrefix = $temporaryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $checkoutDirectory = [System.IO.Path]::GetFullPath(
        (Join-Path $temporaryRoot ("red-packet-rush-clean-" + [Guid]::NewGuid().ToString("N")))
    )
    if (-not $checkoutDirectory.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to create a clean checkout outside the system temp root: $checkoutDirectory"
    }

    try {
        Invoke-ExternalCommand `
            -FilePath $gitCommand `
            -ArgumentList @("clone", "--no-local", "--", $repositoryDirectory, $checkoutDirectory) `
            -WorkingDirectory $temporaryRoot

        $checkoutScript = Join-Path $checkoutDirectory "scripts\verify.ps1"
        if (-not (Test-Path -LiteralPath $checkoutScript -PathType Leaf)) {
            throw "The clean checkout does not contain scripts/verify.ps1."
        }
        $powerShellExecutable = (Get-Process -Id $PID).Path
        Invoke-ExternalCommand `
            -FilePath $powerShellExecutable `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $checkoutScript,
                "-GodotPath", $script:resolvedGodotPath,
                "-LiveSmoke",
                "-RequireCleanTree"
            ) `
            -WorkingDirectory $checkoutDirectory
    }
    finally {
        if (Test-Path -LiteralPath $checkoutDirectory) {
            $resolvedCheckout = (Resolve-Path -LiteralPath $checkoutDirectory).Path
            if (-not $resolvedCheckout.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to clean a directory outside the system temp root: $resolvedCheckout"
            }
            Remove-Item -LiteralPath $resolvedCheckout -Recurse -Force
        }
    }
}

$resolvedGodotPath = Resolve-GodotExecutable $GodotPath
Assert-ToolVersions

if ($CleanCheckout) {
    Invoke-CleanCheckoutVerification
    Write-Host "PASS: clean-checkout verification"
    return
}

Write-Host "== Tracked-artifact hygiene =="
Assert-TrackedArtifactHygiene
if ($RequireCleanTree) {
    Assert-CleanTree
}

if (-not $SkipInstall) {
    Write-Host "== Install server dependencies =="
    Invoke-ExternalCommand -FilePath $npmCommand -ArgumentList @("ci") -WorkingDirectory $serverDirectory
}

Write-Host "== Server tests =="
Invoke-ExternalCommand -FilePath $npmCommand -ArgumentList @("test") -WorkingDirectory $serverDirectory

Write-Host "== TypeScript build =="
Invoke-ExternalCommand -FilePath $npmCommand -ArgumentList @("run", "build") -WorkingDirectory $serverDirectory

Write-Host "== Godot editor parse =="
Invoke-ExternalCommand `
    -FilePath $resolvedGodotPath `
    -ArgumentList @("--headless", "--editor", "--path", $clientDirectory, "--quit-after", "120") `
    -WorkingDirectory $clientDirectory

$headlessRunners = @(
    Get-ChildItem -LiteralPath (Join-Path $clientDirectory "tests") -File -Filter "run_*_tests.gd" |
        Sort-Object Name
)
if ($headlessRunners.Count -eq 0) {
    throw "No Godot headless test runners were found."
}
foreach ($runner in $headlessRunners) {
    Write-Host "== Godot runner: $($runner.Name) =="
    Invoke-ExternalCommand `
        -FilePath $resolvedGodotPath `
        -ArgumentList @(
            "--headless",
            "--path", $clientDirectory,
            "--script", "res://tests/$($runner.Name)"
        ) `
        -WorkingDirectory $clientDirectory
}

if ($LiveSmoke) {
    Write-Host "== Native SDK four-client smoke =="
    $smokeScript = Join-Path $clientDirectory "tests\run_live_lobby_smoke.ps1"
    & $smokeScript -GodotPath $resolvedGodotPath
}

if ($RequireCleanTree) {
    Assert-CleanTree
}

Write-Host "PASS: tracked-artifact hygiene, server tests/build, Godot parse, and $($headlessRunners.Count) headless runners"
if ($LiveSmoke) {
    Write-Host "PASS: Native SDK four-client smoke"
}
