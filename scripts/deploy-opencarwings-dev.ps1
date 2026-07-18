[CmdletBinding()]
param(
    [string]$Destination = "\\HOMEASSISTANT\addons\opencarwings-dev",
    [switch]$AllowDirty,
    [switch]$ConfirmDevStopped,
    [switch]$DryRun,
    [ValidateRange(0, 30)]
    [int]$SmbFlushSeconds = 3
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $RepoRoot "opencarwings"
$ExpectedDestinationLeaf = "opencarwings-dev"
$DevName = "OpenCarwings (Local Dev)"
$DevSlug = "opencarwings-dev"
$GitExe = $null
$RobocopyExe = $null

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($gitCommand) {
    $GitExe = $gitCommand.Source
}
else {
    $gitCandidate = Join-Path $env:ProgramFiles "Git\cmd\git.exe"
    if (Test-Path -LiteralPath $gitCandidate -PathType Leaf) {
        $GitExe = $gitCandidate
    }
}
if (-not $GitExe) {
    throw "Git for Windows was not found in PATH or Program Files."
}

$robocopyCommand = Get-Command robocopy -ErrorAction SilentlyContinue
if ($robocopyCommand) {
    $RobocopyExe = $robocopyCommand.Source
}
else {
    $robocopyCandidate = Join-Path $env:SystemRoot "System32\robocopy.exe"
    if (Test-Path -LiteralPath $robocopyCandidate -PathType Leaf) {
        $RobocopyExe = $robocopyCandidate
    }
}
if (-not $RobocopyExe) {
    throw "Robocopy was not found in PATH or Windows System32."
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $GitExe
    $processInfo.WorkingDirectory = $RepoRoot
    $processInfo.Arguments = $Arguments -join ' '
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Unable to start Git for Windows."
    }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $stderr"
    }
    return @($stdout -split "`r?`n" | Where-Object { $_ -ne "" })
}

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $RobocopyExe
    $processInfo.Arguments = '"{0}" "{1}" /MIR /XJ /XD .git .vscode /NFL /NDL /NJH /NJS /NP /R:2 /W:2' -f $SourceRoot, $DestinationRoot
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Unable to start Robocopy."
    }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -gt 7) {
        throw "Robocopy failed with exit code $exitCode. $stderr $stdout"
    }
}

function Get-RelativeFiles {
    param([Parameter(Mandatory)][string]$Root)

    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\') } |
            Sort-Object
    )
}

function Get-ExpectedDevConfig {
    param([Parameter(Mandatory)][string]$SourceConfig)

    $sourceText = [System.IO.File]::ReadAllText($SourceConfig)
    if ([regex]::Matches($sourceText, '(?m)^name:\s*.*$').Count -ne 1) {
        throw "Source config.yaml must contain exactly one top-level name field."
    }
    if ([regex]::Matches($sourceText, '(?m)^slug:\s*.*$').Count -ne 1) {
        throw "Source config.yaml must contain exactly one top-level slug field."
    }

    $devText = [regex]::Replace($sourceText, '(?m)^name:\s*.*$', "name: $DevName")
    return [regex]::Replace($devText, '(?m)^slug:\s*.*$', "slug: $DevSlug")
}

function Get-SourceManifest {
    param([Parameter(Mandatory)][string]$Root)

    $manifest = [ordered]@{}
    foreach ($relativePath in (Get-RelativeFiles -Root $Root)) {
        $manifest[$relativePath] = (Get-FileHash -LiteralPath (Join-Path $Root $relativePath) -Algorithm SHA256).Hash
    }
    return $manifest
}

function Assert-SourceManifestUnchanged {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Expected
    )

    $current = Get-SourceManifest -Root $Root
    $pathDiff = @(Compare-Object -ReferenceObject @($Expected.Keys) -DifferenceObject @($current.Keys))
    if ($pathDiff.Count -ne 0) {
        throw "Source file list changed during deployment."
    }
    foreach ($relativePath in $Expected.Keys) {
        if ($Expected[$relativePath] -cne $current[$relativePath]) {
            throw "Source file changed during deployment: $relativePath"
        }
    }
}

