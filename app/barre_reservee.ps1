# =============================================================================
#  barre_reservee.ps1  -  "moteur" de l'interface (tourne en permanence, invisible)
# -----------------------------------------------------------------------------
#  1. Reserve une bande en haut de l'ecran (comme la barre des menus d'un Mac) :
#     les fenetres agrandies s'arretent dessous (mecanisme "AppBar" de Windows).
#  2. Surveille Rainmeter : s'il se ferme ou plante, il est relance (pleine resolution).
#  3. Surveille l'alimentation toutes les 3 s :
#       - envoie a la barre l'etat de charge / mode economie (couleur de la batterie),
#       - declenche le mode economie (economie.ps1) apres 15 s sur batterie.
#  4. Ecoute les changements de luminosite (evenement Windows, pas de boucle)
#     et affiche la pastille de luminosite.
# =============================================================================
param([int]$Hauteur = 30)

$dossier = $PSScriptRoot
$rainmeter = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Rainmeter' -ErrorAction SilentlyContinue).'(default)'
if (-not $rainmeter) { $rainmeter = (Get-ItemProperty 'HKLM:\SOFTWARE\Rainmeter' -ErrorAction SilentlyContinue).'(default)' }
if (-not $rainmeter) { $rainmeter = 'C:\Program Files\Rainmeter' }
$rainmeterExe = Join-Path $rainmeter 'Rainmeter.exe'

