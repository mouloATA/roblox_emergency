# Vérifie ERS sans ouvrir Roblox :
#   1. compilation Luau de tous les fichiers (syntaxe) ;
#   2. tests unitaires (maths, catalogues, budget, permissions) ;
#   3. intégration (monde, alertes, engagement, résolution, sauvegarde) ;
#   4. multijoueur (rôles, périmètres, refus côté serveur) ;
#   5. interface headless (construction, snapshots, actions).
#
# Usage :  powershell -ExecutionPolicy Bypass -File tools\check.ps1
#
# Les sources sont copiées dans un dossier temporaire ASCII : luau.exe ne gère
# pas les accents dans les chemins. Un manifeste reproduit l'arbre Rojo pour que
# les modules puissent s'appeler par chemin absolu, comme dans Studio.
#
# Encodage : tous les fichiers réécrits le sont en UTF-8 sans BOM (Luau refuse
# le BOM en tête de fichier).

param(
	[string]$LuauDir = "$env:LOCALAPPDATA\Temp\opencode\luau"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8([string]$Path, [string]$Text) {
	[System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Read-Utf8([string]$Path) {
	return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# Le CLI Luau isole les globales de chaque module. Cet en-tête, injecté dans
# chaque module testé, expose `game`, les types Roblox et un `require` qui
# résout les Instances virtuelles. Le code de production reste inchangé.
$envHeader = @'
local __env = require("./__env")
local game = __env.game
local workspace = __env.workspace
local Instance = __env.Instance
local UDim = __env.UDim
local UDim2 = __env.UDim2
local Vector2 = __env.Vector2
local Vector3 = __env.Vector3
local Color3 = __env.Color3
local CFrame = __env.CFrame
local TweenInfo = __env.TweenInfo
local Rect = __env.Rect
local Enum = __env.Enum
local task = __env.task
local typeof = __env.typeof
local require = __env.require
'@

$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $LuauDir "luau-compile.exe"
$runner = Join-Path $LuauDir "luau.exe"

if (-not (Test-Path $compiler)) {
	Write-Host "luau-compile.exe introuvable dans $LuauDir" -ForegroundColor Red
	Write-Host "Téléchargez luau-windows.zip : https://github.com/luau-lang/luau/releases" -ForegroundColor Yellow
	exit 1
}

$tempRoot = (Get-Item -LiteralPath $env:TEMP).FullName
$work = Join-Path $tempRoot ("ers-check-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

Copy-Item (Join-Path $root "src") $work -Recurse
Copy-Item (Join-Path $root "tests") $work -Recurse

# ── 1. Compilation ────────────────────────────────────────────
$files = Get-ChildItem -Path $work -Recurse -Filter *.luau
$syntaxErrors = 0
foreach ($file in $files) {
	$output = & $compiler --only-parse $file.FullName 2>&1
	if ($LASTEXITCODE -ne 0) {
		$syntaxErrors++
		$relative = $file.FullName.Substring($work.Length + 1)
		Write-Host "ERREUR  $relative" -ForegroundColor Red
		$output | ForEach-Object { Write-Host "        $_" }
	}
}
$color = if ($syntaxErrors -eq 0) { "Green" } else { "Red" }
Write-Host "Compilation : $($files.Count) fichier(s), $syntaxErrors erreur(s)" -ForegroundColor $color
if ($syntaxErrors -gt 0) {
	Write-Host "ECHEC (syntaxe)" -ForegroundColor Red
	exit 1
}

# ── 2. Arbre virtuel ──────────────────────────────────────────
$flat = Join-Path $work "flat"
New-Item -ItemType Directory -Path $flat | Out-Null
$srcRoot = Join-Path $work "src"

# Seuls les modules sont mappés : les scripts .server/.client ne sont jamais
# requis par un autre module, ils sont seulement compilés.
$modules = Get-ChildItem -Path $srcRoot -Recurse -Filter *.luau |
	Where-Object { $_.Name -notlike "*.server.luau" -and $_.Name -notlike "*.client.luau" }

$manifestLines = @("return {")
$moduleCount = 0
foreach ($file in $modules) {
	$relative = $file.FullName.Substring($srcRoot.Length + 1) -replace '\\', '/'
	$segments = @($relative -split '/')
	$folders = @()
	if ($segments.Count -gt 1) {
		$folders = @($segments[0..($segments.Count - 2)])
	}
	if ($file.Name -ne "init.luau") {
		$folders = @($folders) + @($file.BaseName)
	}
	if ($folders.Count -eq 0) { continue }

	if ($folders[0] -eq "ServerScriptService") {
		$tail = if ($folders.Count -gt 1) { @($folders[1..($folders.Count - 1)]) } else { @() }
		$virtual = @("ServerScriptService", "ERS") + $tail
	} elseif ($folders[0] -eq "StarterPlayer") {
		# StarterPlayer/StarterPlayerScripts/<...> devient, à l'exécution,
		# Players.LocalPlayer.PlayerScripts.ERSClient/<...>
		$tail = if ($folders.Count -gt 2) { @($folders[2..($folders.Count - 1)]) } else { @() }
		$virtual = @("Players", "LocalPlayer", "PlayerScripts", "ERSClient") + $tail
	} else {
		$virtual = $folders
	}

	$flatName = ($relative -replace '\.luau$', '') -replace '[/\\]', '_'
	Write-Utf8 (Join-Path $flat "$flatName.luau") ($envHeader + "`n" + (Read-Utf8 $file.FullName))
	$manifestLines += "`t{ path = ""$($virtual -join '.')"", file = ""$flatName"" },"
	$moduleCount++
}
$manifestLines += "}"
Write-Utf8 (Join-Path $flat "manifest.luau") ($manifestLines -join "`n")

Copy-Item (Join-Path $work "tests/__env.luau") (Join-Path $flat "__env.luau")
Copy-Item (Join-Path $work "tests/__prelude.luau") (Join-Path $flat "__prelude.luau")
Copy-Item (Join-Path $work "tests/__stubs.luau") (Join-Path $flat "__stubs.luau")

Write-Host "Modules mappés : $moduleCount" -ForegroundColor DarkGray

# ── 3. Suites ─────────────────────────────────────────────────
$suites = @(
	@{ File = "tests/Unit/spec.luau"; Name = "Unit_spec" },
	@{ File = "tests/Integration/sim.luau"; Name = "Integration_sim" },
	@{ File = "tests/Multiplayer/permissions.luau"; Name = "Multiplayer_permissions" },
	@{ File = "tests/UI/ui.luau"; Name = "UI_ui" }
)

$failed = $false
foreach ($suite in $suites) {
	$source = Join-Path $work $suite.File
	if (-not (Test-Path $source)) {
		Write-Host "Suite absente : $($suite.File)" -ForegroundColor Red
		$failed = $true
		continue
	}
	$content = Read-Utf8 $source
	$runnerName = "$($suite.Name).luau"
	Write-Utf8 (Join-Path $flat $runnerName) ($envHeader + "`nlocal __env = require(`"./__prelude`")`n" + $content)
	Write-Host ""
	Write-Host "== $($suite.File) ==" -ForegroundColor Cyan
	& $runner (Join-Path $flat $runnerName)
	if ($LASTEXITCODE -ne 0) { $failed = $true }
}

Write-Host ""
$resolvedWork = (Resolve-Path -LiteralPath $work).Path
if ((Split-Path -Parent $resolvedWork) -ne $tempRoot -or (Split-Path -Leaf $resolvedWork) -notmatch '^ers-check-[0-9a-f]{32}$') {
	throw "Dossier temporaire de test inattendu."
}
Remove-Item -LiteralPath $resolvedWork -Recurse -Force

if ($failed) {
	Write-Host "ECHEC" -ForegroundColor Red
	exit 1
}
Write-Host "OK" -ForegroundColor Green
