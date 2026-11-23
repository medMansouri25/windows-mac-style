# =============================================================================
#  installer_conservation.ps1  -  (administrateur) prepare le mode conservation sans fenetre Oui/Non
#  Appele par installer.ps1, ou seul :  installer_conservation.ps1 -Source <dossier app> -Utilisateur <DOMAINE\nom>
#  - copie conservation_admin.ps1 dans C:\Program Files\InterfaceMac (reserve aux administrateurs)
#  - cree C:\ProgramData\InterfaceMac (administrateurs : ecriture ; utilisateurs : lecture seule)
#  - cree deux taches a parametres fixes : « Interface Mac - conservation On » / « ... Off »
#  Rien n'est installe si le PC n'a pas le reglage HP « Battery Health Manager ».
# =============================================================================
param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Utilisateur, [switch]$Retirer)
$ErrorActionPreference = 'Stop'
$prog = Join-Path $env:ProgramFiles 'InterfaceMac'
$donnees = Join-Path $env:ProgramData 'InterfaceMac'
$taches = 'Interface Mac - conservation On', 'Interface Mac - conservation Off'

if ($Retirer) {
  foreach ($t in $taches) { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
  Remove-Item $prog, $donnees -Recurse -Force -ErrorAction SilentlyContinue
  'retire'; return
}

$hp = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSetting -Filter "Name='Battery Health Manager'" -ErrorAction SilentlyContinue
if (-not $hp) { 'non HP : rien a installer'; return }

New-Item -ItemType Directory -Force $prog | Out-Null      # Program Files : seuls les administrateurs peuvent ecrire
Copy-Item (Join-Path $Source 'conservation_admin.ps1') $prog -Force

New-Item -ItemType Directory -Force $donnees | Out-Null
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)                # pas d'heritage : droits explicites
$h = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'; $p = [System.Security.AccessControl.PropagationFlags]::None
foreach ($sid in 'S-1-5-32-544', 'S-1-5-18') { $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule((New-Object System.Security.Principal.SecurityIdentifier $sid), 'FullControl', $h, $p, 'Allow'))) }
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule((New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-545'), 'ReadAndExecute', $h, $p, 'Allow')))
Set-Acl $donnees $acl

$script = Join-Path $prog 'conservation_admin.ps1'
$reglages = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
$principal = New-ScheduledTaskPrincipal -UserId $Utilisateur -LogonType Interactive -RunLevel Highest
foreach ($e in 'On', 'Off') {
  $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`" -Etat $e"
  Register-ScheduledTask -TaskName "Interface Mac - conservation $e" -Action $action -Principal $principal -Settings $reglages -Description "Regle seulement « Battery Health Manager » (BIOS HP) sur $e" -Force | Out-Null
}
'installe'
