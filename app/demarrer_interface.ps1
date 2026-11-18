# =============================================================================
#  demarrer_interface.ps1  -  lance l'interface a l'ouverture de session
#  (tache planifiee "Interface Mac - demarrage", via lancer_invisible.vbs : aucune fenetre)
# =============================================================================
$dossier = $PSScriptRoot
$journal = Join-Path $dossier 'demarrage.log'
function Note($t) { Add-Content $journal ("{0:dd/MM HH:mm:ss}  {1}" -f (Get-Date), $t) }
if ((Test-Path $journal) -and (Get-Item $journal).Length -gt 50KB) { Remove-Item $journal }
Note "Ouverture de session"

$rmDir = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Rainmeter' -ErrorAction SilentlyContinue).'(default)'
if (-not $rmDir) { $rmDir = 'C:\Program Files\Rainmeter' }
$rm = Join-Path $rmDir 'Rainmeter.exe'

# 1) Attendre le bureau
for ($i = 0; $i -lt 120 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }

# 2) En premier : reserver la place de la barre + Rainmeter en pleine resolution
if (-not (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*barre_reservee.ps1*' })) {
  Start-Process wscript.exe -ArgumentList "`"$dossier\lancer_invisible.vbs`"","`"$dossier\barre_reservee.ps1`""
  Note "Reservation de la barre lancee"
}
if (-not (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
  # "~ HIGHDPIAWARE" (avec le ~) : pleine resolution ET enregistrement des reglages
  $env:__COMPAT_LAYER = '~ HIGHDPIAWARE'
  Start-Process $rm
  Remove-Item Env:__COMPAT_LAYER -ErrorAction SilentlyContinue
  Note "Rainmeter lance"
}

# 3) Forcer le bon affichage (pas les widgets d'exemple de Rainmeter)
for ($i = 0; $i -lt 20 -and -not (Get-Process Rainmeter -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 300 }
Start-Sleep -Milliseconds 1500
foreach ($c in 'illustro\Clock','illustro\Disk','illustro\System','illustro\Welcome') { & $rm '!DeactivateConfig' $c }
& $rm '!ActivateConfig' 'MacWidgets\BarreMenus' 'BarreMenus.ini'
& $rm '!ActivateConfig' 'MacWidgets\Volume' 'Volume.ini'
& $rm '!ActivateConfig' 'MacWidgets\Luminosite' 'Luminosite.ini'
if (Test-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\MacWidgets\PanneauBatterie')) { & $rm '!ActivateConfig' 'MacWidgets\PanneauBatterie' 'PanneauBatterie.ini' }
Note "Barre des menus activee"

# 4) Fond d'ecran : seulement si Windows l'a remplace
$fond = Join-Path $dossier 'fond_ecran.jpg'
$actuel = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
if ((Test-Path $fond) -and $actuel -ne $fond) {
  try { & (Join-Path $dossier 'fond_ecran.ps1') -Image $fond; Note "Fond d'ecran re-applique" } catch { Note "Fond : $($_.Exception.Message)" }
}
Note "Demarrage termine"
