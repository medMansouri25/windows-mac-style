# raccourci.ps1 : simule un raccourci Windows (les panneaux ouverts ainsi ont le focus et se ferment au clic exterieur)
#   A = centre de controle, N = notifications, S = recherche, Demarrer = menu Demarrer
param([string]$Touche = 'A')
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Tch { [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e); [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t); [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l); }'
# menu Demarrer : on le demande directement a la barre des taches (WM_SYSCOMMAND / SC_TASKLIST)
if ($Touche -eq 'Demarrer') { [Tch]::PostMessage([Tch]::FindWindow('Shell_TrayWnd', $null), 0x0112, [IntPtr]0xF130, [IntPtr]::Zero) | Out-Null; return }
$vk = [byte][char]$Touche.ToUpper()
[Tch]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); [Tch]::keybd_event($vk,0,0,[UIntPtr]::Zero)
[Tch]::keybd_event($vk,0,2,[UIntPtr]::Zero); [Tch]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
