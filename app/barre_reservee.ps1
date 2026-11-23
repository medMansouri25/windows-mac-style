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

// ============================================================================
//  Fenetres en verre dessinees par le moteur : Spotlight et Calendrier + notifications
// ============================================================================
public static class VerreUI {
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int t);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  public static double S = 1.0;   // echelle d'affichage (1.5 = 150 %)
  public static int N(double v) { return (int)Math.Round(v * S); }
  // photo floutee + teinte de ce qu'il y a derriere une zone de l'ecran (meme rendu que les panneaux Rainmeter)
  public static System.Drawing.Bitmap Flou(System.Drawing.Rectangle z) {
    var ecran = new System.Drawing.Bitmap(z.Width, z.Height);
    using (var g = System.Drawing.Graphics.FromImage(ecran)) g.CopyFromScreen(z.X, z.Y, 0, 0, z.Size);
    int pw = Math.Max(2, z.Width / 18), ph = Math.Max(2, z.Height / 18);
    using (var petit = new System.Drawing.Bitmap(pw, ph)) {
      using (var g = System.Drawing.Graphics.FromImage(petit)) { g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic; g.DrawImage(ecran, 0, 0, pw, ph); }
      using (var g = System.Drawing.Graphics.FromImage(ecran)) {
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
        g.DrawImage(petit, new System.Drawing.Rectangle(0, 0, z.Width, z.Height));
        using (var v = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(102, 24, 22, 30))) g.FillRectangle(v, 0, 0, z.Width, z.Height);
        using (var v = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(12, 255, 255, 255))) g.FillRectangle(v, 0, 0, z.Width, z.Height);
      }
    }
    return ecran;
  }
  public static void Arrondir(IntPtr h) { int v = 2; DwmSetWindowAttribute(h, 33, ref v, 4); int c = 0x00787070; DwmSetWindowAttribute(h, 34, ref c, 4); }
  public static System.Drawing.Drawing2D.GraphicsPath Rond(System.Drawing.RectangleF r, float ray) {
    var p = new System.Drawing.Drawing2D.GraphicsPath(); float d = ray * 2;
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90); p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure();
    return p;
  }
  public static System.Drawing.Font Police(double px, bool gras) { return new System.Drawing.Font("Segoe UI Variable Text", (float)(px * S), gras ? System.Drawing.FontStyle.Bold : System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Pixel); }
  public static System.Drawing.Font Icones(double px) { return new System.Drawing.Font("Segoe Fluent Icons", (float)(px * S), System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Pixel); }
  public static void Texte(System.Drawing.Graphics g, string t, System.Drawing.Font f, System.Drawing.Color c, System.Drawing.RectangleF r, bool droite) {
    using (var sf = new System.Drawing.StringFormat(System.Drawing.StringFormatFlags.NoWrap)) using (var b = new System.Drawing.SolidBrush(c)) {
      sf.Trimming = System.Drawing.StringTrimming.EllipsisCharacter; sf.LineAlignment = System.Drawing.StringAlignment.Center;
      sf.Alignment = droite ? System.Drawing.StringAlignment.Far : System.Drawing.StringAlignment.Near;
      g.DrawString(t ?? "", f, b, r, sf);
    }
  }
  // icone d'une application (shell:AppsFolder\ID) ou d'un fichier, avec transparence
  [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellItemImageFactory { [PreserveSig] int GetImage(System.Drawing.Size taille, int options, out IntPtr hbm); }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)] static extern void SHCreateItemFromParsingName(string chemin, IntPtr bc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
  [StructLayout(LayoutKind.Sequential)] struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public short bmPlanes, bmBitsPixel; public IntPtr bmBits; }
  [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int n, ref BITMAP b);
  static System.Collections.Generic.Dictionary<string, System.Drawing.Bitmap> cacheIcones = new System.Collections.Generic.Dictionary<string, System.Drawing.Bitmap>();
  public static System.Drawing.Bitmap Icone(string chemin, int taille) {
    string cle = chemin + "|" + taille;
    lock (cacheIcones) { if (cacheIcones.ContainsKey(cle)) return cacheIcones[cle]; }
    System.Drawing.Bitmap res = null;
    try {
      Guid iid = typeof(IShellItemImageFactory).GUID; IShellItemImageFactory f; SHCreateItemFromParsingName(chemin, IntPtr.Zero, ref iid, out f);
      IntPtr hb; if (f.GetImage(new System.Drawing.Size(taille, taille), 0, out hb) == 0) {
        var bm = new BITMAP(); GetObject(hb, Marshal.SizeOf(bm), ref bm);
        if (bm.bmBits != IntPtr.Zero && bm.bmBitsPixel == 32) {
          using (var tmp = new System.Drawing.Bitmap(bm.bmWidth, bm.bmHeight, bm.bmWidthBytes, System.Drawing.Imaging.PixelFormat.Format32bppPArgb, bm.bmBits)) { res = new System.Drawing.Bitmap(tmp); }
          res.RotateFlip(System.Drawing.RotateFlipType.RotateNoneFlipY);   // l'image de Windows est stockee a l'envers
        } else res = System.Drawing.Image.FromHbitmap(hb);
        DeleteObject(hb);
      }
    } catch { }
    lock (cacheIcones) { cacheIcones[cle] = res; }
    return res;
  }
  // donner le clavier a une fenetre du moteur (Windows le refuse sinon a un programme en arriere-plan)
  public static void Activer(System.Windows.Forms.Form f) {
    // la fenetre a le droit de prendre le clavier : ouverte via le raccourci Alt+Espace (voir le moteur)
    SetForegroundWindow(f.Handle); f.Activate();
  }
}

