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

// --- Volume : interfaces Windows (Core Audio) pour etre prevenu des changements ---
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator { [PreserveSig] int EnumAudioEndpoints(int f, int s, out IntPtr d); [PreserveSig] int GetDefaultAudioEndpoint(int flux, int role, out IMMDevice dev); }
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); [PreserveSig] int OpenPropertyStore(int a, out IntPtr p); [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume { [PreserveSig] int RegisterControlChangeNotify(IAudioEndpointVolumeCallback cb); [PreserveSig] int UnregisterControlChangeNotify(IAudioEndpointVolumeCallback cb); }
[Guid("657804FA-D6AD-4496-8A60-352752AF4F89"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolumeCallback { [PreserveSig] int OnNotify(IntPtr data); }
public class EcouteVolume : IAudioEndpointVolumeCallback {
  public Action<int> Change; int dernier = -99;
  public int OnNotify(IntPtr d) {
    try {
      bool muet = Marshal.ReadInt32(d, 16) != 0;
      float v = BitConverter.ToSingle(BitConverter.GetBytes(Marshal.ReadInt32(d, 20)), 0);
      int n = muet ? -1 : (int)Math.Round(v * 100);
      if (n != dernier) { dernier = n; if (Change != null) Change(n); }
    } catch { }
    return 0;
  }
}

public class BarreReservee : Form {
  public static Func<string> LireWifi;   // fourni par PowerShell (API reseau de Windows)
  string dernierWifi = "";
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

  System.Windows.Forms.Timer minuteur; int dernierEco = -1; int dernierCharge = -1; int tours = 0; int renvoi = 0;
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
        dernierEco = -1; dernierCharge = -1; renvoi = 4; // Rainmeter met ~2 s a charger la barre : renvoyer l'etat pendant 12 s
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
    bool sansBatterie = (s.BatteryFlag & 128) != 0;
    if (!sansBatterie) ModeEconomie(s.ACLineStatus == 0 || eco == 1 ? 1 : 0);
    // batterie jaune : economiseur Windows OU notre mode economie actif
    if (modeApplique == 1) eco = 1;
    int charge = ((s.BatteryFlag & 8) != 0) ? 1 : 0;
    tours++;
    if (tours % 12 == 0) EcouterVolume();   // sortie audio changee (casque, ecran...) ?
    bool renvoyer = renvoi > 0; if (renvoi > 0) renvoi--;
    if (eco != dernierEco || charge != dernierCharge || renvoyer || tours % 12 == 0) {
      dernierEco = eco; dernierCharge = charge;
      Bang("[!SetVariable Economie " + eco + " \"MacWidgets\\BarreMenus\"][!SetVariable EnCharge " + charge + " \"MacWidgets\\BarreMenus\"]");
    }
    // Wi-Fi : niveau du signal (0 = pas de connexion, 1 a 4 = arcs allumes), lu toutes les 6 s
    if (LireWifi != null && (tours % 2 == 0 || renvoyer)) {
      string w = ""; try { w = LireWifi(); } catch { }
      if (w.Contains("|") && (w != dernierWifi || renvoyer || tours % 12 == 0)) {
        dernierWifi = w; string[] p = w.Split(new char[] { '|' }, 2);
        try { System.Diagnostics.Process.Start(Rainmeter, "[!SetVariable WifiNiv " + p[0] + " \"MacWidgets\\BarreMenus\"][!SetVariable WifiInfo \"" + p[1] + "\" \"MacWidgets\\BarreMenus\"][!UpdateMeasure MesureWifi \"MacWidgets\\BarreMenus\"]"); } catch { }
      }
    }
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

  // --- Volume : Windows previent a chaque changement (remplace la verification 4 fois par seconde) ---
  [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "FindWindowW")] static extern IntPtr TrouverFenetre(string c, string t);
  [StructLayout(LayoutKind.Sequential)] struct COPYDATA { public IntPtr dwData; public int cbData; public IntPtr lpData; }
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, int msg, IntPtr w, ref COPYDATA l, int flags, int delai, out IntPtr r);
  IAudioEndpointVolume volPeriph; EcouteVolume volEcoute; string volId = "";
  void EcouterVolume() {
    try {
      var en = (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")));
      IMMDevice dev; if (en.GetDefaultAudioEndpoint(0, 0, out dev) != 0 || dev == null) return;
      string id; dev.GetId(out id);
      if (id == volId && volPeriph != null) return;          // meme sortie audio : deja a l'ecoute
      if (volPeriph != null && volEcoute != null) { try { volPeriph.UnregisterControlChangeNotify(volEcoute); } catch { } }
      Guid iid = typeof(IAudioEndpointVolume).GUID; object o;
      if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return;
      volPeriph = (IAudioEndpointVolume)o;
      if (volEcoute == null) { volEcoute = new EcouteVolume(); volEcoute.Change = EnvoyerVolume; }
      volPeriph.RegisterControlChangeNotify(volEcoute); volId = id;
    } catch { }
  }
  // envoi direct a Rainmeter (WM_COPYDATA), sans lancer de processus a chaque cran de volume
  void EnvoyerVolume(int n) {
    IntPtr h = TrouverFenetre("DummyRainWClass", null); if (h == IntPtr.Zero) return;
    string b = "[!SetVariable Vol " + n + " \"MacWidgets\\Volume\"][!UpdateMeasure MesureVolume \"MacWidgets\\Volume\"]";
    var cd = new COPYDATA(); cd.dwData = (IntPtr)1; cd.cbData = (b.Length + 1) * 2; cd.lpData = Marshal.StringToHGlobalUni(b);
    try { IntPtr r; SendMessageTimeout(h, 0x4A, IntPtr.Zero, ref cd, 2, 1000, out r); } finally { Marshal.FreeHGlobal(cd.lpData); }
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
    EcouterVolume();
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
# Wi-Fi : on lit le signal comme la barre des taches de Windows (sans demander la localisation)
$null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
[BarreReservee]::LireWifi = [Func[string]] {
  $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
  if (-not $p) { return '0|Pas de connexion' }
  $nom = $p.ProfileName -replace '["\[\]]', ''
  if ([string]$p.GetNetworkConnectivityLevel() -ne 'InternetAccess') { return "0|$nom : pas d'acces a Internet" }
  if (-not $p.IsWlanConnectionProfile) { return "4|$nom (cable)" }
  $b = [int]$p.GetSignalBars()
  $n = if ($b -ge 4) { 4 } elseif ($b -eq 3) { 3 } elseif ($b -eq 2) { 2 } else { 1 }
  "$n|Wi-Fi : $nom (signal $b/5)"
}
[BarreReservee]::Lancer($Hauteur)
