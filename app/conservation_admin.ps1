# =============================================================================
#  conservation_admin.ps1 -Etat On|Off  -  partie ADMINISTRATEUR du mode conservation (PC HP)
#  Installe dans  C:\Program Files\InterfaceMac  (modifiable seulement par un administrateur)
#  et lance par les taches « Interface Mac - conservation On / Off » (parametres fixes).
#  Ne fait qu'une chose : regler « Battery Health Manager » dans le BIOS HP.
#  Le resultat va dans C:\ProgramData\InterfaceMac (dossier protege, pas un dossier de l'utilisateur).
# =============================================================================
param([ValidateSet('On', 'Off')][string]$Etat = 'On')
$resultat = Join-Path $env:ProgramData 'InterfaceMac\conservation.txt'
try {
  $interface = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSettingInterface -ErrorAction Stop
  $r = Invoke-CimMethod -InputObject $interface -MethodName SetBIOSSetting -Arguments @{ Name = 'Battery Health Manager'; Value = "Maximize my battery health $Etat"; Password = '<utf-16/>' }
  $lu = (Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSetting -Filter "Name='Battery Health Manager'").CurrentValue
  Set-Content $resultat "$($r.Return)|$lu" -Encoding UTF8
} catch { Set-Content $resultat "erreur|$($_.Exception.Message)" -Encoding UTF8 }
