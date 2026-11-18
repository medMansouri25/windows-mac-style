# =============================================================================
#  conservation.ps1 -Etat On|Off  -  mode conservation de la batterie (PC HP)
#  Active ou coupe le reglage BIOS HP « Battery Health Manager »
#  (« Maximize my battery health » = charge limitee a environ 80 %).
#  Windows demande l'autorisation (Oui/Non) a chaque fois : aucun droit
#  administrateur permanent n'est installe.
# =============================================================================
param([ValidateSet('On', 'Off')][string]$Etat = 'On', [switch]$Admin)
$dossier = $PSScriptRoot
$resultat = Join-Path $dossier 'conservation_resultat.txt'

if ($Admin) {
  # --- partie administrateur : uniquement ce reglage, rien d'autre ---
  try {
    $interface = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSettingInterface -ErrorAction Stop
    $r = Invoke-CimMethod -InputObject $interface -MethodName SetBIOSSetting -Arguments @{ Name = 'Battery Health Manager'; Value = "Maximize my battery health $Etat"; Password = '<utf-16/>' }
    $lu = (Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSetting -Filter "Name='Battery Health Manager'").CurrentValue
    Set-Content $resultat "$($r.Return)|$lu" -Encoding UTF8
  } catch { Set-Content $resultat "erreur|$($_.Exception.Message)" -Encoding UTF8 }
  exit
}

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
$fichierEtat = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\MacWidgets\PanneauBatterie\etat.inc'
$avant = 'inconnu'
if (Test-Path $fichierEtat) { $m = [regex]::Match([IO.File]::ReadAllText($fichierEtat), '(?m)^Conservation=(.*)$'); if ($m.Success) { $avant = $m.Groups[1].Value.Trim() } }

Remove-Item $resultat -ErrorAction SilentlyContinue
try { Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Etat $Etat -Admin" } catch { }   # « Non » : rien ne change

$nouveau = $avant
if (Test-Path $resultat) {
  $r = (Get-Content $resultat -Raw).Trim(); Remove-Item $resultat -ErrorAction SilentlyContinue
  if ($r -match 'health On$') { $nouveau = 'On' } elseif ($r -match 'health Off$') { $nouveau = 'Off' }
}
if (Test-Path $fichierEtat) {
  $t = [IO.File]::ReadAllText($fichierEtat)
  $t = if ($t -match '(?m)^Conservation=') { [regex]::Replace($t, '(?m)^Conservation=.*$', "Conservation=$nouveau") } else { $t.TrimEnd() + "`r`nConservation=$nouveau`r`n" }
  [IO.File]::WriteAllText($fichierEtat, $t, [Text.Encoding]::Unicode)
}
$c = '"MacWidgets\PanneauBatterie"'
[RmEnvoi]::Bang("[!SetVariable Conservation $nouveau $c][!UpdateMeasure MesureCons $c][!UpdateMeter * $c][!Redraw $c]")
& (Join-Path $dossier 'infos_batterie.ps1')
