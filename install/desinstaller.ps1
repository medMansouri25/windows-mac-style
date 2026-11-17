# =============================================================================
#  desinstaller.ps1  -  retire l'interface "style Mac" et remet Windows comme avant
#  (lance par DESINSTALLER.bat, en administrateur)
# =============================================================================
$ErrorActionPreference = 'Continue'
$cible = Join-Path $env:LOCALAPPDATA 'InterfaceMac'
$sauv  = Join-Path $cible 'sauvegarde'
$docs  = [Environment]::GetFolderPath('MyDocuments')
$skins = Join-Path $docs 'Rainmeter\Skins\MacWidgets'
$whReg = 'HKLM:\SOFTWARE\Windhawk'
$modules = 'windows-11-taskbar-styler','taskbar-dock-animation','taskbar-icon-size','on-screen-indicator-position'
function Etape($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    [OK] $t" -ForegroundColor Green }

Write-Host "=============================================================" -ForegroundColor Magenta
Write-Host "        Desinstallation de l'interface 'style Mac'" -ForegroundColor Magenta
Write-Host "=============================================================" -ForegroundColor Magenta

Etape "Arret de l'interface"
# 1. d'abord le "moteur" (sinon il relancerait Rainmeter), puis Rainmeter
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*barre_reservee.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName 'Interface Mac - demarrage' -Confirm:$false -ErrorAction SilentlyContinue
# remettre l'ecran comme avant si le mode economie etait actif
if (Test-Path (Join-Path $cible 'economie_ecran.json')) { & (Join-Path $cible 'economie.ps1') -Mode Desactiver }
Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force
Ok "Interface arretee, demarrage automatique supprime"

Etape "Retrait des modules Windhawk (dock)"
foreach ($id in $modules) {
  $k = "$whReg\Engine\Mods\$id"
  $dll = (Get-ItemProperty $k -ErrorAction SilentlyContinue).LibraryFileName
  Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue
  if ($dll) { Remove-Item "C:\ProgramData\Windhawk\Engine\Mods\64\$dll" -Force -ErrorAction SilentlyContinue }
  Remove-Item "C:\ProgramData\Windhawk\ModsSource\$id.wh.cpp" -Force -ErrorAction SilentlyContinue
}
Ok "Modules retires"

Etape "Restauration des reglages Windows"
foreach ($f in 'barre_des_taches.reg','recherche.reg') { $p = Join-Path $sauv $f; if (Test-Path $p) { reg import $p 2>$null | Out-Null } }
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name 'C:\Program Files\Rainmeter\Rainmeter.exe' -ErrorAction SilentlyContinue
$fond = Get-ChildItem $sauv -Filter 'fond_origine.*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($fond) {
  $copie = Join-Path $env:LOCALAPPDATA ('fond_origine' + $fond.Extension); Copy-Item $fond.FullName $copie -Force
  & (Join-Path $cible 'fond_ecran.ps1') -Image $copie
}
$rmIni = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
$orig = Join-Path $sauv 'Rainmeter.ini.origine'
if (Test-Path $orig) { Copy-Item $orig $rmIni -Force } else { Remove-Item $rmIni -Force -ErrorAction SilentlyContinue }
Ok "Barre des taches, recherche et fond d'ecran remis comme avant"

Etape "Logiciels"
$rep = Read-Host "    Desinstaller aussi Rainmeter et Windhawk ? (O/N)"
if ($rep -match '^[oOyY]') {
  winget uninstall --id Rainmeter.Rainmeter -e --silent --accept-source-agreements | Out-Null
  winget uninstall --id RamenSoftware.Windhawk -e --silent --accept-source-agreements | Out-Null
  Ok "Rainmeter et Windhawk desinstalles"
} else { Ok "Rainmeter et Windhawk conserves" }

Etape "Nettoyage des fichiers"
Remove-Item $skins -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem $cible -Exclude 'sauvegarde' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Ok "Fichiers de l'interface supprimes (la sauvegarde reste dans $sauv)"

Etape "Redemarrage de l'Explorateur"
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

Write-Host ""
Write-Host "  Desinstallation terminee. Windows est revenu a son apparence d'origine." -ForegroundColor Green