// --- base : fenetre sans bord, toujours devant, absente de la barre des taches et d'Alt+Tab ---
public class FenetreVerre : System.Windows.Forms.Form {
  protected System.Drawing.Bitmap fond; public DateTime Fermee = DateTime.MinValue;
  public FenetreVerre() {
    FormBorderStyle = System.Windows.Forms.FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; KeyPreview = true;
    StartPosition = System.Windows.Forms.FormStartPosition.Manual; AutoScaleMode = System.Windows.Forms.AutoScaleMode.None;
    SetStyle(System.Windows.Forms.ControlStyles.AllPaintingInWmPaint | System.Windows.Forms.ControlStyles.OptimizedDoubleBuffer | System.Windows.Forms.ControlStyles.UserPaint, true);
    BackColor = System.Drawing.Color.FromArgb(40, 38, 46);
  }
  protected override System.Windows.Forms.CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x80; return p; } }
  protected override bool ShowWithoutActivation { get { return false; } }
  // photo du fond prise AVANT l'affichage, sur la hauteur maximale possible
  protected void PreparerFond(System.Drawing.Rectangle zone) { if (fond != null) fond.Dispose(); fond = VerreUI.Flou(zone); }
  public void Fermer() { if (Visible) { Hide(); Fermee = DateTime.Now; } }
  protected virtual bool FermerSiInactive { get { return true; } }
  protected override void OnDeactivate(EventArgs e) { base.OnDeactivate(e); if (FermerSiInactive) Fermer(); }
  protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); VerreUI.Arrondir(Handle); }
  protected void DessinerFond(System.Drawing.Graphics g) {
    if (fond != null) g.DrawImage(fond, 0, 0);
    using (var p = new System.Drawing.Pen(System.Drawing.Color.FromArgb(60, 255, 255, 255), 1)) g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
  }
  protected static System.Drawing.Color Blanc(int a) { return System.Drawing.Color.FromArgb(a, 255, 255, 255); }
  protected static readonly System.Drawing.Color Bleu = System.Drawing.Color.FromArgb(10, 132, 255);
}

