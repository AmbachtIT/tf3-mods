<#
.SYNOPSIS
Copies the mod into the Transport Fever 3 staging area.

.DESCRIPTION
Run after every edit, then restart the game - mods are read at startup.

Deploys to staging_area\ only, on purpose. The staging area is a full mod
install source in its own right - the game's precedence is Staging Area, then
the manual mods\ folder, then subscribed mods - so a mod there is playable as
well as publishable, and publishing (Modhub.ModPublishHelper) only ever reads
the staging area.

Deploying to both locations is what we used to do and it is worse: the log
fills with "Multiple (2) mods with same id found <id>, the one from
.../staging_area/... has been selected", and the staging copy silently wins. If
only one of the two gets redeployed, the game runs the other one and the
mistake is invisible.

.PARAMETER Mods
Deploy to mods\ instead. Escape hatch; not normally needed. Do not leave a copy
in both places.

.PARAMETER Validate
Deploy, then run the game's own mod validator over the staging area. The
validator grades PC and console separately and is what publishing runs anyway,
so it is the cheapest way to find packaging problems before uploading. Close
the game first.

.EXAMPLE
.\deploy.ps1
.EXAMPLE
.\deploy.ps1 -Validate
#>
[CmdletBinding()]
param(
	[switch]$Mods,
	[switch]$Validate
)

$ErrorActionPreference = "Stop"

$ModId = "multi_layer_stations_1"
$Source = Join-Path $PSScriptRoot "mod\$ModId"

if (-not (Test-Path $Source)) {
	throw "Mod source not found: $Source"
}

# Validating means publishing, which only reads the staging area.
if ($Validate) { $Mods = $false }
$Folder = if ($Mods) { "mods" } else { "staging_area" }

# Transport Fever 3 is Steam appid 3493540. The per-account userdata folder
# holds both destinations side by side.
$Local = Get-ChildItem "C:\Program Files (x86)\Steam\userdata\*\3493540\local" -Directory -ErrorAction SilentlyContinue |
	Select-Object -First 1

if (-not $Local) {
	throw "Could not find the TF3 userdata folder. Launch the game once, then retry."
}

$TargetRoot = Join-Path $Local.FullName $Folder
if (-not (Test-Path $TargetRoot)) {
	New-Item -ItemType Directory -Force $TargetRoot | Out-Null
}

$Target = Join-Path $TargetRoot $ModId

# _metadata\mod.io_fileid.txt is written by the in-game publisher and read back
# by the game's LocalModHubBackend: it is what says "this folder IS mod.io mod
# N", so the next publish updates that mod instead of creating a second one.
# This deploy wipes the target, so the file has to come from the source tree -
# it is committed for exactly that reason. If a publish has happened since the
# last deploy and the id exists only in the target, rescue it rather than
# destroying the link.
$FileIdRel = "_metadata\mod.io_fileid.txt"
$SourceFileId = Join-Path $Source $FileIdRel
$TargetFileId = Join-Path $Target $FileIdRel
$Rescued = $null
if ((Test-Path $TargetFileId) -and (-not (Test-Path $SourceFileId))) {
	$Rescued = [System.IO.File]::ReadAllBytes($TargetFileId)
}

if (Test-Path $Target) { Remove-Item -Recurse -Force $Target -Confirm:$false }
Copy-Item -Recurse $Source $Target

if ($null -ne $Rescued) {
	New-Item -ItemType Directory -Force (Split-Path $TargetFileId) | Out-Null
	[System.IO.File]::WriteAllBytes($TargetFileId, $Rescued)
	Write-Warning "mod.io id was only in the deploy target - restored it. Copy $FileIdRel into mod\$ModId\ and commit it."
}

Write-Host "Deployed to $Target"
if (Test-Path $TargetFileId) {
	Write-Host "  mod.io id: $((Get-Content $TargetFileId -Raw).Trim()) - publishing will update that mod"
}
else {
	Write-Host "  not published yet - the first publish will create a new mod.io entry"
}

# One mod id must live in exactly one place, or the game picks for us.
$Other = Join-Path (Join-Path $Local.FullName $(if ($Mods) { "staging_area" } else { "mods" })) $ModId
if (Test-Path $Other) {
	Write-Warning "A second copy of $ModId exists at $Other - the game will pick one of them. Delete it."
}