function Assert-DeploymentMatches {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DeployedRoot
    )

    $sourceFiles = Get-RelativeFiles -Root $SourceRoot
    $deployedFiles = Get-RelativeFiles -Root $DeployedRoot
    $pathDiff = @(Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $deployedFiles)
    if ($pathDiff.Count -ne 0) {
        throw "Deployment file list differs from source: $($pathDiff | Out-String)"
    }

    foreach ($relativePath in $sourceFiles) {
        $sourcePath = Join-Path $SourceRoot $relativePath
        $deployedPath = Join-Path $DeployedRoot $relativePath

        if ($relativePath -eq "config.yaml") {
            $expectedConfig = Get-ExpectedDevConfig -SourceConfig $sourcePath
            $actualConfig = [System.IO.File]::ReadAllText($deployedPath)
            if ($actualConfig -cne $expectedConfig) {
                throw "Deployed config.yaml differs from the exact dev name/slug transform."
            }
            continue
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $deployedHash = (Get-FileHash -LiteralPath $deployedPath -Algorithm SHA256).Hash
        if ($sourceHash -cne $deployedHash) {
            throw "Deployed file hash mismatch: $relativePath"
        }
    }
}

if (-not $ConfirmDevStopped) {
    throw "Stop local_opencarwings-dev first, then rerun with -ConfirmDevStopped."
}
if (-not (Test-Path -LiteralPath (Join-Path $Source "config.yaml") -PathType Leaf)) {
    throw "Source add-on not found at $Source"
}
if (-not (Test-Path -LiteralPath (Join-Path $Source ".upstream_sync") -PathType Leaf)) {
    throw "Source .upstream_sync marker is missing."
}
if ((Get-Item -LiteralPath $Source).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    throw "Refusing a source add-on directory that is a reparse point."
}

$destinationItem = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
$destinationLeaf = if ($destinationItem) { $destinationItem.Name } else { Split-Path -Leaf $Destination }
if ($destinationLeaf -cne $ExpectedDestinationLeaf) {
    throw "Refusing destination '$Destination'; leaf must be exactly '$ExpectedDestinationLeaf'."
}
if ($destinationItem) {
    if (-not $destinationItem.PSIsContainer) {
        throw "Destination exists but is not a directory: $Destination"
    }
    if ($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Refusing a destination add-on directory that is a reparse point."
    }
}

$DestinationParent = Split-Path -Parent $Destination
if (-not (Test-Path -LiteralPath $DestinationParent -PathType Container)) {
    throw "Destination parent is unavailable: $DestinationParent"
}
if ([System.IO.Path]::GetFullPath($Source) -eq [System.IO.Path]::GetFullPath($Destination)) {
    throw "Source and destination must not be the same directory."
}

Write-Host "Fetching origin before deployment..."
Invoke-Git -Arguments @("fetch", "--prune", "--tags", "origin") | Out-Null
$originUrlOutput = @(Invoke-Git -Arguments @("remote", "get-url", "origin"))
$headOutput = @(Invoke-Git -Arguments @("rev-parse", "HEAD"))
$originMainOutput = @(Invoke-Git -Arguments @("rev-parse", "origin/main"))
$branchOutput = @(Invoke-Git -Arguments @("symbolic-ref", "--short", "HEAD"))
if ($originUrlOutput.Count -ne 1 -or $headOutput.Count -ne 1 -or $originMainOutput.Count -ne 1 -or $branchOutput.Count -ne 1) {
    throw "Git returned an unexpected revision result."
}
$originUrl = $originUrlOutput[0].Trim()
if ($originUrl -notin @(
    "https://github.com/Chaoscontrol/opencarwings-app.git",
    "git@github.com:Chaoscontrol/opencarwings-app.git"
)) {
    throw "Unexpected origin URL: $originUrl"
}
$head = $headOutput[0].Trim()
$originMain = $originMainOutput[0].Trim()
$branch = $branchOutput[0].Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Deploy from a named working branch, not a detached HEAD."
}
try {
    Invoke-Git -Arguments @("merge-base", "--is-ancestor", $originMain, $head) | Out-Null
}
catch {
    throw "Current branch does not contain origin/main ($originMain). Fast-forward/rebase before deploying."
}

$dirtyPaths = @(Invoke-Git -Arguments @("status", "--porcelain=v1", "--untracked-files=all", "--", "opencarwings"))
if ($dirtyPaths.Count -gt 0) {
    Write-Warning "The deployed add-on source has uncommitted changes:"
    $dirtyPaths | ForEach-Object { Write-Warning "  $_" }
    if (-not $AllowDirty) {
        throw "Dirty source requires the explicit -AllowDirty switch."
    }
}

$sensitivePathPattern = '(?i)(^|[\\/])(\.env(?:\..*)?|secrets?[^\\/]*|[^\\/]+\.(?:pem|key|p12|pfx))$'
$sensitiveFiles = @(
    Get-RelativeFiles -Root $Source |
        Where-Object { $_ -match $sensitivePathPattern }
)
if ($sensitiveFiles.Count -gt 0) {
    throw "Refusing to deploy sensitive-looking files from the add-on source: $($sensitiveFiles -join ', ')"
}

