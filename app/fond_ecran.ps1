# Applique une image comme fond d'ecran (API officielle de Windows : sur tous les ecrans, mode "Remplir").
param([Parameter(Mandatory)][string]$Image)
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
  void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
  [return: MarshalAs(UnmanagedType.U4)] uint GetMonitorDevicePathCount();
  void GetMonitorRECT(); void SetBackgroundColor(uint color); uint GetBackgroundColor();
  void SetPosition(int position); int GetPosition();
}
[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")] public class DesktopWallpaperClass { }
public static class FondMac { public static void Mettre(string p) { var w = (IDesktopWallpaper)new DesktopWallpaperClass(); w.SetPosition(4); w.SetWallpaper(null, p); } }
'@ -ErrorAction SilentlyContinue
[FondMac]::Mettre((Resolve-Path $Image).Path)
