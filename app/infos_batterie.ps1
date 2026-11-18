# =============================================================================
#  infos_batterie.ps1  -  remplit le panneau batterie (lance au clic sur l'icone)
#  Etat de charge, temps restant, sante (capacite actuelle / d'origine), cycles.
#  Les valeurs sont envoyees a Rainmeter par WM_COPYDATA (aucune fenetre).
# =============================================================================
$dossier = $PSScriptRoot
$fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class RmEnvoi {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string c, string t);
  [StructLayout(LayoutKind.Sequential)] struct CD { public IntPtr d; public int n; public IntPtr p; }
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, int m, IntPtr w, ref CD l, int f, int t, out IntPtr r);
  public static void Bang(string b) {
    IntPtr h = FindWindow("DummyRainWClass", null); if (h == IntPtr.Zero) return;
    var c = new CD(); c.d = (IntPtr)1; c.n = (b.Length + 1) * 2; c.p = Marshal.StringToHGlobalUni(b);
    try { IntPtr r; SendMessageTimeout(h, 0x4A, IntPtr.Zero, ref c, 2, 2000, out r); } finally { Marshal.FreeHGlobal(c.p); }
  }
}
'@
Add-Type -AssemblyName System.Windows.Forms
function Duree($sec) { $h = [int][math]::Floor($sec / 3600); $m = [int][math]::Floor(($sec % 3600) / 60); if ($h -gt 0) { '{0} h {1:00}' -f $h, $m } else { "$m min" } }
function Etat($cle) { $l = Select-String -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\MacWidgets\PanneauBatterie\etat.inc') -Pattern "^$cle=(.*)$" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($l) { $l.Matches[0].Groups[1].Value.Trim() } else { '' } }

$ps    = [System.Windows.Forms.SystemInformation]::PowerStatus
$pct   = [int][math]::Round($ps.BatteryLifePercent * 100)
$st    = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
$plein = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
$cycles = (Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | Select-Object -First 1).CycleCount

# capacite d'origine : rapport batterie de Windows (1 s), garde en cache une semaine
$cache = Join-Path $dossier 'batterie_origine.txt'
$origine = 0
if ((Test-Path $cache) -and ((Get-Date) - (Get-Item $cache).LastWriteTime).TotalDays -lt 7) { $origine = [int](Get-Content $cache -Raw) }
if (-not $origine) {
  $xml = Join-Path $env:TEMP 'rapport_batterie_interface_mac.xml'
  powercfg /batteryreport /xml /output $xml | Out-Null
  try { [xml]$x = Get-Content $xml -Raw; $origine = [int]@($x.BatteryReport.Batteries.Battery)[0].DesignCapacity; Set-Content $cache $origine } catch { }
  Remove-Item $xml -ErrorAction SilentlyContinue
}

# source et temps
$conservation = Etat 'Conservation'
if ($ps.PowerLineStatus -eq 'Online') {
  if ($st -and $st.Charging -and $st.ChargeRate -gt 0 -and $plein) {
    $cible = if ($conservation -eq 'On') { 0.8 * $plein } else { $plein }
    $reste = [math]::Max(0, $cible - $st.RemainingCapacity) / $st.ChargeRate * 3600
    $source = if ($reste -gt 60) { "En charge · pleine dans $(Duree $reste)" } else { 'En charge' }
  } elseif ($conservation -eq 'On' -and $pct -lt 98) { $source = 'Branché · charge limitée à 80 %' }
  elseif ($pct -ge 98) { $source = 'Branché · batterie pleine' }
  else { $source = 'Branché · recharge en pause' }
} else {
  $source = if ($ps.BatteryLifeRemaining -gt 0) { "Sur batterie · $(Duree $ps.BatteryLifeRemaining) restantes" } else { 'Sur batterie · calcul du temps restant…' }
}

# sante
if ($origine -gt 0 -and $plein) {
  $s = [math]::Min(100, [int][math]::Round(100.0 * $plein / $origine))
  $sante = "$s % · " + $(if ($s -ge 80) { 'Normal' } else { 'Révision conseillée' })
  $capacite = '{0} Wh sur {1} Wh' -f ([math]::Round($plein / 1000, 1)).ToString($fr), ([math]::Round($origine / 1000, 1)).ToString($fr)
} else { $sante = '—'; $capacite = $(if ($plein) { '{0} Wh' -f ([math]::Round($plein / 1000, 1)).ToString($fr) } else { '—' }) }
$ecoActif = if (Test-Path (Join-Path $dossier 'economie_ecran.json')) { 'actif' } else { 'inactif' }

$c = '"MacWidgets\PanneauBatterie"'
[RmEnvoi]::Bang("[!SetVariable Source `"$source`" $c][!SetVariable Sante `"$sante`" $c][!SetVariable Cycles `"$(if ($cycles -ne $null) { $cycles } else { '—' })`" $c][!SetVariable Capacite `"$capacite`" $c][!SetVariable EcoActif `"$ecoActif`" $c][!UpdateMeasure * $c][!UpdateMeter * $c][!Redraw $c]")