$code = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class BarreReservee : Form {
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)] struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
  [DllImport("user32.dll")] static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr h, int i);
  [StructLayout(LayoutKind.Sequential)] struct SYSTEM_POWER_STATUS { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public int BatteryLifeTime, BatteryFullLifeTime; }
  [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);

  const string Rainmeter = @"__RAINMETER__";
  const string Dossier = @"__DOSSIER__\";

  System.Windows.Forms.Timer minuteur; int dernierEco = -1; int dernierCharge = -1; int tours = 0;
  int modeApplique = -1; int modeCandidat = -1; int stable = 0;

  // --- Rainmeter : relance automatique, en pleine resolution ---
  // "~ HIGHDPIAWARE" (avec le ~) : Rainmeter dessine en pleine resolution ET enregistre ses reglages.
  void SurveillerRainmeter() {
    try {
      if (System.Diagnostics.Process.GetProcessesByName("Rainmeter").Length == 0) {
        var psi = new System.Diagnostics.ProcessStartInfo(Rainmeter);
        psi.UseShellExecute = false;
        psi.EnvironmentVariables["__COMPAT_LAYER"] = "~ HIGHDPIAWARE";
        System.Diagnostics.Process.Start(psi);
        dernierEco = -1; dernierCharge = -1;
      }
    } catch { }
  }

  void Bang(string b) { try { System.Diagnostics.Process.Start(Rainmeter, b); } catch { } }

  // --- Alimentation (toutes les 3 s) ---
  void Verifier(object o, EventArgs e) {
    if (tours > 3) SurveillerRainmeter();
    SYSTEM_POWER_STATUS s;
    if (!GetSystemPowerStatus(out s)) return;
    int eco = (s.SystemStatusFlag == 1) ? 1 : 0;
    int charge = ((s.BatteryFlag & 8) != 0) ? 1 : 0;
    tours++;
    if (eco != dernierEco || charge != dernierCharge || tours % 12 == 0) {
      dernierEco = eco; dernierCharge = charge;
      Bang("[!SetVariable Economie " + eco + " \"MacWidgets\\BarreMenus\"][!SetVariable EnCharge " + charge + " \"MacWidgets\\BarreMenus\"]");
    }
    bool sansBatterie = (s.BatteryFlag & 128) != 0;
    if (!sansBatterie) ModeEconomie(s.ACLineStatus == 0 || eco == 1 ? 1 : 0);
  }

  // Mode economie : declenche apres 15 s d'etat stable (5 verifications), pour ignorer un cable qui bouge
  void ModeEconomie(int voulu) {
    if (voulu != modeCandidat) { modeCandidat = voulu; stable = 0; return; }
    stable++;
    if (stable < 5 || voulu == modeApplique) return;
    modeApplique = voulu;
    try {
      System.Diagnostics.Process.Start("wscript.exe", "\"" + Dossier + "lancer_invisible.vbs\" \"" + Dossier + "economie.ps1\" " + (voulu == 1 ? "Activer" : "Desactiver"));
    } catch { }
  }

  // --- Luminosite : Windows previent a chaque changement ---
  System.Management.ManagementEventWatcher veilleLum;
  void EcouterLuminosite() {
    try {
      veilleLum = new System.Management.ManagementEventWatcher(new System.Management.ManagementScope(@"root\WMI"),
        new System.Management.WqlEventQuery("SELECT * FROM WmiMonitorBrightnessEvent"));
      veilleLum.EventArrived += (s, e) => {
        try {
          int v = Convert.ToInt32(e.NewEvent["Brightness"]);
          Bang("[!SetVariable Lum " + v + " \"MacWidgets\\Luminosite\"][!UpdateMeasure MesureLum \"MacWidgets\\Luminosite\"]");
        } catch { }
      };
      veilleLum.Start();
    } catch { } // ecran externe / PC fixe : pas de luminosite logicielle, ce n'est pas grave
  }

  // --- AppBar : reserve la bande du haut ---
  uint cb, taskbarCreated; bool inscrit; int hauteurLogique;

  public BarreReservee(int h) {
    hauteurLogique = h;
    FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false;
    StartPosition = FormStartPosition.Manual; Location = new System.Drawing.Point(-32000, -32000);
    Size = new System.Drawing.Size(1, 1); Opacity = 0;
    taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    cb = RegisterWindowMessage("BarreReserveeMac");
    minuteur = new System.Windows.Forms.Timer(); minuteur.Interval = 3000; minuteur.Tick += Verifier; minuteur.Start();
    EcouterLuminosite();
  }
  protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x80 | 0x08000000; return p; } }
  protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Inscrire(); }
  protected override void SetVisibleCore(bool v) { base.SetVisibleCore(false); if (!IsHandleCreated) CreateHandle(); }
  int HauteurPhysique() { int dpi = GetDeviceCaps(GetDC(IntPtr.Zero), 88); return (int)Math.Round(hauteurLogique * dpi / 96.0); }
  void Inscrire() {
    var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(d); d.hWnd = Handle; d.uCallbackMessage = cb;
    if (inscrit) SHAppBarMessage(1, ref d);
    SHAppBarMessage(0, ref d); inscrit = true;
    Placer();
  }
  void Placer() {
    var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(d); d.hWnd = Handle; d.uEdge = 1;
    d.rc.left = 0; d.rc.right = GetSystemMetrics(0); d.rc.top = 0; d.rc.bottom = HauteurPhysique();
    SHAppBarMessage(2, ref d);
    d.rc.bottom = d.rc.top + HauteurPhysique();
    SHAppBarMessage(3, ref d);
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == (int)taskbarCreated) { inscrit = false; Inscrire(); }      // Explorateur relance
    else if (m.Msg == (int)cb && (int)m.WParam == 1) { Placer(); }
    else if (m.Msg == 0x007E) { Placer(); }                                 // changement de resolution
    base.WndProc(ref m);
  }
  protected override void OnFormClosing(FormClosingEventArgs e) {
    var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(d); d.hWnd = Handle; SHAppBarMessage(1, ref d); base.OnFormClosing(e);
  }
  public static void Lancer(int h) {
    bool nouveau;
    using (var verrou = new System.Threading.Mutex(true, "InterfaceMacBarreReservee", out nouveau)) {
      if (!nouveau) return;   // deja lance
      SetProcessDPIAware(); Application.Run(new BarreReservee(h));
    }
  }
}
'@
$code = $code.Replace('__RAINMETER__', $rainmeterExe).Replace('__DOSSIER__', $dossier.TrimEnd('\'))
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Management -TypeDefinition $code
[BarreReservee]::Lancer($Hauteur)
