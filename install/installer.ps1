# =============================================================================
#  installer.ps1  -  installe l'interface "style Mac" (lance par INSTALLER.bat, en administrateur)
# =============================================================================
$ErrorActionPreference = 'Stop'
$depot   = Split-Path $PSScriptRoot -Parent
$cible   = Join-Path $env:LOCALAPPDATA 'InterfaceMac'
$sauv    = Join-Path $cible 'sauvegarde'
$docs    = [Environment]::GetFolderPath('MyDocuments')
$skins   = Join-Path $docs 'Rainmeter\Skins\MacWidgets'
$journal = Join-Path $env:TEMP 'InterfaceMac_installation.log'
Start-Transcript -Path $journal -Force | Out-Null

function Etape($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    [OK] $t" -ForegroundColor Green }
function Info($t)  { Write-Host "    $t" }
function Attention($t) { Write-Host "    [!] $t" -ForegroundColor Yellow }
function Redemarrer-Windhawk {
  $s = Get-Service Windhawk -ErrorAction SilentlyContinue; if (-not $s) { return }
  if ($s.Status -ne 'Stopped') { Stop-Service Windhawk -Force -ErrorAction SilentlyContinue; try { $s.WaitForStatus('Stopped', '00:00:20') } catch { } }
  Start-Sleep 3
  for ($i = 0; $i -lt 6; $i++) { try { Start-Service Windhawk -ErrorAction Stop; break } catch { Start-Sleep 3 } }
}

# Versions des modules Windhawk testees avec cette interface (ne pas changer sans tester)
$modules = [ordered]@{
  'windows-11-taskbar-styler'    = '1.11.2'
  'taskbar-dock-animation'       = '1.9.2'
  'taskbar-icon-size'            = '1.3.11'
  'on-screen-indicator-position' = '1.6.1'
}

try {
Write-Host "=============================================================" -ForegroundColor Magenta
Write-Host "        Installation de l'interface 'style Mac' pour Windows 11" -ForegroundColor Magenta
Write-Host "=============================================================" -ForegroundColor Magenta

# ------------------------------------------------------------------ 0. Verifications
Etape "Verifications"
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -lt 22000) { throw "Windows 11 est necessaire (build actuel : $build)." }
Ok "Windows 11 (build $build)"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget est introuvable. Installez 'App Installer' depuis le Microsoft Store puis relancez." }
Ok "winget present"
try { Invoke-WebRequest 'https://mods.windhawk.net' -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null; Ok "Connexion Internet" } catch { throw "Pas d'acces a Internet (mods.windhawk.net)." }
Get-ChildItem $depot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ 1. Copie des fichiers
Etape "Copie des fichiers dans $cible"
New-Item -ItemType Directory -Force $cible, $sauv | Out-Null
Copy-Item (Join-Path $depot 'app\*') $cible -Recurse -Force
Copy-Item (Join-Path $depot 'docs\GUIDE.txt') (Join-Path $cible 'GUIDE.txt') -Force
Copy-Item (Join-Path $depot 'install\desinstaller.ps1') (Join-Path $cible 'desinstaller.ps1') -Force
Ok "Fichiers copies"

# ------------------------------------------------------------------ 2. Sauvegarde des reglages actuels
Etape "Sauvegarde de vos reglages actuels (pour pouvoir tout annuler)"
if (-not (Test-Path (Join-Path $sauv 'fait.txt'))) {
  reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" (Join-Path $sauv 'barre_des_taches.reg') /y | Out-Null
  reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" (Join-Path $sauv 'recherche.reg') /y | Out-Null
  $fondActuel = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
  if ($fondActuel -and (Test-Path $fondActuel)) { Copy-Item $fondActuel (Join-Path $sauv ('fond_origine' + [IO.Path]::GetExtension($fondActuel))) -Force }
  $rmIni = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
  if (Test-Path $rmIni) { Copy-Item $rmIni (Join-Path $sauv 'Rainmeter.ini.origine') -Force }
  Get-Date | Set-Content (Join-Path $sauv 'fait.txt')
  Ok "Sauvegarde faite dans $sauv"
} else { Ok "Sauvegarde deja presente (installation precedente) : conservee" }

# ------------------------------------------------------------------ 3. Logiciels
Etape "Installation de Rainmeter et Windhawk (sources officielles, via winget)"
foreach ($id in 'Rainmeter.Rainmeter', 'RamenSoftware.Windhawk') {
  $deja = winget list --id $id -e --accept-source-agreements 2>$null | Select-String $id
  if ($deja) { Ok "$id deja installe" }
  else {
    Info "Telechargement et installation de $id ..."
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Echec de l'installation de $id (code $LASTEXITCODE)." }
    Ok "$id installe"
  }
}
$rmDir = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Rainmeter' -ErrorAction SilentlyContinue).'(default)'
if (-not $rmDir) { $rmDir = 'C:\Program Files\Rainmeter' }
$rmExe = Join-Path $rmDir 'Rainmeter.exe'
if (-not (Test-Path $rmExe)) { throw "Rainmeter introuvable apres installation." }
for ($i = 0; $i -lt 30 -and -not (Get-Service Windhawk -ErrorAction SilentlyContinue); $i++) { Start-Sleep 1 }
if (-not (Get-Service Windhawk -ErrorAction SilentlyContinue)) { throw "Le service Windhawk n'est pas present." }
Ok "Rainmeter et Windhawk prets"

# ------------------------------------------------------------------ 4. Windhawk : reglages + modules
Etape "Configuration de Windhawk et installation des modules (dock Mac)"
$data   = 'C:\ProgramData\Windhawk'
$whReg  = 'HKLM:\SOFTWARE\Windhawk'
$comp   = 'C:\Program Files\Windhawk\Compiler'
New-Item "$whReg\Settings" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty "$whReg\Settings" SafeMode 0 -Type DWord
Set-ItemProperty "$whReg\Settings" ModTasksDialogDelay 600000 -Type DWord   # pas de fenetre "chargement des mods"
Set-ItemProperty "$whReg\Settings" DontAutoShowToolkit 1 -Type DWord         # pas de boite a outils automatique
# bibliotheques communes aux modules
foreach ($t in @(@('x86_64-w64-mingw32','64'), @('i686-w64-mingw32','32'))) {
  $dst = "$data\Engine\Mods\$($t[1])"; New-Item -ItemType Directory -Force $dst | Out-Null
  foreach ($p in @(@('libc++.dll','libc++.whl'), @('libunwind.dll','libunwind.whl'), @('windhawk-mod-shim.dll','windhawk-mod-shim.dll'))) {
    $srcLib = "$comp\$($t[0])\bin\$($p[0])"; if (Test-Path $srcLib) { Copy-Item $srcLib "$dst\$($p[1])" -Force }
  }
}
New-Item -ItemType Directory -Force "$data\ModsSource" | Out-Null
$telech = Join-Path $env:TEMP 'InterfaceMac_mods'; New-Item -ItemType Directory -Force $telech | Out-Null

$config = Get-Content (Join-Path $cible 'config.json') -Raw | ConvertFrom-Json
$reglages = @{
  'windows-11-taskbar-styler' = [ordered]@{
    'theme' = $config.dock.theme; 'styleConstants[0]' = ''; 'themeResourceVariables[0]' = ''
    'clickThroughTaskbar' = 0; 'xamlDiagnosticsHandling' = 'alert'
    # masquer la recherche, les widgets et la vue des taches du dock
    'controlStyles[0].target' = 'Taskbar.SearchBoxButton'; 'controlStyles[0].styles[0]' = 'Visibility=Collapsed'
    'controlStyles[1].target' = 'Taskbar.AugmentedEntryPointButton#AugmentedEntryPointButton'; 'controlStyles[1].styles[0]' = 'Visibility=Collapsed'
    'controlStyles[2].target' = 'Taskbar.ExperienceToggleButton#LaunchListButton[AutomationProperties.AutomationId=TaskViewButton]'; 'controlStyles[2].styles[0]' = 'Visibility=Collapsed'
    'controlStyles[3].target' = 'SearchUx.SearchUI.SearchBoxButton'; 'controlStyles[3].styles[0]' = 'Visibility=Collapsed'
    'controlStyles[4].target' = 'SearchUx.SearchUI.SearchButtonControl'; 'controlStyles[4].styles[0]' = 'Visibility=Collapsed'
    # wifi/son/batterie et heure : rendus invisibles (ils sont dans la barre du haut).
    # ATTENTION : ne jamais utiliser Visibility=Collapsed sur SystemTray.* -> plantage de l'Explorateur au demarrage.
    'controlStyles[5].target' = 'SystemTray.OmniButton#ControlCenterButton'
    'controlStyles[5].styles[0]' = 'Width=0'; 'controlStyles[5].styles[1]' = 'MinWidth=0'; 'controlStyles[5].styles[2]' = 'MaxWidth=0'; 'controlStyles[5].styles[3]' = 'Opacity=0'
    'controlStyles[6].target' = 'SystemTray.OmniButton#NotificationCenterButton'
    'controlStyles[6].styles[0]' = 'Width=0'; 'controlStyles[6].styles[1]' = 'MinWidth=0'; 'controlStyles[6].styles[2]' = 'MaxWidth=0'; 'controlStyles[6].styles[3]' = 'Opacity=0'
    # pastille d'icones vide (2e ecran) : invisible
    'controlStyles[7].target' = 'SystemTray.SystemTrayFrame'
    'controlStyles[7].styles[0]' = 'ActualWidth=>largeurTray'; 'controlStyles[7].styles[1]' = 'Opacity={{largeurTray > 50 ? 1 : 0}}'
  }
  'taskbar-dock-animation' = [ordered]@{ AnimationType=0; MaxScale=[int]$config.dock.grossissementLoupe; EffectRadius=200; SpacingFactor=80; BounceDelay=500; FocusDuration=150; MirrorForTopTaskbar=0; DisableVerticalBounce=1; TaskbarLabelsMode=0; ExcludeSystemButtonsMode=0; LerpSpeed=45; DisableBounce=1 }
  'taskbar-icon-size' = [ordered]@{ TaskbarHeight=[int]$config.dock.hauteur; IconSize=[int]$config.dock.tailleIcones; TaskbarButtonWidth=([int]$config.dock.tailleIcones + 24); IconSizeSmall=16; TaskbarButtonWidthSmall=32 }
  'on-screen-indicator-position' = [ordered]@{ 'position'='windowsDefault'; 'perIndicator.volume'='hidden'; 'perIndicator.brightness'='hidden'; 'offsetX'=0; 'offsetY'=0; 'skipHideAnimation'=0; 'durationSeconds'=0; 'displayProfiles[0].enabled'=0; 'displayProfiles[0].monitorCount'=0; 'displayProfiles[0].indicator'='all'; 'displayProfiles[0].position'='same'; 'displayProfiles[0].horizontal'='inherit'; 'displayProfiles[0].vertical'='inherit'; 'displayProfiles[0].x'=0; 'displayProfiles[0].y'=0 }
}
foreach ($n in 'keyboardBrightness','airplaneMode','camera','microphone','text','virtualDesktop') { $reglages['on-screen-indicator-position']["perIndicator.$n"] = 'same' }
foreach ($n in 'volume','brightness','keyboardBrightness','airplaneMode','camera','microphone','text','virtualDesktop') {
  $reglages['on-screen-indicator-position']["indicatorOffsets.$n.horizontal"] = 'inherit'; $reglages['on-screen-indicator-position']["indicatorOffsets.$n.vertical"] = 'inherit'
  $reglages['on-screen-indicator-position']["indicatorOffsets.$n.x"] = 0; $reglages['on-screen-indicator-position']["indicatorOffsets.$n.y"] = 0
}

foreach ($id in $modules.Keys) {
  $ver = $modules[$id]
  $dllTmp = Join-Path $telech "$id`_$ver.dll"; $srcTmp = Join-Path $telech "$id.wh.cpp"
  Invoke-WebRequest "https://mods.windhawk.net/mods/$id/${ver}_64.dll" -OutFile $dllTmp -UseBasicParsing
  Invoke-WebRequest "https://mods.windhawk.net/mods/$id/$ver.wh.cpp" -OutFile $srcTmp -UseBasicParsing
  $include = ((Get-Content $srcTmp | Select-String '^// @include\s+(\S+)') | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join '|'
  $k = "$whReg\Engine\Mods\$id"
  # supprimer une ancienne version eventuelle
  $ancienne = (Get-ItemProperty $k -ErrorAction SilentlyContinue).LibraryFileName
  if ($ancienne) { Remove-Item "$data\Engine\Mods\64\$ancienne" -Force -ErrorAction SilentlyContinue }
  $dll = "$($id)_$($ver)_$(Get-Random -Minimum 100000 -Maximum 999999).dll"
  Copy-Item $dllTmp "$data\Engine\Mods\64\$dll" -Force
  Copy-Item $srcTmp "$data\ModsSource\$id.wh.cpp" -Force
  Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue
  New-Item "$k\Settings" -Force | Out-Null
  Set-ItemProperty $k LibraryFileName $dll -Type String
  Set-ItemProperty $k Disabled 0 -Type DWord
  Set-ItemProperty $k Include $include -Type String
  Set-ItemProperty $k Exclude '' -Type String
  Set-ItemProperty $k Architecture 'x86-64' -Type String
  Set-ItemProperty $k Version $ver -Type String
  foreach ($e in $reglages[$id].GetEnumerator()) {
    if ($e.Value -is [int]) { New-ItemProperty "$k\Settings" -Name $e.Key -Value $e.Value -PropertyType DWord -Force | Out-Null }
    else { New-ItemProperty "$k\Settings" -Name $e.Key -Value ([string]$e.Value) -PropertyType String -Force | Out-Null }
  }
  Set-ItemProperty $k SettingsChangeTime ([int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -band 0x7FFFFFFF)) -Type DWord
  Ok "Module $id $ver"
}
Remove-Item $telech -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ 5. Reglages Windows (utilisateur)
Etape "Reglages de Windows"
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-ItemProperty $adv TaskbarAl 1 -Type DWord               # dock centre
Set-ItemProperty $adv ShowTaskViewButton 0 -Type DWord
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' SearchboxTaskbarMode 0 -Type DWord
New-Item 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $rmExe -Value '~ HIGHDPIAWARE'
Ok "Barre des taches centree, recherche et vue des taches masquees, Rainmeter en pleine resolution"

# ------------------------------------------------------------------ 6. Fond d'ecran
Etape "Fond d'ecran"
try {
  Invoke-WebRequest $config.fondEcran.url -OutFile (Join-Path $cible 'fond_ecran.jpg') -UseBasicParsing
  & (Join-Path $cible 'fond_ecran.ps1') -Image (Join-Path $cible 'fond_ecran.jpg')
  Ok "Fond d'ecran applique ($($config.fondEcran.credit))"
} catch { Attention "Fond d'ecran non telecharge : $($_.Exception.Message)" }

# ------------------------------------------------------------------ 7. Rainmeter : barre + pastilles
Etape "Barre des menus et pastilles (Rainmeter)"
Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
$res = & (Join-Path $cible 'generer_skins.ps1') -App $cible -Skins $skins
Ok "Genere pour l'ecran : echelle $($res.Echelle), largeur $($res.LargeurPx) px, batterie : $($res.Batterie)"
$rmIni = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
New-Item -ItemType Directory -Force (Split-Path $rmIni) | Out-Null
$ini = @"
[Rainmeter]
Logging=0
SkinPath=$docs\Rainmeter\Skins\

[MacWidgets\BarreMenus]
Active=1
WindowX=0
WindowY=0
ClickThrough=0
Draggable=0
SnapEdges=0
KeepOnScreen=0
AlwaysOnTop=0

[MacWidgets\Volume]
Active=1
WindowX=$($res.PastilleX)
WindowY=$($res.PastilleY)
ClickThrough=1
Draggable=0
SnapEdges=0
KeepOnScreen=0
AlwaysOnTop=2

[MacWidgets\Luminosite]
Active=1
WindowX=$($res.PastilleX)
WindowY=$($res.PastilleY)
ClickThrough=1
Draggable=0
SnapEdges=0
KeepOnScreen=0
AlwaysOnTop=2

[MacWidgets\PanneauBatterie]
Active=1
Draggable=0
SnapEdges=0
KeepOnScreen=0
AlwaysOnTop=2
"@
[IO.File]::WriteAllText($rmIni, $ini, [Text.Encoding]::Unicode)
# Rainmeter ne doit pas se lancer seul (c'est la tache de demarrage qui le lance correctement)
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Rainmeter -ErrorAction SilentlyContinue
$startup = [Environment]::GetFolderPath('Startup'); Get-ChildItem $startup -Filter 'Rainmeter*.lnk' -ErrorAction SilentlyContinue | Remove-Item -Force
Ok "Rainmeter configure"

# ------------------------------------------------------------------ 8. Demarrage automatique
Etape "Demarrage automatique (invisible)"
$utilisateur = "$env:USERDOMAIN\$env:USERNAME"
$act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$cible\lancer_invisible.vbs`" `"$cible\demarrer_interface.ps1`""
$trg = New-ScheduledTaskTrigger -AtLogOn -User $utilisateur
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable
$pr  = New-ScheduledTaskPrincipal -UserId $utilisateur -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'Interface Mac - demarrage' -Action $act -Trigger $trg -Settings $set -Principal $pr -Description "Lance la barre des menus et le dock facon Mac" -Force | Out-Null
Ok "Tache 'Interface Mac - demarrage' creee"

# ------------------------------------------------------------------ 9. Lancement + verification
Etape "Lancement de l'interface"
$debut = Get-Date
Redemarrer-Windhawk
Start-Sleep 3
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
Start-Sleep 5
Start-ScheduledTask -TaskName 'Interface Mac - demarrage'
Start-Sleep 20
$plantages = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$debut} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'Explorer.EXE' }).Count
$safe = (Get-ItemProperty "$whReg\Settings").SafeMode
if ($plantages -gt 0 -or $safe -eq 1) {
  Attention "L'Explorateur a plante ($plantages fois) avec les reglages du dock. Retrait des reglages de la zone horloge/wifi et nouvel essai..."
  $k = "$whReg\Engine\Mods\windows-11-taskbar-styler\Settings"
  foreach ($i in 5..7) { Get-Item $k | Select-Object -ExpandProperty Property | Where-Object { $_ -like "controlStyles[$i]*" } | ForEach-Object { Remove-ItemProperty $k -Name $_ } }
  Set-ItemProperty "$whReg\Settings" SafeMode 0 -Type DWord
  Redemarrer-Windhawk; Start-Sleep 3
  Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3
  if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
} else { Ok "Aucun plantage, dock actif" }

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Green
Write-Host "  Installation terminee !" -ForegroundColor Green
Write-Host "  - Barre des menus en haut, dock facon Mac en bas" -ForegroundColor Green
Write-Host "  - Guide : menu 'Aide' de la barre, ou $cible\GUIDE.txt" -ForegroundColor Green
Write-Host "  - Pour tout annuler : DESINSTALLER.bat" -ForegroundColor Green
Write-Host "  Conseil : fermez puis rouvrez votre session une fois." -ForegroundColor Green
Write-Host "=============================================================" -ForegroundColor Green
}
catch {
  Write-Host ""
  Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Rien n'est casse : lancez DESINSTALLER.bat pour annuler ce qui a deja ete fait." -ForegroundColor Red
  Write-Host "Journal detaille : $journal" -ForegroundColor Red
}
finally { Stop-Transcript | Out-Null }
