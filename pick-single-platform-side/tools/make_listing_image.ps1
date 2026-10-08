<#
.SYNOPSIS
Renders the mod.io listing image (1920x1080).

.DESCRIPTION
Two modes, picked automatically:

  composite  a title block beside a real screenshot, drawn at its native size
             on a 1920x1080 canvas. Used when -Screenshot points at a file.
             Native size on purpose: the screenshots are smaller than 1920x1080
             and upscaling them to fill the canvas only softens them.
  schematic  a flat placeholder - the entrance block with the platform on one
             side and then the other. Used when there is no screenshot yet.

.PARAMETER Screenshot
Source screenshot. Defaults to _metadata\1.jpg, the in-game shot of the
placement dialog.

.PARAMETER Schematic
Force the placeholder even when a screenshot exists.

.PARAMETER OutFile
Where to write the PNG.
#>
[CmdletBinding()]
param(
	[string]$Screenshot = "$PSScriptRoot\..\mod\pick_single_platform_side_1\_metadata\1.jpg",
	[switch]$Schematic,
	[string]$OutFile = "$PSScriptRoot\..\mod\pick_single_platform_side_1\_metadata\0.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$W = 1920
$H = 1080

$bg       = [System.Drawing.Color]::FromArgb(30, 36, 48)
$street   = [System.Drawing.Color]::FromArgb(58, 66, 82)
$entrance = [System.Drawing.Color]::FromArgb(110, 122, 145)
$platform = [System.Drawing.Color]::FromArgb(224, 163, 62)
$ink      = [System.Drawing.Color]::FromArgb(242, 244, 248)
$muted    = [System.Drawing.Color]::FromArgb(154, 166, 186)

$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.Clear($bg)

$inkBrush   = New-Object System.Drawing.SolidBrush($ink)
$mutedBrush = New-Object System.Drawing.SolidBrush($muted)
$streetB    = New-Object System.Drawing.SolidBrush($street)
$entranceB  = New-Object System.Drawing.SolidBrush($entrance)
$platformB  = New-Object System.Drawing.SolidBrush($platform)
$accentB    = New-Object System.Drawing.SolidBrush($platform)

$center = New-Object System.Drawing.StringFormat
$center.Alignment = [System.Drawing.StringAlignment]::Center

$left = New-Object System.Drawing.StringFormat
$left.Alignment = [System.Drawing.StringAlignment]::Near

$useShot = (-not $Schematic) -and (Test-Path $Screenshot)

if ($useShot) {
	$shot = [System.Drawing.Image]::FromFile((Resolve-Path $Screenshot))
	$sx = $W - 90 - $shot.Width
	$sy = [int](($H - $shot.Height) / 2)

	# A hairline frame so the screenshot does not bleed into the background.
	$framePen = New-Object System.Drawing.Pen($street, 2)
	$g.DrawImage($shot, $sx, $sy, $shot.Width, $shot.Height)
	$g.DrawRectangle($framePen, $sx, $sy, $shot.Width, $shot.Height)

	$tx = 110
	$tw = $sx - $tx - 60

	$title = "Pick Single Platform Side"
	$pitch = "The single platform is not always on the side you want it. Now you can choose."
	$bullets = @(
		"Bus stations and cargo truck stations",
		"Only shows up for a one-platform station",
		"No new models - add or remove it any time"
	)

	# Shrink the title until it fits on one line; wrapping it collides with the
	# line underneath, and the text column is narrow because the screenshot is
	# drawn at native size.
	$titleFont = $null
	for ($pt = 52; $pt -ge 30; $pt = $pt - 2) {
		$f = New-Object System.Drawing.Font("Segoe UI", $pt, [System.Drawing.FontStyle]::Bold)
		if ($g.MeasureString($title, $f).Width -le $tw) { $titleFont = $f; break }
		$f.Dispose()
	}
	if ($null -eq $titleFont) {
		$titleFont = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Bold)
	}

	$subFont = New-Object System.Drawing.Font("Segoe UI", 25, [System.Drawing.FontStyle]::Regular)
	$bulletF = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular)

	$titleH = [int]$g.MeasureString($title, $titleFont, $tw).Height
	$pitchH = [int]$g.MeasureString($pitch, $subFont, $tw).Height
	$lineH = 58
	$blockH = $titleH + 18 + $pitchH + 56 + ($bullets.Count * $lineH)
	$y = [int](($H - $blockH) / 2)

	$g.DrawString($title, $titleFont, $inkBrush,
		(New-Object System.Drawing.RectangleF($tx, $y, $tw, ($titleH + 10))), $left)
	$y = $y + $titleH + 18

	$g.DrawString($pitch, $subFont, $mutedBrush,
		(New-Object System.Drawing.RectangleF($tx, $y, $tw, ($pitchH + 10))), $left)
	$y = $y + $pitchH + 56

	foreach ($b in $bullets) {
		$g.FillRectangle($accentB, $tx, ($y + 13), 14, 14)
		$g.DrawString($b, $bulletF, $mutedBrush,
			(New-Object System.Drawing.RectangleF(($tx + 36), $y, ($tw - 36), $lineH)), $left)
		$y = $y + $lineH
	}

	$framePen.Dispose()
	$shot.Dispose()
}
else {
	$titleFont   = New-Object System.Drawing.Font("Segoe UI", 58, [System.Drawing.FontStyle]::Bold)
	$subFont     = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Regular)
	$captionFont = New-Object System.Drawing.Font("Segoe UI", 32, [System.Drawing.FontStyle]::Bold)

	$g.DrawString("Pick Single Platform Side", $titleFont, $inkBrush,
		(New-Object System.Drawing.RectangleF(0, 110, $W, 100)), $center)
	$g.DrawString("Put a one-platform bus or truck station's platform on either side of its entrance",
		$subFont, $mutedBrush,
		(New-Object System.Drawing.RectangleF(0, 215, $W, 60)), $center)

	$panelY = 440
	$blockH = 220
	$entW = 130
	$platW = 100
	$gap = 26

	function Draw-Panel {
		param([int]$CenterX, [string]$Caption, [int]$Direction)

		$streetRect = New-Object System.Drawing.Rectangle(
			($CenterX - 430), ($panelY + $blockH + 40), 860, 56)
		$g.FillRectangle($streetB, $streetRect)

		$entRect = New-Object System.Drawing.Rectangle(
			($CenterX - [int]($entW / 2)), $panelY, $entW, $blockH)
		$g.FillRectangle($entranceB, $entRect)

		$platX = $CenterX + $Direction * ([int]($entW / 2) + $gap)
		if ($Direction -lt 0) { $platX = $platX - $platW }
		$platRect = New-Object System.Drawing.Rectangle($platX, $panelY, $platW, $blockH)
		$g.FillRectangle($platformB, $platRect)

		$g.DrawString($Caption, $captionFont, $inkBrush,
			(New-Object System.Drawing.RectangleF(($CenterX - 430), ($panelY + $blockH + 140), 860, 60)),
			$center)
	}

	Draw-Panel -CenterX 490 -Caption "Standard" -Direction 1
	Draw-Panel -CenterX 1430 -Caption "Other side" -Direction -1

	$g.DrawString("placeholder - replace with a screenshot before publishing",
		$subFont, $mutedBrush,
		(New-Object System.Drawing.RectangleF(0, ($H - 110), $W, 60)), $center)
}

$target = [System.IO.Path]::GetFullPath($OutFile)
$dir = [System.IO.Path]::GetDirectoryName($target)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$bmp.Dispose()

if ($useShot) { Write-Host "Wrote $target (composite over $Screenshot)" }
else { Write-Host "Wrote $target (schematic placeholder)" }
