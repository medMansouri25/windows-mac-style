# Change la frequence de rafraichissement de l'ecran principal (sans toucher a la resolution ni a la luminosite).
param([int]$Hz = 0, [switch]$Lister)
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public class Frequence {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr param);
  static DEVMODE Nouveau() { var d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return d; }
  public static int Actuelle(string dev) { var d = Nouveau(); EnumDisplaySettings(dev, -1, ref d); return d.dmDisplayFrequency; }
  public static List<int> Disponibles(string dev) {
    var cur = Nouveau(); EnumDisplaySettings(dev, -1, ref cur);
    var l = new List<int>(); var d = Nouveau();
    for (int i = 0; EnumDisplaySettings(dev, i, ref d); i++)
      if (d.dmPelsWidth == cur.dmPelsWidth && d.dmPelsHeight == cur.dmPelsHeight && !l.Contains(d.dmDisplayFrequency)) l.Add(d.dmDisplayFrequency);
    l.Sort(); return l;
  }
  public static int Appliquer(string dev, int hz) {
    var d = Nouveau(); EnumDisplaySettings(dev, -1, ref d);
    if (d.dmDisplayFrequency == hz) return 0;
    d.dmDisplayFrequency = hz; d.dmFields = 0x400000;
    return ChangeDisplaySettingsEx(dev, ref d, IntPtr.Zero, 0x01, IntPtr.Zero);
  }
}
'@ -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms
$ecran = ([System.Windows.Forms.Screen]::AllScreens | Where-Object Primary | Select-Object -First 1).DeviceName
if ($Lister) { "Ecran $ecran : actuel $([Frequence]::Actuelle($ecran)) Hz ; disponibles : $(([Frequence]::Disponibles($ecran)) -join ', ') Hz"; return }
if ($Hz -gt 0) {
  $dispo = [Frequence]::Disponibles($ecran)
  if ($dispo -notcontains $Hz) { $Hz = ($dispo | Sort-Object { [math]::Abs($_ - $Hz) } | Select-Object -First 1) }
  $r = [Frequence]::Appliquer($ecran, $Hz)
  "Ecran $ecran -> $Hz Hz (code $r)"
}