if ($DryRun) {
    $fileCount = (Get-RelativeFiles -Root $Source).Count
    Get-ExpectedDevConfig -SourceConfig (Join-Path $Source "config.yaml") | Out-Null
    Write-Host "Dry run passed for branch $branch at $head ($fileCount files)."
    Write-Host "No files were written to $Destination"
    exit 0
}

$SourceManifest = Get-SourceManifest -Root $Source

$Staging = Join-Path $DestinationParent ".$ExpectedDestinationLeaf.deploying"
$DeploymentStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Previous = Join-Path $DestinationParent ".$ExpectedDestinationLeaf.previous-$DeploymentStamp"
$Failed = Join-Path $DestinationParent ".$ExpectedDestinationLeaf.failed-$DeploymentStamp"
$LockPath = Join-Path $DestinationParent ".$ExpectedDestinationLeaf.deploy.lock"
$lockAcquired = $false
$destinationMoved = $false
$swapped = $false

try {
    try {
        New-Item -ItemType Directory -Path $LockPath -ErrorAction Stop | Out-Null
        $lockAcquired = $true
        $lockMetadata = "pid=$PID`r`nstarted=$([DateTimeOffset]::Now.ToString('o'))`r`n"
        [System.IO.File]::WriteAllText(
            (Join-Path $LockPath "owner.txt"),
            $lockMetadata,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        throw "Another deployment lock exists at $LockPath. Confirm no deployment is running before removing a stale lock manually."
    }

    if (Test-Path -LiteralPath $Staging) {
        if ((Get-Item -LiteralPath $Staging).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "Refusing a staging path that is a reparse point: $Staging"
        }
        Remove-Item -LiteralPath $Staging -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Staging | Out-Null

    Write-Host "Mirroring add-on source to staging..."
    Invoke-RobocopyMirror -SourceRoot $Source -DestinationRoot $Staging

    $stagedConfig = Join-Path $Staging "config.yaml"
    $expectedConfig = Get-ExpectedDevConfig -SourceConfig (Join-Path $Source "config.yaml")
    [System.IO.File]::WriteAllText(
        $stagedConfig,
        $expectedConfig,
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-SourceManifestUnchanged -Root $Source -Expected $SourceManifest
    Assert-DeploymentMatches -SourceRoot $Source -DeployedRoot $Staging
    Assert-SourceManifestUnchanged -Root $Source -Expected $SourceManifest

    if (Test-Path -LiteralPath $Destination) {
        Move-Item -LiteralPath $Destination -Destination $Previous
        $destinationMoved = $true
    }
    Move-Item -LiteralPath $Staging -Destination $Destination
    $swapped = $true

    if ($SmbFlushSeconds -gt 0) {
        Start-Sleep -Seconds $SmbFlushSeconds
    }
    Assert-DeploymentMatches -SourceRoot $Source -DeployedRoot $Destination

    Write-Host "Deployment verified at $Destination"
    Write-Host "Source commit: $head"
    if ($destinationMoved) {
        Write-Host "Previous deployment retained at $Previous"
    }
    else {
        Write-Host "This was the first deployment; no previous destination existed."
    }
    Write-Host "Refresh the local app store, rebuild local_opencarwings-dev, and verify its isolated Supervisor port mappings before starting it."
}
catch {
    $deploymentError = $_
    if ($destinationMoved -and (Test-Path -LiteralPath $Previous)) {
        try {
            if (Test-Path -LiteralPath $Destination) {
                Move-Item -LiteralPath $Destination -Destination $Failed
            }
            Move-Item -LiteralPath $Previous -Destination $Destination
            $destinationMoved = $false
            $swapped = $false
            Write-Warning "Deployment failed; restored the previous dev source. Failed output retained at $Failed"
        }
        catch {
            throw "Deployment failed and automatic rollback also failed. Previous='$Previous', destination='$Destination', failed='$Failed'. Original error: $deploymentError. Rollback error: $_"
        }
    }
    elseif ($swapped -and (Test-Path -LiteralPath $Destination)) {
        try {
            Move-Item -LiteralPath $Destination -Destination $Failed
            $swapped = $false
            Write-Warning "Deployment failed and no previous destination existed; failed output retained at $Failed"
        }
        catch {
            throw "Deployment failed and the invalid first deployment could not be quarantined. Destination='$Destination', failed='$Failed'. Original error: $deploymentError. Quarantine error: $_"
        }
    }
    throw $deploymentError
}
finally {
    if ($lockAcquired -and (Test-Path -LiteralPath $LockPath)) {
        Remove-Item -LiteralPath $LockPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $Staging) {
        Remove-Item -LiteralPath $Staging -Recurse -Force
    }
}
