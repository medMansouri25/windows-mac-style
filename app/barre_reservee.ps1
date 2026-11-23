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
public interface IAudioEndpointVolume {
  [PreserveSig] int RegisterControlChangeNotify(IAudioEndpointVolumeCallback cb); [PreserveSig] int UnregisterControlChangeNotify(IAudioEndpointVolumeCallback cb);
  [PreserveSig] int GetChannelCount(out uint n); [PreserveSig] int SetMasterVolumeLevel(float db, ref Guid ctx); [PreserveSig] int SetMasterVolumeLevelScalar(float v, ref Guid ctx);
  [PreserveSig] int GetMasterVolumeLevel(out float db); [PreserveSig] int GetMasterVolumeLevelScalar(out float v);
  [PreserveSig] int SetChannelVolumeLevel(uint c, float db, ref Guid ctx); [PreserveSig] int SetChannelVolumeLevelScalar(uint c, float v, ref Guid ctx);
  [PreserveSig] int GetChannelVolumeLevel(uint c, out float db); [PreserveSig] int GetChannelVolumeLevelScalar(uint c, out float v);
  [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid ctx); [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m);
}
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
    string force = LireForce();
    int auto = (s.ACLineStatus == 0 || eco == 1) ? 1 : 0;
    int voulu = force == "on" ? 1 : force == "off" ? 0 : auto;
    if (force != ecoForce) { ecoForce = force; modeCandidat = voulu; stable = 5; }   // choix fait dans le panneau : tout de suite
    if (!sansBatterie || force != "auto") ModeEconomie(voulu);
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
    if (pCC.Vis) { EnvoyerCC("Son", n); return; }   // centre de controle ouvert : on bouge son curseur, pas la pastille
    EnvoyerBang("[!SetVariable Vol " + n + " \"MacWidgets\\Volume\"][!UpdateMeasure MesureVolume \"MacWidgets\\Volume\"]");
  }
  void EnvoyerBang(string b) {
    IntPtr h = TrouverFenetre("DummyRainWClass", null); if (h == IntPtr.Zero) return;
    var cd = new COPYDATA(); cd.dwData = (IntPtr)1; cd.cbData = (b.Length + 1) * 2; cd.lpData = Marshal.StringToHGlobalUni(b);
    try { IntPtr r; SendMessageTimeout(h, 0x4A, IntPtr.Zero, ref cd, 2, 1000, out r); } finally { Marshal.FreeHGlobal(cd.lpData); }
  }

  // --- Panneaux en verre (batterie, centre de controle) : fermeture au clic a cote ou avec Echap ---
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int v);
  [StructLayout(LayoutKind.Sequential)] struct RECTP { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECTP r);
  [StructLayout(LayoutKind.Sequential)] struct PT { public int x, y; }
  [DllImport("user32.dll")] static extern bool GetCursorPos(out PT p);
  [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
  [DllImport("gdi32.dll")] static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
  [StructLayout(LayoutKind.Sequential)] struct ACCENT { public int Etat; public int Drapeaux; public uint Couleur; public int Anim; }
  [StructLayout(LayoutKind.Sequential)] struct WCAD { public int Attribut; public IntPtr Donnees; public int Taille; }
  [DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr h, ref WCAD d);
  delegate bool EnumCB(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumCB cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  class Panneau { public string Nom; public IntPtr H; public bool Vis; public int[] Zone = new int[] { -1, -1, -1, -1, 20 }; }
  Panneau pBat = new Panneau { Nom = "PanneauBatterie" }, pCC = new Panneau { Nom = "CentreControle" };
  System.Windows.Forms.Timer minuteurPanneau; bool clicAvant; int recherche = 0;
  int[] curseurs = new int[8];                 // centre de controle : luminosite (x,y,l,h) puis son (x,y,l,h), en pixels, relatifs au panneau
  int glisse = 0, toursCC = 0; int[] derniers = new int[] { -1, -1 };

  int[] LireNombres(string f, int n) {
    var r = new int[n]; for (int i = 0; i < n; i++) r[i] = -1;
    try { var v = System.IO.File.ReadAllText(Dossier + f).Trim().Split(','); for (int i = 0; i < n && i < v.Length; i++) r[i] = int.Parse(v[i]); } catch { }
    return r;
  }
  // zones ecrites par generer_skins.ps1 : icone de la barre (x1,x2,y1,y2) + rayon des coins (+ curseurs)
  void LireZone() {
    pBat.Zone = LireNombres("zone_batterie.txt", 5);
    var c = LireNombres("zone_centre.txt", 13);
    pCC.Zone = new int[] { c[0], c[1], c[2], c[3], c[4] };
    for (int i = 0; i < 8; i++) curseurs[i] = c[5 + i];
  }
  IntPtr TrouverSkin(string fin) {
    IntPtr t = IntPtr.Zero;
    EnumWindows((h, l) => { var sb = new System.Text.StringBuilder(300); GetWindowText(h, sb, 300); if (sb.ToString().EndsWith(fin)) { t = h; return false; } return true; }, IntPtr.Zero);
    return t;
  }
  // coins arrondis (le verre lui-meme est une image : voir Verre)
  void Habiller(Panneau p) {
    RECTP r; GetWindowRect(p.H, out r); int ray = (p.Zone[4] > 0 ? p.Zone[4] : 20) * 2;
    SetWindowRgn(p.H, IntPtr.Zero, true);   // pas de decoupe : Windows peint mal les coins des fenetres Rainmeter ; image et cadre sont deja arrondis
    var a = new ACCENT(); a.Etat = 0;   // aucun effet Windows (il peindrait les coins) : le verre est l'image de fond
    int taille = Marshal.SizeOf(a); IntPtr q = Marshal.AllocHGlobal(taille);
    try { Marshal.StructureToPtr(a, q, false); var d = new WCAD(); d.Attribut = 19; d.Donnees = q; d.Taille = taille; SetWindowCompositionAttribute(p.H, ref d); }
    finally { Marshal.FreeHGlobal(q); }
  }
  // Verre facon dock : Windows ne floute pas les fenetres Rainmeter (transparence pixel par pixel),
  // alors juste avant l'ouverture on photographie ce qu'il y a derriere le panneau, on le floute
  // et on le teinte legerement : cette image devient le fond du panneau.
  string Verre(Panneau p) {
    RECTP r; GetWindowRect(p.H, out r); int w = r.r - r.l, h = r.b - r.t; if (w < 10 || h < 10) return "";
    string dossierSkin = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), @"Rainmeter\Skins\MacWidgets\" + p.Nom);
    // nom unique a chaque ouverture (Rainmeter garde les images en memoire) ; on efface les anciennes
    string f = System.IO.Path.Combine(dossierSkin, "verre" + DateTime.Now.Ticks + ".png");
    try { foreach (var v in System.IO.Directory.GetFiles(dossierSkin, "verre*.png")) System.IO.File.Delete(v); } catch { }
    try {
      using (var ecran = new System.Drawing.Bitmap(w, h)) {
        using (var g = System.Drawing.Graphics.FromImage(ecran)) g.CopyFromScreen(r.l, r.t, 0, 0, new System.Drawing.Size(w, h));
        int pw = Math.Max(2, w / 18), ph = Math.Max(2, h / 18);
        using (var petit = new System.Drawing.Bitmap(pw, ph)) {
          using (var g = System.Drawing.Graphics.FromImage(petit)) { g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic; g.DrawImage(ecran, 0, 0, pw, ph); }
          using (var g = System.Drawing.Graphics.FromImage(ecran)) {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
            g.DrawImage(petit, new System.Drawing.Rectangle(0, 0, w, h));
            using (var voile = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(78, 28, 26, 34))) g.FillRectangle(voile, 0, 0, w, h);
          }
        }
        // coins arrondis transparents (comme la forme du panneau)
        using (var rond = new System.Drawing.Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb)) {
          int d = (p.Zone[4] > 0 ? p.Zone[4] : 20) * 2;
          using (var g = System.Drawing.Graphics.FromImage(rond))
          using (var forme = new System.Drawing.Drawing2D.GraphicsPath())
          using (var pinceau = new System.Drawing.TextureBrush(ecran)) {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            forme.AddArc(0, 0, d, d, 180, 90); forme.AddArc(w - d - 1, 0, d, d, 270, 90);
            forme.AddArc(w - d - 1, h - d - 1, d, d, 0, 90); forme.AddArc(0, h - d - 1, d, d, 90, 90); forme.CloseFigure();
            g.FillPath(pinceau, forme);
          }
          rond.Save(f, System.Drawing.Imaging.ImageFormat.Png);
        }
      }
      return f;
    } catch { return ""; }
  }
  // ouverture / fermeture d'un panneau (clic sur son icone dans la barre)
  void Basculer(Panneau p) {
    if (p.H == IntPtr.Zero || !IsWindow(p.H)) p.H = TrouverSkin(p.Nom + ".ini");
    if (p.H == IntPtr.Zero) return;
    string cfg = "\"MacWidgets\\" + p.Nom + "\"";
    if (IsWindowVisible(p.H)) { EnvoyerBang("[!Hide " + cfg + "]"); return; }
    foreach (var a in new[] { pBat, pCC }) if (a != p && a.H != IntPtr.Zero && IsWindowVisible(a.H)) EnvoyerBang("[!Hide \"MacWidgets\\" + a.Nom + "\"]");
    string img = Verre(p);
    EnvoyerBang("[!SetVariable FondVerre \"" + img + "\" " + cfg + "][!UpdateMeter FondVerre " + cfg + "][!Redraw " + cfg + "][!Show " + cfg + "]");
  }
  void SurveillerPanneau(object o, EventArgs e) {
    bool chercher = recherche++ % 20 == 0;     // cherche les fenetres au plus toutes les 2,4 s
    bool gauche = (GetAsyncKeyState(0x01) & 0x8000) != 0;
    bool clic = gauche || (GetAsyncKeyState(0x02) & 0x8000) != 0;
    bool echap = (GetAsyncKeyState(0x1B) & 0x8000) != 0;
    PT pt; GetCursorPos(out pt);
    foreach (var p in new[] { pBat, pCC }) {
      if (p.H == IntPtr.Zero || !IsWindow(p.H)) { p.H = IntPtr.Zero; p.Vis = false; if (chercher) p.H = TrouverSkin(p.Nom + ".ini"); if (p.H == IntPtr.Zero) continue; }
      bool vis = IsWindowVisible(p.H);
      if (vis && !p.Vis) { Habiller(p); if (p == pCC) OuvertureCC(); }
      p.Vis = vis;
      if (!vis) { if (p == pCC) glisse = 0; continue; }
      RECTP r; GetWindowRect(p.H, out r);
      bool dedans = pt.x >= r.l && pt.x < r.r && pt.y >= r.t && pt.y < r.b;
      if ((clic && !clicAvant) || echap) {
        bool surIcone = pt.x >= p.Zone[0] && pt.x <= p.Zone[1] && pt.y >= p.Zone[2] && pt.y <= p.Zone[3];
        if (echap || (!dedans && !surIcone)) { EnvoyerBang("[!Hide \"MacWidgets\\" + p.Nom + "\"]"); continue; }
        if (p == pCC && gauche && dedans) { glisse = Curseur(pt, r); derniers[0] = -1; derniers[1] = -1; }
      }
      if (p == pCC) {
        if (!gauche) glisse = 0;
        if (glisse != 0) AppliquerCurseur(glisse, pt, r);
        if (++toursCC % 10 == 0) Executer("musique");   // musique en cours relue toutes les 1,2 s, seulement panneau ouvert
      }
    }
    clicAvant = clic;
    minuteurPanneau.Interval = glisse != 0 ? 30 : 120;   // plus fluide pendant qu'on fait glisser un curseur
  }

  // --- Centre de controle : curseurs (on peut cliquer ou faire glisser), commandes, musique ---
  public static Func<string, string> Commande;   // fourni par PowerShell (Wi-Fi, Bluetooth, musique : API WinRT)
  void Executer(string c) { if (Commande == null) return; string b = ""; try { b = Commande(c); } catch { } if (!string.IsNullOrEmpty(b)) EnvoyerBang(b); }
  void EnvoyerCC(string var, int v) {
    EnvoyerBang("[!SetVariable " + var + " " + v + " \"MacWidgets\\CentreControle\"][!UpdateMeasure Mesure" + var + " \"MacWidgets\\CentreControle\"][!UpdateMeterGroup " + var + " \"MacWidgets\\CentreControle\"][!Redraw \"MacWidgets\\CentreControle\"]");
  }
  int Curseur(PT pt, RECTP r) {
    for (int k = 0; k < 2; k++) {
      int x = r.l + curseurs[k * 4], y = r.t + curseurs[k * 4 + 1], w = curseurs[k * 4 + 2], h = curseurs[k * 4 + 3];
      if (w > 0 && pt.x >= x - h / 2 && pt.x <= x + w + h / 2 && pt.y >= y - h / 2 && pt.y <= y + h + h / 2) return k + 1;
    }
    return 0;
  }
  void AppliquerCurseur(int k, PT pt, RECTP r) {
    int i = (k - 1) * 4, x = r.l + curseurs[i], w = curseurs[i + 2];
    int v = (int)Math.Round(Math.Max(0.0, Math.Min(1.0, (pt.x - x) / (double)w)) * 100);
    if (v == derniers[k - 1]) return; derniers[k - 1] = v;
    if (k == 1) RegleLuminosite(v); else RegleSon(v);
  }
  System.Management.ManagementObject methodesLum;
  void RegleLuminosite(int v) {
    try {
      if (methodesLum == null) foreach (System.Management.ManagementObject m in new System.Management.ManagementObjectSearcher(@"root\WMI", "SELECT * FROM WmiMonitorBrightnessMethods").Get()) { methodesLum = m; break; }
      if (methodesLum != null) methodesLum.InvokeMethod("WmiSetBrightness", new object[] { (uint)1, (byte)v });
    } catch { methodesLum = null; }
    EnvoyerCC("Lum", v);
  }
  void RegleSon(int v) {
    try { Guid g = Guid.Empty; volPeriph.SetMasterVolumeLevelScalar(v / 100f, ref g); if (v > 0) volPeriph.SetMute(false, ref g); } catch { }
    EnvoyerCC("Son", v);
  }
  void OuvertureCC() {
    try { foreach (System.Management.ManagementObject m in new System.Management.ManagementObjectSearcher(@"root\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness").Get()) { EnvoyerCC("Lum", Convert.ToInt32(m["CurrentBrightness"])); break; } } catch { }
    try { float f; bool mu; volPeriph.GetMasterVolumeLevelScalar(out f); volPeriph.GetMute(out mu); EnvoyerCC("Son", mu ? -1 : (int)Math.Round(f * 100)); } catch { }
    Executer("etat"); Executer("musique-force"); toursCC = 0;
  }
  // commandes envoyees par le panneau (WindowMessagePlugin -> message WM_APP+1)
  void ActionCC(int c) {
    if (c == 1) Touche(0xB3); else if (c == 2) Touche(0xB0); else if (c == 3) Touche(0xB1);       // lecture/pause, suivant, precedent
    else if (c == 4) Executer("wifi"); else if (c == 5) Executer("bluetooth");
    else if (c == 10) Basculer(pBat); else if (c == 11) Basculer(pCC);                          // icones de la barre
    else if (c == 6) { try { bool mu; Guid g = Guid.Empty; volPeriph.GetMute(out mu); volPeriph.SetMute(!mu, ref g); } catch { } }
    if (c <= 3) toursCC = 6;   // musique relue dans 0,5 s
  }
  void Touche(byte v) { keybd_event(v, 0, 1, UIntPtr.Zero); keybd_event(v, 0, 3, UIntPtr.Zero); }

  // --- Mode eco choisi dans le panneau : auto (selon le chargeur), on (force), off (coupe) ---
  string ecoForce = "auto";
  // dans le dossier du panneau : Rainmeter n'accepte d'ecrire (!WriteKeyValue) que dans ses skins
  static readonly string FichierEtat = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), @"Rainmeter\Skins\MacWidgets\PanneauBatterie\etat.inc");
  string LireForce() {
    try { foreach (var l in System.IO.File.ReadAllLines(FichierEtat)) { var t = l.Trim(); if (t.StartsWith("EcoForce=")) return t.Substring(9).Trim().ToLower(); } } catch { }
    return "auto";
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
          if (pCC.Vis) { EnvoyerCC("Lum", v); return; }
          EnvoyerBang("[!SetVariable Lum " + v + " \"MacWidgets\\Luminosite\"][!UpdateMeasure MesureLum \"MacWidgets\\Luminosite\"]");
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
    Size = new System.Drawing.Size(1, 1); Opacity = 0; Text = "InterfaceMacMoteur";   // nom vise par le centre de controle (WindowMessagePlugin)
    taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    cb = RegisterWindowMessage("BarreReserveeMac");
    minuteur = new System.Windows.Forms.Timer(); minuteur.Interval = 3000; minuteur.Tick += Verifier; minuteur.Start();
    EcouterLuminosite();
    EcouterVolume();
    LireZone();
    minuteurPanneau = new System.Windows.Forms.Timer(); minuteurPanneau.Interval = 120; minuteurPanneau.Tick += SurveillerPanneau; minuteurPanneau.Start();
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
    else if (m.Msg == 0x8001) { int c = (int)m.WParam; BeginInvoke(new Action(() => ActionCC(c))); }   // commande du centre de controle
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
# Centre de controle : Wi-Fi / Bluetooth (API Radios) et musique en cours (API GSMTC), sans droits administrateur
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$script:asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Attendre($op, [Type]$type) { $t = $script:asTask.MakeGenericMethod($type).Invoke($null, @($op)); $null = $t.Wait(3000); $t.Result }
$null = [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
$script:skinCC = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\MacWidgets\CentreControle'
$script:cfgCC = '"MacWidgets\CentreControle"'
$script:musiqueAvant = ''; $script:titreAvant = $null; $script:pochetteN = 0; $script:gestionnaire = $null
try { $null = Attendre ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus]) } catch { }
function Radios { Attendre ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]]) }
function Nettoyer($t) { ([string]$t) -replace '["\[\]]', '' }
function EtatRadios {
  $r = @(Radios); $w = $r | Where-Object { [string]$_.Kind -eq 'WiFi' } | Select-Object -First 1; $b = $r | Where-Object { [string]$_.Kind -eq 'Bluetooth' } | Select-Object -First 1
  $wOn = $w -and [string]$w.State -eq 'On'; $bOn = $b -and [string]$b.State -eq 'On'
  $wTxt = if (-not $w) { 'Indisponible' } elseif (-not $wOn) { 'Désactivé' } else {
    $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if ($p -and $p.IsWlanConnectionProfile) { Nettoyer $p.ProfileName } else { 'Non connecté' } }
  $bTxt = if (-not $b) { 'Indisponible' } elseif ($bOn) { 'Activé' } else { 'Désactivé' }
  $bleu = '10,132,255,255'; $gris = '255,255,255,45'; $c = $script:cfgCC
  "[!SetVariable WifiFond `"$(if ($wOn) { $bleu } else { $gris })`" $c][!SetVariable WifiTexte `"$wTxt`" $c][!SetVariable BtFond `"$(if ($bOn) { $bleu } else { $gris })`" $c][!SetVariable BtTexte `"$bTxt`" $c][!UpdateMeterGroup Radios $c][!Redraw $c]"
}
function Basculer($type) {
  $r = @(Radios) | Where-Object { [string]$_.Kind -eq $type } | Select-Object -First 1
  if ($r) { $cible = if ([string]$r.State -eq 'On') { [Windows.Devices.Radios.RadioState]::Off } else { [Windows.Devices.Radios.RadioState]::On }; $null = Attendre ($r.SetStateAsync($cible)) ([Windows.Devices.Radios.RadioAccessStatus]) }
  Start-Sleep -Milliseconds 300; EtatRadios
}
function Musique([bool]$force) {
  if (-not $script:gestionnaire) { $script:gestionnaire = Attendre ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]) }
  $s = $script:gestionnaire.GetCurrentSession(); $c = $script:cfgCC
  if (-not $s) {
    if ($script:musiqueAvant -eq 'aucune' -and -not $force) { return '' }
    $script:musiqueAvant = 'aucune'; $script:titreAvant = $null
    return "[!SetVariable MusTitre `"Aucune lecture`" $c][!SetVariable MusArtiste `"`" $c][!SetVariable MusEtat 0 $c][!SetVariable MusImage `"`" $c][!UpdateMeasure MesureMus $c][!UpdateMeterGroup Musique $c][!Redraw $c]"
  }
  $p = Attendre ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
  $joue = if ([string]$s.GetPlaybackInfo().PlaybackStatus -eq 'Playing') { 1 } else { 0 }
  $titre = Nettoyer $p.Title; $artiste = Nettoyer $p.Artist
  $sig = "$titre|$artiste|$joue"
  if ($sig -eq $script:musiqueAvant -and -not $force) { return '' }
  $script:musiqueAvant = $sig
  $image = ''
  if ($titre -ne $script:titreAvant -or $force) {
    $script:titreAvant = $titre; $script:pochetteN = 1 - $script:pochetteN   # deux fichiers en alternance : Rainmeter garde les images en memoire
    $fichier = Join-Path $script:skinCC "pochette$($script:pochetteN).img"
    try {
      $flux = Attendre ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
      $net = [System.IO.WindowsRuntimeStreamExtensions].GetMethod('AsStreamForRead', [Type[]]@([Windows.Storage.Streams.IInputStream])).Invoke($null, @($flux)); $f = [IO.File]::Create($fichier); $net.CopyTo($f); $f.Close(); $net.Close()
      $image = "[!SetVariable MusImage `"$fichier`" $c]"
    } catch { $image = "[!SetVariable MusImage `"`" $c]" }
  }
  if (-not $titre) { $titre = 'Lecture en cours' }
  "[!SetVariable MusTitre `"$titre`" $c][!SetVariable MusArtiste `"$artiste`" $c][!SetVariable MusEtat $joue $c]$image[!UpdateMeasure MesureMus $c][!UpdateMeterGroup Musique $c][!Redraw $c]"
}
[BarreReservee]::Commande = [Func[string, string]] {
  param($c)
  switch ($c) {
    'etat' { EtatRadios }
    'wifi' { Basculer 'WiFi' }
    'bluetooth' { Basculer 'Bluetooth' }
    'musique' { Musique $false }
    'musique-force' { Musique $true }
  }
}
[BarreReservee]::Lancer($Hauteur)
