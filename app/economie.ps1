# =============================================================================
#  economie.ps1  -  mode economie automatique (lance par barre_reservee.ps1)
# -----------------------------------------------------------------------------
#  Activer    : PC debranche (ou mode economie) depuis 15 s
#               -> ferme les programmes d'arriere-plan listes dans config.json,
#               -> ecran a la frequence "batterie" (60 Hz par defaut),
#               -> luminosite plafonnee (60 % par defaut).
#  Desactiver : PC rebranche -> remet frequence + luminosite d'origine
#               et relance (fenetres reduites) les programmes qui avaient ete fermes.
#  Journal : economie.log (dans le dossier d'installation)
# =============================================================================
param([ValidateSet('Activer','Desactiver')][string]$Mode)
$dossier = $PSScriptRoot
$etatFichier  = Join-Path $dossier 'economie_etat.json'
$ecranFichier = Join-Path $dossier 'economie_ecran.json'
$journal      = Join-Path $dossier 'economie.log'
function Note($t) { Add-Content $journal ("{0:dd/MM HH:mm:ss}  {1}" -f (Get-Date), $t) }
if ((Test-Path $journal) -and (Get-Item $journal).Length -gt 50KB) { Remove-Item $journal }

$config = Get-Content (Join-Path $dossier 'config.json') -Raw | ConvertFrom-Json
$eco = $config.economie
if (-not $eco.actif) { Note "Mode economie desactive dans config.json"; return }

Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class FenEco { [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int c); }' -ErrorAction SilentlyContinue

function Steam-Exe { $s = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe; if ($s) { $s -replace '/', '\' } }
function Trouver-AppID($nomMenu) { if ($nomMenu) { (Get-StartApps | Where-Object { $_.Name -eq $nomMenu } | Select-Object -First 1).AppID } }
function Lum-Actuelle { (Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1).CurrentBrightness }
function Lum-Regler($v) { Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = [byte]$v } | Out-Null }

if ($Mode -eq 'Activer') {
  $fermes = @()
  foreach ($p in $eco.programmes) {
    $procs = Get-Process -Name $p.processus -ErrorAction SilentlyContinue
    if (-not $procs) { continue }
    $mo = [math]::Round(($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
    # memoriser comment le relancer (identifiant du menu Demarrer)
    $appid = Trouver-AppID $p.menuDemarrer
    if ($p.nom -eq 'Steam' -and (Steam-Exe)) {
      Start-Process (Steam-Exe) -ArgumentList '-shutdown' -ErrorAction SilentlyContinue
      for ($i = 0; $i -lt 20 -and (Get-Process steam -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    }
    if ($p.nom -eq 'NVIDIA Overlay') {
      # le "relanceur" NVIDIA de la session utilisateur (pas le service systeme)
      Get-CimInstance Win32_Process -Filter "Name='nvcontainer.exe'" | Where-Object { $_.CommandLine -match 'SPUser' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Get-Process -Name $p.processus -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $fermes += [pscustomobject]@{ nom = $p.nom; appid = $appid; relancer = [bool]$p.relancer }
    Note "Ferme : $($p.nom) ($mo Mo liberes)"
  }
  # seconde passe : ce qui serait reapparu
  Start-Sleep 3
  foreach ($p in $eco.programmes) { if ($fermes.nom -contains $p.nom) { Get-Process -Name $p.processus -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } }
  $avant = @(); if (Test-Path $etatFichier) { $avant = @((Get-Content $etatFichier -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) }
  $tous = @($avant) + @($fermes | Where-Object { $avant.nom -notcontains $_.nom })
  ConvertTo-Json -InputObject @($tous) | Set-Content $etatFichier -Encoding UTF8

  # Ecran
  try {
    $hzAvant = [int]((& (Join-Path $dossier 'frequence_ecran.ps1') -Lister) -replace '.*actuel (\d+) Hz.*','$1')
    $lum = $null; try { $lum = Lum-Actuelle } catch { }
    if (-not (Test-Path $ecranFichier)) { @{ Hz = $hzAvant; Luminosite = $lum } | ConvertTo-Json | Set-Content $ecranFichier -Encoding UTF8 }
    if ($eco.frequenceBatterie -gt 0) { & (Join-Path $dossier 'frequence_ecran.ps1') -Hz $eco.frequenceBatterie | Out-Null }
    if ($null -ne $lum -and $eco.luminositeMaxBatterie -gt 0 -and $lum -gt $eco.luminositeMaxBatterie) { Lum-Regler $eco.luminositeMaxBatterie }
    Note "Ecran : $($eco.frequenceBatterie) Hz (avant $hzAvant Hz), luminosite max $($eco.luminositeMaxBatterie) % (avant $lum %)"
  } catch { Note "Ecran : $($_.Exception.Message)" }
  Note "Mode economie ACTIF ($(@($fermes).Count) programme(s) ferme(s))"
}
else {
  if (Test-Path $ecranFichier) {
    try {
      $e = Get-Content $ecranFichier -Raw | ConvertFrom-Json
      if ($e.Hz) { & (Join-Path $dossier 'frequence_ecran.ps1') -Hz ([int]$e.Hz) | Out-Null }
      if ($null -ne $e.Luminosite) { Lum-Regler $e.Luminosite }
      Note "Ecran remis a $($e.Hz) Hz et luminosite $($e.Luminosite) %"
    } catch { Note "Ecran : $($_.Exception.Message)" }
    Remove-Item $ecranFichier -ErrorAction SilentlyContinue
  }
  if (-not (Test-Path $etatFichier)) { Note "Mode economie desactive (rien a relancer)"; return }
  $aRelancer = @((Get-Content $etatFichier -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
  foreach ($r in $aRelancer) {
    if (-not $r.relancer) { continue }
    $p = $eco.programmes | Where-Object { $_.nom -eq $r.nom } | Select-Object -First 1
    if ($p -and (Get-Process -Name $p.processus -ErrorAction SilentlyContinue)) { continue }
    try {
      if ($r.nom -eq 'Steam' -and (Steam-Exe)) { Start-Process (Steam-Exe) -ArgumentList '-silent' }
      elseif ($r.appid) {
        Start-Process explorer.exe "shell:AppsFolder\$($r.appid)"
        for ($i = 0; $i -lt 30; $i++) {   # reduire la fenetre des qu'elle apparait
          Start-Sleep -Milliseconds 500
          $w = Get-Process -Name $p.processus -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
          if ($w) { [FenEco]::ShowWindowAsync($w.MainWindowHandle, 6) | Out-Null; break }
        }
      } else { continue }
      Note "Relance : $($r.nom)"
    } catch { Note "Relance impossible : $($r.nom) ($($_.Exception.Message))" }
  }
  # nouvel essai si un programme relance s'est arrete
  Start-Sleep 8
  foreach ($r in $aRelancer) {
    if (-not $r.relancer -or -not $r.appid) { continue }
    $p = $eco.programmes | Where-Object { $_.nom -eq $r.nom } | Select-Object -First 1
    if ($p -and -not (Get-Process -Name $p.processus -ErrorAction SilentlyContinue)) { Start-Process explorer.exe "shell:AppsFolder\$($r.appid)"; Note "Nouvel essai : $($r.nom)" }
  }
  Remove-Item $etatFichier -ErrorAction SilentlyContinue
  Note "Mode economie desactive"
}
