param([string]$Touche = 'A')
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Tch { [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e); }'
$vk = [byte][char]$Touche.ToUpper()
[Tch]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); [Tch]::keybd_event($vk,0,0,[UIntPtr]::Zero)
[Tch]::keybd_event($vk,0,2,[UIntPtr]::Zero); [Tch]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