// ============================== Spotlight ==============================
public class Spotlight : FenetreVerre {
  class Resultat { public string Section, Titre, Detail, Icone, Cible, Type; }
  public Func<string, string> Commande;
  string texte = ""; bool toutSelect; int choix = 0; int requete = 0;
  System.Collections.Generic.List<Resultat> res = new System.Collections.Generic.List<Resultat>();
  System.Collections.Generic.List<Resultat> fichiers = new System.Collections.Generic.List<Resultat>();
  System.Collections.Generic.List<string[]> apps = new System.Collections.Generic.List<string[]>(); DateTime appsLues = DateTime.MinValue;
  System.Windows.Forms.Timer curseur = new System.Windows.Forms.Timer(); bool curseurVisible = true;
  int L { get { return VerreUI.N(680); } }
  int Haut { get { return VerreUI.N(60); } }
  int Ligne { get { return VerreUI.N(42); } }
  int Entete { get { return VerreUI.N(26); } }
  public Spotlight() { curseur.Interval = 530; curseur.Tick += (s, e) => { curseurVisible = !curseurVisible; Invalidate(new System.Drawing.Rectangle(0, 0, Width, Haut)); }; }
  public void ChargerApps() {
    if (Commande == null || (DateTime.Now - appsLues).TotalMinutes < 10 && apps.Count > 0) return;
    string t = ""; try { t = Commande("apps"); } catch { }
    if (string.IsNullOrEmpty(t)) return;
    var l = new System.Collections.Generic.List<string[]>();
    foreach (var ligne in t.Split('\n')) { var p = ligne.TrimEnd('\r').Split('\t'); if (p.Length == 2 && p[0].Length > 0) l.Add(p); }
    apps = l; appsLues = DateTime.Now;
  }
  public void Ouvrir() {
    if (Visible) { Fermer(); return; }
    if ((DateTime.Now - Fermee).TotalMilliseconds < 350) return;   // le clic sur la loupe vient de la fermer
    var ecran = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
    int x = ecran.X + (ecran.Width - L) / 2, y = ecran.Y + (int)(ecran.Height * 0.06);
    PreparerFond(new System.Drawing.Rectangle(x, y, L, Haut + VerreUI.N(12) + 10 * Ligne + 4 * Entete));
    ChargerApps();
    texte = ""; toutSelect = false; choix = 0; res.Clear(); fichiers.Clear(); sourisAvant = System.Windows.Forms.Cursor.Position;
    Bounds = new System.Drawing.Rectangle(x, y, L, Haut);
    Show(); VerreUI.Activer(this); curseur.Start(); Invalidate();
  }
  protected override void OnDeactivate(EventArgs e) { curseur.Stop(); base.OnDeactivate(e); }
  // --- clavier ---
  protected override bool ProcessCmdKey(ref System.Windows.Forms.Message m, System.Windows.Forms.Keys k) {
    if (k == System.Windows.Forms.Keys.Escape) { Fermer(); return true; }
    if (k == System.Windows.Forms.Keys.Down) { if (res.Count > 0) choix = (choix + 1) % res.Count; Invalidate(); return true; }
    if (k == System.Windows.Forms.Keys.Up) { if (res.Count > 0) choix = (choix - 1 + res.Count) % res.Count; Invalidate(); return true; }
    if (k == System.Windows.Forms.Keys.Enter) { Lancer(choix); return true; }
    if (k == (System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.A)) { toutSelect = true; Invalidate(); return true; }
    if (k == (System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.V)) { try { Changer((toutSelect ? "" : texte) + System.Windows.Forms.Clipboard.GetText().Replace("\r", " ").Replace("\n", " ")); } catch { } return true; }
    if (k == System.Windows.Forms.Keys.Back) { Changer(toutSelect ? "" : (texte.Length > 0 ? texte.Substring(0, texte.Length - 1) : "")); return true; }
    if (k == (System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.Back)) { var t = texte.TrimEnd(); int i = t.LastIndexOf(' '); Changer(toutSelect || i < 0 ? "" : t.Substring(0, i + 1)); return true; }
    return base.ProcessCmdKey(ref m, k);
  }
  protected override void OnKeyPress(System.Windows.Forms.KeyPressEventArgs e) { if (e.KeyChar >= 32) { Changer((toutSelect ? "" : texte) + e.KeyChar); e.Handled = true; } }
  void Changer(string t) { texte = t; toutSelect = false; curseurVisible = true; choix = 0; Chercher(); }
  // --- recherche : calcul, applications (tout de suite), fichiers (index Windows, en arriere-plan) ---
  void Chercher() {
    res.Clear(); string q = texte.Trim();
    if (q.Length > 0) {
      string calcul = Calculer(q);
      if (calcul != null) res.Add(new Resultat { Section = "Calcul", Titre = "= " + calcul, Detail = "Entrée pour copier le résultat", Cible = calcul, Type = "calcul" });
      string ql = q.ToLowerInvariant(); var trouves = new System.Collections.Generic.List<Tuple<int, string[]>>();
      foreach (var a in apps) {
        string n = a[0].ToLowerInvariant(); int score = n == ql ? 100 : n.StartsWith(ql) ? 80 : (" " + n).Contains(" " + ql) ? 60 : n.Contains(ql) ? 40 : 0;
        if (score > 0) trouves.Add(Tuple.Create(score - Math.Min(n.Length, 30) / 10, a));
      }
      trouves.Sort((x, y) => y.Item1.CompareTo(x.Item1));
      for (int i = 0; i < trouves.Count && i < 5; i++) res.Add(new Resultat { Section = "Applications", Titre = trouves[i].Item2[0], Detail = "Application", Icone = @"shell:AppsFolder\" + trouves[i].Item2[1], Cible = trouves[i].Item2[1], Type = "app" });
      foreach (var f in fichiers) res.Add(f);
      res.Add(new Resultat { Section = "Web", Titre = "Rechercher « " + q + " » sur le web", Detail = "Google", Cible = q, Type = "web" });
      int num = ++requete; string terme = q;
      System.Threading.Tasks.Task.Run(() => {
        System.Threading.Thread.Sleep(150); if (num != requete) return;
        var l = ChercherFichiers(terme);
        try { BeginInvoke(new Action(() => { if (num != requete) return; fichiers = l; int c = choix; Chercher2(); choix = Math.Min(c, Math.Max(0, res.Count - 1)); Ajuster(); })); } catch { }
      });
    } else { fichiers.Clear(); requete++; }
    Ajuster();
  }
  void Chercher2() {   // remet les fichiers a leur place (avant le web)
    var w = res.FindAll(r => r.Type == "web"); res.RemoveAll(r => r.Type == "web" || r.Type == "fichier"); res.AddRange(fichiers); res.AddRange(w);
  }
  static System.Collections.Generic.List<Resultat> ChercherFichiers(string q) {
    var l = new System.Collections.Generic.List<Resultat>();
    try {
      using (var cn = new System.Data.OleDb.OleDbConnection("Provider=Search.CollatorDSO;Extended Properties=\"Application=Windows\"")) {
        cn.Open(); var cmd = cn.CreateCommand();
        string t = q.Replace("'", "''").Replace("\"", "");
        cmd.CommandText = "SELECT TOP 12 System.ItemNameDisplay, System.ItemUrl, System.ItemFolderPathDisplay FROM SystemIndex WHERE CONTAINS(System.ItemNameDisplay, '\"" + t + "*\"') AND SCOPE='file:' AND System.FileExtension <> '.lnk' AND System.ItemType <> 'Directory' ORDER BY System.DateModified DESC";
        using (var r = cmd.ExecuteReader()) while (r.Read()) {
          string url = r[1] as string; if (string.IsNullOrEmpty(url) || !url.StartsWith("file:")) continue;
          string chemin = Uri.UnescapeDataString(url.Substring(5)).Replace('/', '\\');   // vrai chemin (ItemPathDisplay est traduit : « Utilisateurs »)
          if (chemin.IndexOf(@"\AppData\", StringComparison.OrdinalIgnoreCase) >= 0 || chemin.IndexOf(@"\ProgramData\", StringComparison.OrdinalIgnoreCase) >= 0 || !System.IO.File.Exists(chemin)) continue;   // fichiers internes des applications
          if (l.Count >= 4) break;
          l.Add(new Resultat { Section = "Fichiers", Titre = r[0] as string, Detail = r[2] as string, Icone = chemin, Cible = chemin, Type = "fichier" });
        }
      }
    } catch { }
    return l;
  }
  static string Calculer(string q) {
    string s = q.ToLowerInvariant().Replace(" ", "").Replace(",", ".").Replace("×", "*").Replace("x", "*").Replace("÷", "/").Replace(":", "/");
    var pct = System.Text.RegularExpressions.Regex.Match(s, @"^([0-9.]+)%(de|of|\*)([0-9.]+)$");
    if (pct.Success) s = "(" + pct.Groups[1].Value + "/100)*" + pct.Groups[3].Value;
    if (!System.Text.RegularExpressions.Regex.IsMatch(s, @"^[0-9.+\-*/()]+$") || !System.Text.RegularExpressions.Regex.IsMatch(s, @"[0-9]") || !System.Text.RegularExpressions.Regex.IsMatch(s, @"[+\-*/]") && !pct.Success) return null;
    try {
      var v = Convert.ToDouble(new System.Data.DataTable().Compute(s, ""), System.Globalization.CultureInfo.InvariantCulture);
      if (double.IsInfinity(v) || double.IsNaN(v)) return null;
      return Math.Round(v, 6).ToString("0.######", System.Globalization.CultureInfo.GetCultureInfo("fr-FR"));
    } catch { return null; }
  }
  void Lancer(int i) {
    if (i < 0 || i >= res.Count) return; var r = res[i];
    try {
      if (r.Type == "app") System.Diagnostics.Process.Start("explorer.exe", @"shell:AppsFolder\" + r.Cible);
      else if (r.Type == "fichier") System.Diagnostics.Process.Start(r.Cible);
      else if (r.Type == "web") System.Diagnostics.Process.Start("https://www.google.com/search?q=" + Uri.EscapeDataString(r.Cible));
      else if (r.Type == "calcul") System.Windows.Forms.Clipboard.SetText(r.Cible);
    } catch { }
    Fermer();
  }
  void Ajuster() {
    int h = Haut; string sec = null;
    if (res.Count > 0) { h += VerreUI.N(6); foreach (var r in res) { if (r.Section != sec) { h += Entete; sec = r.Section; } h += Ligne; } h += VerreUI.N(8); }
    if (Height != h) Height = h;
    Invalidate();
  }
  protected override void OnMouseClick(System.Windows.Forms.MouseEventArgs e) { int i = LigneSous(e.Y); if (i >= 0) Lancer(i); }
  System.Drawing.Point sourisAvant;   // la souris ne choisit une ligne que si elle bouge vraiment (pas si la fenetre apparait dessous)
  protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e) { var s = System.Windows.Forms.Cursor.Position; if (s == sourisAvant) return; sourisAvant = s; int i = LigneSous(e.Y); if (i >= 0 && i != choix) { choix = i; Invalidate(); } }
  int LigneSous(int y) {
    int yy = Haut + VerreUI.N(6); string sec = null;
    for (int i = 0; i < res.Count; i++) { if (res[i].Section != sec) { yy += Entete; sec = res[i].Section; } if (y >= yy && y < yy + Ligne) return i; yy += Ligne; }
    return -1;
  }
  protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
    var g = e.Graphics; DessinerFond(g);
    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
    using (var ic = VerreUI.Icones(20)) VerreUI.Texte(g, "", ic, Blanc(170), new System.Drawing.RectangleF(VerreUI.N(20), 0, VerreUI.N(30), Haut), false);
    using (var f = VerreUI.Police(22, false)) {
      var zone = new System.Drawing.RectangleF(VerreUI.N(58), 0, L - VerreUI.N(80), Haut);
      if (texte.Length == 0) VerreUI.Texte(g, "Recherche Spotlight", f, Blanc(150), zone, false);
      else {
        if (toutSelect) { var t = g.MeasureString(texte, f); using (var b = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(120, 10, 132, 255))) g.FillRectangle(b, zone.X + 2, (Haut - t.Height) / 2, t.Width - 4, t.Height); }
        VerreUI.Texte(g, texte, f, Blanc(255), zone, false);
      }
      if (curseurVisible) {
        float w = texte.Length == 0 ? 0 : g.MeasureString(texte + "|", f).Width - g.MeasureString("|", f).Width;
        using (var p = new System.Drawing.Pen(Blanc(230), VerreUI.N(1.5))) g.DrawLine(p, zone.X + w + VerreUI.N(2), Haut / 2 - VerreUI.N(13), zone.X + w + VerreUI.N(2), Haut / 2 + VerreUI.N(13));
      }
    }
    if (res.Count == 0) return;
    using (var p = new System.Drawing.Pen(Blanc(40), 1)) g.DrawLine(p, VerreUI.N(14), Haut, L - VerreUI.N(14), Haut);
    int y = Haut + VerreUI.N(6); string sec = null;
    using (var fSec = VerreUI.Police(11.5, true)) using (var fT = VerreUI.Police(14.5, false)) using (var fD = VerreUI.Police(12, false))
    for (int i = 0; i < res.Count; i++) {
      var r = res[i];
      if (r.Section != sec) { sec = r.Section; VerreUI.Texte(g, sec.ToUpperInvariant(), fSec, Blanc(170), new System.Drawing.RectangleF(VerreUI.N(22), y, L - VerreUI.N(44), Entete), false); y += Entete; }
      if (i == choix) using (var b = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(225, 10, 132, 255))) using (var pth = VerreUI.Rond(new System.Drawing.RectangleF(VerreUI.N(10), y, L - VerreUI.N(20), Ligne), VerreUI.N(8))) g.FillPath(b, pth);
      var img = r.Icone != null ? VerreUI.Icone(r.Icone, VerreUI.N(28)) : null;
      if (img != null) g.DrawImage(img, VerreUI.N(22), y + (Ligne - VerreUI.N(28)) / 2, VerreUI.N(28), VerreUI.N(28));
      else using (var ic = VerreUI.Icones(18)) VerreUI.Texte(g, r.Type == "calcul" ? "" : "", ic, Blanc(220), new System.Drawing.RectangleF(VerreUI.N(22), y, VerreUI.N(28), Ligne), false);
      float xt = VerreUI.N(62), lt = L - VerreUI.N(84);
      var tm = g.MeasureString(r.Titre, fT); float lTitre = Math.Min(tm.Width, lt * 0.62f);
      VerreUI.Texte(g, r.Titre, fT, Blanc(255), new System.Drawing.RectangleF(xt, y, lTitre + 4, Ligne), false);
      VerreUI.Texte(g, r.Detail, fD, Blanc(i == choix ? 225 : 175), new System.Drawing.RectangleF(xt + lTitre + VerreUI.N(10), y, lt - lTitre - VerreUI.N(10), Ligne), false);
      y += Ligne;
    }
  }
}

// ======================= Calendrier + notifications =======================
public class Agenda : FenetreVerre {
  class Notif { public string Id, App, Titre, Corps, Aumid; public DateTime Date; }
  public Func<string, string> Commande; public Action<string> Raccourci;
  protected override bool FermerSiInactive { get { return false; } }   // ferme par le moteur (clic a cote, Echap)
  protected override bool ShowWithoutActivation { get { return true; } }
  DateTime mois; System.Collections.Generic.List<Notif> notifs = new System.Collections.Generic.List<Notif>();
  System.Collections.Generic.List<Tuple<System.Drawing.RectangleF, string>> zones = new System.Collections.Generic.List<Tuple<System.Drawing.RectangleF, string>>();
  static readonly System.Globalization.CultureInfo fr = System.Globalization.CultureInfo.GetCultureInfo("fr-FR");
  int L { get { return VerreUI.N(340); } }
  const int MaxNotifs = 5;
  public void Ouvrir(int droite, int haut) {
    if (Visible) { Fermer(); return; }
    if ((DateTime.Now - Fermee).TotalMilliseconds < 350) return;
    mois = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
    Lire();
    int hMax = VerreUI.N(330) + MaxNotifs * VerreUI.N(74) + VerreUI.N(110);
    PreparerFond(new System.Drawing.Rectangle(droite - L, haut, L, hMax));
    Bounds = new System.Drawing.Rectangle(droite - L, haut, L, Hauteur());
    Show(); Invalidate();
  }
  void Lire() {
    notifs.Clear(); if (Commande == null) return;
    string t = ""; try { t = Commande("notifs"); } catch { }
    foreach (var ligne in (t ?? "").Split('\n')) {
      var p = ligne.TrimEnd('\r').Split('\t'); if (p.Length < 6) continue;
      DateTime d; DateTime.TryParse(p[4], null, System.Globalization.DateTimeStyles.RoundtripKind, out d);
      notifs.Add(new Notif { Id = p[0], App = p[1], Titre = p[2], Corps = p[3], Date = d.ToLocalTime(), Aumid = p[5] });
    }
    notifs.Sort((a, b) => b.Date.CompareTo(a.Date));
  }
  int Hauteur() { int n = Math.Min(notifs.Count, MaxNotifs); return VerreUI.N(318) + VerreUI.N(44) + (n == 0 ? VerreUI.N(44) : n * VerreUI.N(74)) + (notifs.Count > MaxNotifs ? VerreUI.N(26) : 0) + VerreUI.N(46); }
  // numero de semaine ISO 8601 (norme francaise) : celui du jeudi de la semaine
  static int Semaine(DateTime d) { var jeudi = d.Date.AddDays(3 - ((int)d.DayOfWeek + 6) % 7); return (jeudi.DayOfYear - 1) / 7 + 1; }
  string Quand(DateTime d) {
    var m = (DateTime.Now - d).TotalMinutes;
    if (m < 1) return "maintenant"; if (m < 60) return "il y a " + (int)m + " min";
    if (d.Date == DateTime.Today) return d.ToString("HH:mm"); if (d.Date == DateTime.Today.AddDays(-1)) return "hier";
    return d.ToString("d MMM", fr);
  }
  protected override void OnMouseClick(System.Windows.Forms.MouseEventArgs e) {
    foreach (var z in zones) if (z.Item1.Contains(e.Location)) {
      string a = z.Item2;
      if (a == "prec") mois = mois.AddMonths(-1); else if (a == "suiv") mois = mois.AddMonths(1);
      else if (a == "auj") mois = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
      else if (a == "effacer") { try { Commande("notif-effacer"); } catch { } notifs.Clear(); Height = Hauteur(); }
      else if (a == "windows") { Fermer(); if (Raccourci != null) Raccourci("N"); return; }
      else if (a.StartsWith("n:")) {
        var n = notifs.Find(x => x.Id == a.Substring(2));
        if (n != null) { try { if (!string.IsNullOrEmpty(n.Aumid)) System.Diagnostics.Process.Start("explorer.exe", @"shell:AppsFolder\" + n.Aumid); Commande("notif-suppr:" + n.Id); } catch { } }
        Fermer(); return;
      }
      Invalidate(); return;
    }
  }
  protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e) {
    bool main = false; foreach (var z in zones) if (z.Item1.Contains(e.Location)) main = true;
    Cursor = main ? System.Windows.Forms.Cursors.Hand : System.Windows.Forms.Cursors.Default;
  }
  protected override bool ProcessCmdKey(ref System.Windows.Forms.Message m, System.Windows.Forms.Keys k) {
    if (k == System.Windows.Forms.Keys.Escape) { Fermer(); return true; }
    return base.ProcessCmdKey(ref m, k);
  }
  protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
    var g = e.Graphics; DessinerFond(g); zones.Clear();
    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
    float m = VerreUI.N(18), lu = L - 2 * m;
    // --- calendrier ---
    using (var fM = VerreUI.Police(16, true)) using (var ic = VerreUI.Icones(13)) using (var fJ = VerreUI.Police(11.5, true)) using (var fD = VerreUI.Police(13.5, false)) using (var fDg = VerreUI.Police(13.5, true)) {
      string titre = mois.ToString("MMMM yyyy", fr); titre = char.ToUpper(titre[0]) + titre.Substring(1);
      var rt = new System.Drawing.RectangleF(m, VerreUI.N(14), lu - VerreUI.N(70), VerreUI.N(30)); VerreUI.Texte(g, titre, fM, Blanc(255), rt, false); zones.Add(Tuple.Create(rt, "auj"));
      if (mois.Year == DateTime.Today.Year && mois.Month == DateTime.Today.Month)   // semaine en cours, a cote du titre
        using (var fS = VerreUI.Police(12.5, false)) {
          float lt = g.MeasureString(titre, fM).Width;
          VerreUI.Texte(g, "·  semaine " + Semaine(DateTime.Today), fS, Blanc(185), new System.Drawing.RectangleF(m + lt + VerreUI.N(2), VerreUI.N(15), lu - VerreUI.N(70) - lt, VerreUI.N(30)), false);
        }
      var rp = new System.Drawing.RectangleF(L - m - VerreUI.N(64), VerreUI.N(14), VerreUI.N(30), VerreUI.N(30)); var rs = new System.Drawing.RectangleF(L - m - VerreUI.N(30), VerreUI.N(14), VerreUI.N(30), VerreUI.N(30));
      VerreUI.Texte(g, "", ic, Blanc(220), rp, false); VerreUI.Texte(g, "", ic, Blanc(220), rs, false); zones.Add(Tuple.Create(rp, "prec")); zones.Add(Tuple.Create(rs, "suiv"));
      float ws = VerreUI.N(30), cw = (lu - ws) / 7f, y0 = VerreUI.N(52), x0 = m + ws;   // colonne des numeros de semaine a gauche
      string[] jours = { "L", "M", "M", "J", "V", "S", "D" };
      using (var sf = new System.Drawing.StringFormat { Alignment = System.Drawing.StringAlignment.Center, LineAlignment = System.Drawing.StringAlignment.Center })
      using (var fW = VerreUI.Police(11, false)) using (var fWg = VerreUI.Police(11, true))
      using (var bg = new System.Drawing.SolidBrush(Blanc(170))) {
        for (int i = 0; i < 7; i++) g.DrawString(jours[i], fJ, bg, new System.Drawing.RectangleF(x0 + i * cw, y0, cw, VerreUI.N(24)), sf);
        int decal = ((int)mois.DayOfWeek + 6) % 7; var debut = mois.AddDays(-decal); float ch = VerreUI.N(38);
        for (int sem = 0; sem < 6; sem++) {
          var lundi = debut.AddDays(sem * 7); bool cette = DateTime.Today >= lundi && DateTime.Today < lundi.AddDays(7);
          var rw = new System.Drawing.RectangleF(m, y0 + VerreUI.N(26) + sem * ch, ws, ch);
          using (var b = new System.Drawing.SolidBrush(cette ? System.Drawing.Color.FromArgb(120, 185, 255) : Blanc(120))) g.DrawString(Semaine(lundi).ToString(), cette ? fWg : fW, b, rw, sf);
        }
        using (var p = new System.Drawing.Pen(Blanc(35), 1)) g.DrawLine(p, x0 - VerreUI.N(2), y0 + VerreUI.N(30), x0 - VerreUI.N(2), y0 + VerreUI.N(22) + 6 * ch);
        for (int k = 0; k < 42; k++) {
          var d = debut.AddDays(k); var r = new System.Drawing.RectangleF(x0 + (k % 7) * cw, y0 + VerreUI.N(26) + (k / 7) * ch, cw, ch);
          bool auj = d == DateTime.Today, dansMois = d.Month == mois.Month;
          if (auj) using (var b = new System.Drawing.SolidBrush(Bleu)) { float s = VerreUI.N(32); g.FillEllipse(b, r.X + (r.Width - s) / 2, r.Y + (r.Height - s) / 2, s, s); }
          using (var b = new System.Drawing.SolidBrush(auj ? Blanc(255) : dansMois ? Blanc(k % 7 >= 5 ? 215 : 245) : Blanc(105))) g.DrawString(d.Day.ToString(), auj ? fDg : fD, b, r, sf);
        }
      }
    }
    // --- notifications ---
    float y = VerreUI.N(318);
    using (var p = new System.Drawing.Pen(Blanc(40), 1)) g.DrawLine(p, m, y, L - m, y);
    using (var fH = VerreUI.Police(14, true)) using (var fL = VerreUI.Police(12.5, false)) using (var fA = VerreUI.Police(11.5, false)) using (var fT = VerreUI.Police(13, true)) using (var fC = VerreUI.Police(12.5, false)) {
      VerreUI.Texte(g, "Notifications", fH, Blanc(255), new System.Drawing.RectangleF(m, y + VerreUI.N(6), lu, VerreUI.N(32)), false);
      if (notifs.Count > 0) { var re = new System.Drawing.RectangleF(L - m - VerreUI.N(110), y + VerreUI.N(6), VerreUI.N(110), VerreUI.N(32)); VerreUI.Texte(g, "Tout effacer", fL, Blanc(190), re, true); zones.Add(Tuple.Create(re, "effacer")); }
      y += VerreUI.N(44);
      if (notifs.Count == 0) { VerreUI.Texte(g, "Aucune notification", fL, Blanc(175), new System.Drawing.RectangleF(m, y, lu, VerreUI.N(36)), false); y += VerreUI.N(44); }
      for (int i = 0; i < notifs.Count && i < MaxNotifs; i++) {
        var n = notifs[i]; var carte = new System.Drawing.RectangleF(m, y, lu, VerreUI.N(66));
        using (var b = new System.Drawing.SolidBrush(Blanc(26))) using (var pth = VerreUI.Rond(carte, VerreUI.N(12))) g.FillPath(b, pth);
        using (var pn = new System.Drawing.Pen(Blanc(30), 1)) using (var pth = VerreUI.Rond(carte, VerreUI.N(12))) g.DrawPath(pn, pth);
        var img = string.IsNullOrEmpty(n.Aumid) ? null : VerreUI.Icone(@"shell:AppsFolder\" + n.Aumid, VerreUI.N(32));
        if (img != null) g.DrawImage(img, carte.X + VerreUI.N(12), carte.Y + VerreUI.N(17), VerreUI.N(32), VerreUI.N(32));
        float xt = carte.X + VerreUI.N(54), lt = carte.Right - xt - VerreUI.N(12);
        VerreUI.Texte(g, n.App, fA, Blanc(185), new System.Drawing.RectangleF(xt, carte.Y + VerreUI.N(5), lt - VerreUI.N(80), VerreUI.N(18)), false);
        VerreUI.Texte(g, Quand(n.Date), fA, Blanc(185), new System.Drawing.RectangleF(carte.Right - VerreUI.N(92), carte.Y + VerreUI.N(5), VerreUI.N(80), VerreUI.N(18)), true);
        VerreUI.Texte(g, n.Titre, fT, Blanc(255), new System.Drawing.RectangleF(xt, carte.Y + VerreUI.N(23), lt, VerreUI.N(20)), false);
        VerreUI.Texte(g, n.Corps, fC, Blanc(210), new System.Drawing.RectangleF(xt, carte.Y + VerreUI.N(42), lt, VerreUI.N(20)), false);
        zones.Add(Tuple.Create(carte, "n:" + n.Id));
        y += VerreUI.N(74);
      }
      if (notifs.Count > MaxNotifs) { VerreUI.Texte(g, "+" + (notifs.Count - MaxNotifs) + " autres notifications", fA, Blanc(180), new System.Drawing.RectangleF(m, y - VerreUI.N(4), lu, VerreUI.N(26)), false); y += VerreUI.N(26); }
      using (var p = new System.Drawing.Pen(Blanc(40), 1)) g.DrawLine(p, m, y + VerreUI.N(2), L - m, y + VerreUI.N(2));
      var rw = new System.Drawing.RectangleF(m, y + VerreUI.N(6), lu, VerreUI.N(34));
      VerreUI.Texte(g, "Centre de notifications Windows…", fL, Blanc(230), rw, false); zones.Add(Tuple.Create(rw, "windows"));
    }
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
    EnvoyerBang(FondPastille(pVol, pLum) + "[!SetVariable Vol " + n + " \"MacWidgets\\Volume\"][!UpdateMeasure MesureVolume \"MacWidgets\\Volume\"]");
  }
  // pastilles volume / luminosite : meme verre que les panneaux (photo floutee du fond), prise seulement
  // au premier appui (pastille encore cachee) et jamais quand l'autre pastille occupe deja la place
  Panneau pVol = new Panneau { Nom = "Volume" }, pLum = new Panneau { Nom = "Luminosite" };
  string FondPastille(Panneau p, Panneau autre) {
    try {
      if (p.H == IntPtr.Zero || !IsWindow(p.H)) p.H = TrouverSkin(p.Nom + ".ini");
      if (autre.H == IntPtr.Zero || !IsWindow(autre.H)) autre.H = TrouverSkin(autre.Nom + ".ini");
      if (p.H == IntPtr.Zero || IsWindowVisible(p.H) || (autre.H != IntPtr.Zero && IsWindowVisible(autre.H))) return "";
      RECTP r; GetWindowRect(p.H, out r); p.Zone[4] = Math.Max(1, (r.b - r.t) / 2);   // forme de pilule
      string img = Verre(p);
      return img == "" ? "" : "[!SetVariable FondVerre \"" + img + "\" \"MacWidgets\\" + p.Nom + "\"]";
    } catch { return ""; }
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
            using (var voile = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(102, 24, 22, 30))) g.FillRectangle(voile, 0, 0, w, h);
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
    bool chercher = recherche++ % 20 == 0;
    if (recherche % 4 == 0) NomApplication();   // nom de l'application active, toutes les 0,5 s     // cherche les fenetres au plus toutes les 2,4 s
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
    if (agenda != null && agenda.Visible && ((clic && !clicAvant) || echap)) {
      bool surDate = pt.y < HauteurPhysique() && pt.x > GetSystemMetrics(0) - VerreUI.N(200);
      if (echap || (!agenda.Bounds.Contains(pt.x, pt.y) && !surDate)) agenda.Fermer();
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
  static void Journal(string s) { try { System.IO.File.AppendAllText(Dossier + "moteur_erreurs.log", DateTime.Now.ToString("dd/MM HH:mm:ss") + "  " + s + Environment.NewLine); } catch { } }
  void ActionCC(int c) { try { ActionCC2(c); } catch (Exception ex) { Journal("commande " + c + " : " + ex.ToString()); } }
  void ActionCC2(int c) {
    if (c == 1) Touche(0xB3); else if (c == 2) Touche(0xB0); else if (c == 3) Touche(0xB1);       // lecture/pause, suivant, precedent
    else if (c == 4) Executer("wifi"); else if (c == 5) Executer("bluetooth");
    else if (c == 10) { spot.Fermer(); agenda.Fermer(); Basculer(pBat); } else if (c == 11) { spot.Fermer(); agenda.Fermer(); Basculer(pCC); }
    else if (c == 12) { if (raccourciOk) { keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x20, 0, 0, UIntPtr.Zero); keybd_event(0x20, 0, 2, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero); } else OuvrirSpotlight(); }   // loupe : on passe par le raccourci
    else if (c == 13) OuvrirAgenda();
    else if (c == 14) { spot.Fermer(); agenda.Fermer(); FermerPanneauxRainmeter(); keybd_event(0x5B, 0, 1, UIntPtr.Zero); keybd_event(0x5B, 0, 3, UIntPtr.Zero); }   // logo : touche Windows (menu Demarrer)                          // icones de la barre
    else if (c == 6) { try { bool mu; Guid g = Guid.Empty; volPeriph.GetMute(out mu); volPeriph.SetMute(!mu, ref g); } catch { } }
    if (c <= 3) toursCC = 6;   // musique relue dans 0,5 s
  }
  void Touche(byte v) { keybd_event(v, 0, 1, UIntPtr.Zero); keybd_event(v, 0, 3, UIntPtr.Zero); }

  // --- Spotlight (Alt+Espace ou loupe) et calendrier + notifications (clic sur la date) ---
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
  Spotlight spot; Agenda agenda; bool raccourciOk;
  void CreerFenetres() {
    VerreUI.S = GetDeviceCaps(GetDC(IntPtr.Zero), 88) / 96.0;
    spot = new Spotlight(); spot.Commande = c => Commande != null ? Commande(c) : "";
    agenda = new Agenda(); agenda.Commande = c => Commande != null ? Commande(c) : "";
    agenda.Raccourci = t => { try { System.Diagnostics.Process.Start("wscript.exe", "\"" + Dossier + "lancer_invisible.vbs\" \"" + Dossier + "raccourci.ps1\" " + t); } catch { } };
    var prechargement = new System.Windows.Forms.Timer(); prechargement.Interval = 15000;
    prechargement.Tick += (s, e) => { prechargement.Stop(); spot.ChargerApps(); };   // liste des applications prete avant la premiere recherche
    prechargement.Start();
  }
  void FermerPanneauxRainmeter() { foreach (var a in new[] { pBat, pCC }) if (a.H != IntPtr.Zero && IsWindowVisible(a.H)) EnvoyerBang("[!Hide \"MacWidgets\\" + a.Nom + "\"]"); }
  void OuvrirSpotlight() { FermerPanneauxRainmeter(); agenda.Fermer(); spot.Ouvrir(); }
  void OuvrirAgenda() { FermerPanneauxRainmeter(); spot.Fermer(); agenda.Ouvrir(GetSystemMetrics(0) - VerreUI.N(8), HauteurPhysique() + VerreUI.N(6)); }

  // --- nom de l'application au premier plan, a la place de « Bureau » (comme le menu en gras du Mac) ---
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int p);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumCB cb, IntPtr l);
  string nomApp = ""; IntPtr fenAvant = IntPtr.Zero;
  void NomApplication() {
    IntPtr h = GetForegroundWindow(); if (h == IntPtr.Zero || h == fenAvant) return; fenAvant = h;
    string nom = null;
    try {
      var cl = new System.Text.StringBuilder(256); GetClassName(h, cl, 256); string c = cl.ToString();
      int pid; GetWindowThreadProcessId(h, out pid); var p = System.Diagnostics.Process.GetProcessById(pid); string pn = p.ProcessName.ToLower();
      if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") nom = "Bureau";
      else if (pn == "rainmeter" || pid == System.Diagnostics.Process.GetCurrentProcess().Id || pn == "searchhost" || pn == "startmenuexperiencehost" || pn == "shellexperiencehost" || pn == "shellhost" || pn == "lockapp") return;   // nos panneaux, menus de Windows : on garde le nom
      else {
        if (pn == "applicationframehost") {   // applications du Microsoft Store : le vrai programme est dans une fenetre enfant
          int enfant = 0; EnumChildWindows(h, (e, l) => { int q; GetWindowThreadProcessId(e, out q); if (q != pid) { enfant = q; return false; } return true; }, IntPtr.Zero);
          if (enfant != 0) { p = System.Diagnostics.Process.GetProcessById(enfant); pn = p.ProcessName.ToLower(); }
        }
        if (pn == "explorer") nom = "Explorateur";
        else {
          try {
            var v = p.MainModule.FileVersionInfo; string d = (v.FileDescription ?? "").Trim(), pr = (v.ProductName ?? "").Trim();
            nom = (pr.Length > 0 && !pr.Contains("Windows") && (d.Length == 0 || pr.Length <= d.Length)) ? pr : d;
          } catch { }
          if (string.IsNullOrEmpty(nom)) nom = p.ProcessName;
        }
      }
    } catch { return; }
    nom = nom.Replace("\"", "").Replace("®", "").Replace("™", "").Trim(); if (nom.Length > 28) nom = nom.Substring(0, 28).Trim();
    if (nom.Length == 0 || nom == nomApp) return; nomApp = nom;
    EnvoyerBang("[!SetVariable NomApp \"" + nom + "\" \"MacWidgets\\BarreMenus\"][!UpdateMeter * \"MacWidgets\\BarreMenus\"][!Redraw \"MacWidgets\\BarreMenus\"]");
  }

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
          EnvoyerBang(FondPastille(pLum, pVol) + "[!SetVariable Lum " + v + " \"MacWidgets\\Luminosite\"][!UpdateMeasure MesureLum \"MacWidgets\\Luminosite\"]");
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
    CreerFenetres();
    minuteurPanneau = new System.Windows.Forms.Timer(); minuteurPanneau.Interval = 120; minuteurPanneau.Tick += SurveillerPanneau; minuteurPanneau.Start();
  }
  protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x80 | 0x08000000; return p; } }
  protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Inscrire(); raccourciOk = RegisterHotKey(Handle, 1, 0x4001, 0x20); }   // Alt+Espace = Spotlight
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
    else if (m.Msg == 0x0312 && (int)m.WParam == 1) { try { OuvrirSpotlight(); } catch (Exception ex) { Journal("spotlight : " + ex); } }   // raccourci Alt+Espace (Windows autorise la prise du clavier)
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
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Management, System.Data, System.Xml -TypeDefinition $code
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
# Spotlight (liste des applications) et notifications (API WinRT UserNotificationListener, sans droits administrateur)
$null = [Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
function Notifs {
  $l = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
  $liste = Attendre ($l.GetNotificationsAsync([Windows.UI.Notifications.NotificationKinds]::Toast)) ([System.Collections.Generic.IReadOnlyList[Windows.UI.Notifications.UserNotification]])
  $lignes = foreach ($n in @($liste)) {
    try {
      $b = $n.Notification.Visual.GetBinding([Windows.UI.Notifications.KnownNotificationBindings]::ToastGeneric)
      $t = @($b.GetTextElements() | ForEach-Object { ($_.Text -replace "[\t\r\n]+", ' ').Trim() } | Where-Object { $_ })
      $app = ''; $aumid = ''; try { $app = $n.AppInfo.DisplayInfo.DisplayName; $aumid = $n.AppInfo.AppUserModelId } catch { }
      $titre = if ($t.Count) { $t[0] } else { $app }
      "$($n.Id)`t$app`t$titre`t$(($t | Select-Object -Skip 1) -join ' · ')`t$($n.CreationTime.ToString('o'))`t$aumid"
    } catch { }
  }
  $lignes -join "`n"
}
[BarreReservee]::Commande = [Func[string, string]] {
  param($c)
  switch ($c) {
    'etat' { EtatRadios }
    'wifi' { Basculer 'WiFi' }
    'bluetooth' { Basculer 'Bluetooth' }
    'musique' { Musique $false }
    'musique-force' { Musique $true }
    'apps' { (Get-StartApps | ForEach-Object { "$($_.Name)`t$($_.AppID)" }) -join "`n" }
    'notifs' { Notifs }
    'notif-effacer' {   # ClearNotifications echoue (0x80070490) : on supprime une par une
      $l = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
      $liste = Attendre ($l.GetNotificationsAsync([Windows.UI.Notifications.NotificationKinds]::Toast)) ([System.Collections.Generic.IReadOnlyList[Windows.UI.Notifications.UserNotification]])
      foreach ($n in @($liste)) { try { $l.RemoveNotification($n.Id) } catch { } }; '' }
    default { if ($c -like 'notif-suppr:*') { [Windows.UI.Notifications.Management.UserNotificationListener]::Current.RemoveNotification([uint32]$c.Substring(12)) }; '' }
  }
}
[BarreReservee]::Lancer($Hauteur)