$Log = Join-Path $Local.FullName "crash_dump\stdout.txt"
Write-Host "Log: $Log"
Write-Host "  the mod logs with the prefix [multi-layer]"
Write-Host "  note: stdout.txt is overwritten each session - copy it aside if a run matters"

if ($Validate) {
	# Syntax, from the usage strings inside TransportFever3.exe:
	#   --validate <source>,<modid> [report.json] [--and-cook <cook-output-path>]
	# Both trailing parts are optional and both need their argument. Passing
	# --and-cook with no path just logs "argument provided without cook output
	# path, ignoring" and skips cooking, which is the console-asset half of the
	# check. The report path is what turns this from "read the log" into
	# something machine-readable.
	$Exe = "C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3\TransportFever3.exe"
	if (-not (Test-Path $Exe)) {
		Write-Warning "Game executable not found, skipping validation: $Exe"
		return
	}

	$Report = Join-Path $env:TEMP "tf3-validate-$ModId.json"
	$CookDir = Join-Path $env:TEMP "tf3-cook-$ModId"
	# "Cook output folder already exists, please remove manually" - so do that.
	if (Test-Path $Report) { Remove-Item -Force $Report -Confirm:$false }
	if (Test-Path $CookDir) { Remove-Item -Recurse -Force $CookDir -Confirm:$false }

	Write-Host "`nValidating (close the game first - this runs the game exe)..."
	# The exe is a GUI subsystem binary, so it detaches from the console and
	# $LASTEXITCODE is never set. Start-Process -Wait is the only way to get
	# both the exit code and a guarantee the report has been written.
	$proc = Start-Process -FilePath $Exe -Wait -PassThru -ArgumentList @(
		"--validate", "StagingArea,$ModId", $Report, "--and-cook", $CookDir)

	# The exit code is not a verdict: the process we started hands off to a
	# second one and returns before the work is done (53 observed on a run that
	# passed cleanly). Wait for the game to be gone and the report to land, and
	# judge by the report.
	$deadline = (Get-Date).AddMinutes(5)
	while ((Get-Date) -lt $deadline) {
		$running = Get-Process TransportFever3 -ErrorAction SilentlyContinue
		if ((-not $running) -and (Test-Path $Report)) { break }
		Start-Sleep -Milliseconds 500
	}
	Write-Host "Validator exit code: $($proc.ExitCode) (not a verdict - see the report)"

	if (Test-Path $Report) {
		$r = Get-Content $Report -Raw | ConvertFrom-Json
		Write-Host ""
		Write-Host "PC      : level=$($r.levelPc) critical=$($r.criticalPc)"
		Write-Host "Console : level=$($r.levelConsole) critical=$($r.criticalConsole)"
		if ($null -eq $r.messages) {
			Write-Host "Messages: none"
		}
		else {
			# Each message is an object; "$_" would render it as
			# @{consoleOnly=False; context=...} and bury the actual text.
			Write-Host "Messages:"
			$r.messages | ForEach-Object {
				Write-Host "  [$($_.level)] $($_.context) $($_.file)"
				$_.message -split "`n" | ForEach-Object { Write-Host "    $_" }
			}
		}

		# critical is NOT the verdict. A Lua parse failure comes back as
		# level=Error with critical=False, and judging on critical alone prints
		# "Validation passed" directly underneath the error that broke the mod.
		# Grade on the level, which is Info on a clean pass.
		$levels = @($r.levelPc, $r.levelConsole)
		if ($r.criticalPc -or $r.criticalConsole) {
			Write-Warning "Critical issues - fix before publishing. Full report: $Report"
		}
		elseif ($levels -contains "Error") {
			Write-Warning "Validation FAILED (level=Error). Full report: $Report"
		}
		elseif ($levels -contains "Warning") {
			Write-Warning "Validation passed with warnings. Full report: $Report"
		}
		else {
			Write-Host "`nValidation passed."
		}
	}
	else {
		Write-Warning "No report written. Check $Log for 'Validating Modhub mod' and 'Validation'."
		Write-Host "The in-game Mod Manager runs the same validator from the staging"
		Write-Host "area entry and reports per file, if the CLI says nothing useful."
	}
}
