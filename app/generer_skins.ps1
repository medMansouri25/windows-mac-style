# =============================================================================
#  generer_skins.ps1  -  cree la barre des menus + pastilles volume/luminosite
#  adaptees a l'ecran du PC (echelle d'affichage, largeur, batterie ou non).
#  Les fichiers sont crees dans  Documents\Rainmeter\Skins\MacWidgets
#  Relancer ce script apres un changement d'ecran ou d'echelle d'affichage.
# =============================================================================
param([string]$App = $PSScriptRoot, [string]$Skins = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\MacWidgets'))

$config = Get-Content (Join-Path $App 'config.json') -Raw | ConvertFrom-Json
$H = [double]$config.barre.hauteur
$nomMenu = $config.barre.nomMenuPrincipal

# --- Mesures de l'ecran principal (en pixels reels) ---
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class EcranInfo { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h); [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr h, int i); [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i); }' -ErrorAction SilentlyContinue
[EcranInfo]::SetProcessDPIAware() | Out-Null
$dpi = [EcranInfo]::GetDeviceCaps([EcranInfo]::GetDC([IntPtr]::Zero), 88)
$S = $dpi / 96.0                                     # echelle (1.0 = 100 %, 1.5 = 150 %...)
$largeur = [EcranInfo]::GetSystemMetrics(0)          # largeur en pixels reels
$aBatterie = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

function n($v) { [string][int][math]::Round($v * $S) }
function f($v) { ([math]::Round($v * $S, 1)).ToString([Globalization.CultureInfo]::InvariantCulture) }
$hp = n $H; $cy = n ($H / 2)
$lanceur = Join-Path $App 'lancer_invisible.vbs'
$raccourci = Join-Path $App 'raccourci.ps1'
$guide = Join-Path $App 'GUIDE.txt'
foreach ($d in 'BarreMenus','Volume','Luminosite') { New-Item -ItemType Directory -Force (Join-Path $Skins $d) | Out-Null }
function Ecrire($chemin, $texte) { [IO.File]::WriteAllText($chemin, $texte, [Text.Encoding]::Unicode) }

# ------------------------------- Barre des menus -------------------------------
$batterie = ''
if ($aBatterie) {
$batterie = @"

[BatterieIcone]
Meter=Shape
X=(#SCREENAREAWIDTH#-$(n 276))
Y=$(n 8.7)
Shape=Rectangle 0,0,$(n 26),$(n 12.5),$(n 3.6) | Fill Color 0,0,0,1 | StrokeWidth $(n 1.1) | Stroke Color #CoulBat#
Shape2=Rectangle $(n 27.3),$(n 4),$(n 2),$(n 4.5),$(n 1) | Fill Color #CoulBat# | StrokeWidth 0
Shape3=Rectangle $(n 2),$(n 2),(Max([MesureBatterie],4)*$(n 22)/100),$(n 8.5),$(n 2) | Fill Color #CoulBat# | StrokeWidth 0
Shape4=Path Eclair | Fill Color #EclairFond# | StrokeWidth $(f 0.8) | Stroke Color #EclairBord# | StrokeLineJoin Round
Eclair=$(f 14.4),$(f 1.5) | LineTo $(f 9.5),$(f 7.3) | LineTo $(f 12.6),$(f 7.3) | LineTo $(f 11.6),$(f 11.2) | LineTo $(f 16.5),$(f 5.3) | LineTo $(f 13.4),$(f 5.3) | ClosePath 1
DynamicVariables=1
LeftMouseUpAction=["ms-settings:batterysaver"]
ToolTipText=#InfoBat#

[BatteriePct]
Meter=String
MeterStyle=StyleMenu
MeasureName=MesureBatterie
StringAlign=RightCenter
X=(#SCREENAREAWIDTH#-$(n 288))
Text=%1 %
LeftMouseUpAction=["ms-settings:batterysaver"]
DynamicVariables=1
"@
}
$mesuresBatterie = if ($aBatterie) { @"

[MesureBatterie]
Measure=Plugin
Plugin=PowerPlugin
PowerState=Percent

[MesureSecteur]
Measure=Plugin
Plugin=PowerPlugin
PowerState=ACLine

[MesureScript]
Measure=Script
ScriptFile=#CURRENTPATH#batterie.lua
"@ } else { '' }

$barre = @"
[Rainmeter]
Update=1000
AccurateText=1
OnRefreshAction=[!KeepOnScreen "0"][!SnapEdges "0"][!Draggable "0"][!Move "0" "0"]

[Metadata]
Name=Barre des menus
Information=Barre fine en haut de l'ecran, facon Mac. Genere par generer_skins.ps1 (echelle $S, largeur $largeur px).

[Variables]
Police=Segoe UI Variable Text
Icones=Segoe Fluent Icons
Txt=255,255,255,255
Survol=255,255,255,45
Rien=0,0,0,1
Economie=0
WifiNiv=4
WifiInfo=Wi-Fi
EnCharge=0
EclairFond=0,0,0,0
EclairBord=0,0,0,0
CoulBat=255,255,255,255
InfoBat=Batterie
InfoNormal=Batterie
InfoCharge=Batterie en charge
InfoEco=Mode économie actif
InfoPause=Branché – recharge en pause (limite de charge)
InfoChargeEco=En charge – économie d'énergie activée
Start="wscript.exe" "$(Join-Path $App 'lancer_invisible.vbs')" "$(Join-Path $App 'raccourci.ps1')" "Demarrer"

[MesureDate]
Measure=Time
Format=%a %#d %b
FormatLocale=fr-FR

[MesureHeure]
Measure=Time
Format=%H:%M
$mesuresBatterie

[Fond]
Meter=Shape
Shape=Rectangle 0,0,#SCREENAREAWIDTH#,$hp | Fill Color 16,14,26,70 | StrokeWidth 0

[StyleMenu]
FontFace=#Police#
FontSize=$(n 10)
FontWeight=600
FontColor=#Txt#
AntiAlias=1
StringAlign=LeftCenter
Y=$cy
SolidColor=#Rien#
Padding=$(n 8),$(n 3),$(n 8),$(n 3)
MouseOverAction=[!SetOption #CURRENTSECTION# SolidColor #Survol#][!UpdateMeter #CURRENTSECTION#][!Redraw]
MouseLeaveAction=[!SetOption #CURRENTSECTION# SolidColor #Rien#][!UpdateMeter #CURRENTSECTION#][!Redraw]

[StyleIcone]
FontFace=#Icones#
FontSize=$(n 10.5)
FontColor=#Txt#
AntiAlias=1
StringAlign=CenterCenter
Y=$(n 16)
SolidColor=#Rien#
Padding=$(n 6),$(n 4),$(n 6),$(n 4)
MouseOverAction=[!SetOption #CURRENTSECTION# SolidColor #Survol#][!UpdateMeter #CURRENTSECTION#][!Redraw]
MouseLeaveAction=[!SetOption #CURRENTSECTION# SolidColor #Rien#][!UpdateMeter #CURRENTSECTION#][!Redraw]

[ZoneLogo]
Meter=Shape
X=$(n 8)
Y=$(n 3)
Shape=Rectangle 0,0,$(n 30),$(n 24),$(n 5) | Fill Color #Rien# | StrokeWidth 0
Shape2=Rectangle $(n 8.5),$(n 5.5),$(n 6),$(n 6),$(n 0.8) | Fill Color #Txt# | StrokeWidth 0
Shape3=Rectangle $(n 15.5),$(n 5.5),$(n 6),$(n 6),$(n 0.8) | Fill Color #Txt# | StrokeWidth 0
Shape4=Rectangle $(n 8.5),$(n 12.5),$(n 6),$(n 6),$(n 0.8) | Fill Color #Txt# | StrokeWidth 0
Shape5=Rectangle $(n 15.5),$(n 12.5),$(n 6),$(n 6),$(n 0.8) | Fill Color #Txt# | StrokeWidth 0
LeftMouseUpAction=[#Start#]
MouseOverAction=[!SetOption ZoneLogo Shape "Rectangle 0,0,$(n 30),$(n 24),$(n 5) | Fill Color #Survol# | StrokeWidth 0"][!UpdateMeter ZoneLogo][!Redraw]
MouseLeaveAction=[!SetOption ZoneLogo Shape "Rectangle 0,0,$(n 30),$(n 24),$(n 5) | Fill Color #Rien# | StrokeWidth 0"][!UpdateMeter ZoneLogo][!Redraw]
ToolTipText=Toutes les applications

[MenuApp]
Meter=String
MeterStyle=StyleMenu
FontWeight=700
X=$(n 42)
Text=$nomMenu
LeftMouseUpAction=[shell:::{3080F90D-D7AD-11D9-BD98-0000947B0257}]
ToolTipText=Afficher le bureau

[MenuFichiers]
Meter=String
MeterStyle=StyleMenu
X=0R
Text=Fichiers
LeftMouseUpAction=["explorer.exe"]

[MenuApps]
Meter=String
MeterStyle=StyleMenu
X=0R
Text=Applications
LeftMouseUpAction=[#Start#]

[MenuReglages]
Meter=String
MeterStyle=StyleMenu
X=0R
Text=Réglages
LeftMouseUpAction=["ms-settings:"]

[MenuAide]
Meter=String
MeterStyle=StyleMenu
X=0R
Text=Aide
LeftMouseUpAction=["$guide"]

[DateHeure]
Meter=String
MeterStyle=StyleMenu
MeasureName=MesureDate
MeasureName2=MesureHeure
StringAlign=RightCenter
InlineSetting=Case | Proper
X=(#SCREENAREAWIDTH#-$(n 6))
Text=%1  %2
LeftMouseUpAction=["wscript.exe" "$lanceur" "$raccourci" "N"]
ToolTipText=Notifications et calendrier

[CentreControle]
Meter=String
MeterStyle=StyleIcone
X=(#SCREENAREAWIDTH#-$(n 168))
Text=[\xE9E9]
LeftMouseUpAction=["wscript.exe" "$lanceur" "$raccourci" "A"]
ToolTipText=Centre de contrôle (son, wifi, luminosité)

[Recherche]
Meter=String
MeterStyle=StyleIcone
X=(#SCREENAREAWIDTH#-$(n 196))
Text=[\xE721]
LeftMouseUpAction=["wscript.exe" "$lanceur" "$raccourci" "S"]
ToolTipText=Rechercher (comme Spotlight)

[MesureWifi]
; niveau envoye par barre_reservee.ps1 (0 = pas de connexion, 1 a 4 = arcs allumes)
Measure=Calc
Formula=#WifiNiv#
DynamicVariables=1
IfCondition=MesureWifi = 0
IfTrueAction=[!HideMeterGroup WifiNiv][!ShowMeter WifiCoupe][!Redraw]
IfCondition2=MesureWifi = 1
IfTrueAction2=[!HideMeterGroup WifiNiv][!ShowMeter Wifi][!ShowMeter Wifi1][!Redraw]
IfCondition3=MesureWifi = 2
IfTrueAction3=[!HideMeterGroup WifiNiv][!ShowMeter Wifi][!ShowMeter Wifi2][!Redraw]
IfCondition4=MesureWifi = 3
IfTrueAction4=[!HideMeterGroup WifiNiv][!ShowMeter Wifi][!ShowMeter Wifi3][!Redraw]
IfCondition5=MesureWifi = 4
IfTrueAction5=[!HideMeterGroup WifiNiv][!ShowMeter Wifi][!ShowMeter Wifi4][!Redraw]

[Wifi]
Meter=String
Group=WifiNiv
MeterStyle=StyleIcone
X=(#SCREENAREAWIDTH#-$(n 224))
FontColor=255,255,255,85
Text=[\xE701]
LeftMouseUpAction=["ms-availablenetworks:"]
ToolTipText=#WifiInfo#
DynamicVariables=1

[Wifi1]
Meter=String
Group=WifiNiv
FontFace=#Icones#
FontSize=$(n 10.5)
FontColor=#Txt#
AntiAlias=1
StringAlign=CenterCenter
X=(#SCREENAREAWIDTH#-$(n 224))
Y=$(n 16)
Padding=$(n 6),$(n 4),$(n 6),$(n 4)
Text=[\xE872]
Hidden=1

[Wifi2]
Meter=String
Group=WifiNiv
FontFace=#Icones#
FontSize=$(n 10.5)
FontColor=#Txt#
AntiAlias=1
StringAlign=CenterCenter
X=(#SCREENAREAWIDTH#-$(n 224))
Y=$(n 16)
Padding=$(n 6),$(n 4),$(n 6),$(n 4)
Text=[\xE873]
Hidden=1

[Wifi3]
Meter=String
Group=WifiNiv
FontFace=#Icones#
FontSize=$(n 10.5)
FontColor=#Txt#
AntiAlias=1
StringAlign=CenterCenter
X=(#SCREENAREAWIDTH#-$(n 224))
Y=$(n 16)
Padding=$(n 6),$(n 4),$(n 6),$(n 4)
Text=[\xE874]
Hidden=1

[Wifi4]
Meter=String
Group=WifiNiv
FontFace=#Icones#
FontSize=$(n 10.5)
FontColor=#Txt#
AntiAlias=1
StringAlign=CenterCenter
X=(#SCREENAREAWIDTH#-$(n 224))
Y=$(n 16)
Padding=$(n 6),$(n 4),$(n 6),$(n 4)
Text=[\xE701]
Hidden=1

[WifiCoupe]
Meter=String
Group=WifiNiv
MeterStyle=StyleIcone
X=(#SCREENAREAWIDTH#-$(n 224))
FontColor=255,255,255,170
Text=[\xEB5E]
LeftMouseUpAction=["ms-availablenetworks:"]
ToolTipText=#WifiInfo#
DynamicVariables=1
Hidden=1
$batterie
"@
Ecrire (Join-Path $Skins 'BarreMenus\BarreMenus.ini') $barre
Copy-Item (Join-Path $App 'batterie.lua') (Join-Path $Skins 'BarreMenus\batterie.lua') -Force

# --------------------------- Pastilles volume / luminosite ---------------------------
$largPastille = n 248; $hautPastille = n 35
$px = [int](($largeur - [int]$largPastille) / 2); $py = [int]$hp + [int](n 8)
function Pastille($nom, $icone, $mesures, $sourceValeur) {
@"
[Rainmeter]
Update=__UPDATE__
AccurateText=1
OnRefreshAction=[!Move "$px" "$py"][!ZPos "2"][!ClickThrough "1"][!Draggable "0"][!Hide]

[Metadata]
Name=$nom facon Apple
Information=Pastille sous la barre des menus. Apparait au changement, disparait seule.

[Variables]
Icones=Segoe Fluent Icons
Police=Segoe UI Variable Text
$mesures

[Minuteur]
Measure=Plugin
Plugin=ActionTimer
ActionList1=Wait 1600 | Masquer
Masquer=[!Hide]

[Fond]
Meter=Shape
UpdateDivider=-1
Shape=Rectangle 1,1,$([int]$largPastille-2),$([int]$hautPastille-2),$([math]::Round(([int]$hautPastille-2)/2)) | Fill Color 30,28,38,225 | StrokeWidth $(f 1) | Stroke Color 255,255,255,45

[Icone]
Meter=String
UpdateDivider=-1
FontFace=#Icones#
FontSize=$(n 11.3)
FontColor=255,255,255,255
AntiAlias=1
StringAlign=CenterCenter
X=$(n 26.7)
Y=$(n 17.3)
Text=[\x$icone]

[Piste]
Meter=Shape
UpdateDivider=-1
X=$(n 48)
Y=$(n 14.7)
Shape=Rectangle 0,0,$(n 133.3),$(n 5.3),$(n 2.7) | Fill Color 255,255,255,60 | StrokeWidth 0

[Remplissage]
Meter=Shape
UpdateDivider=-1
X=$(n 48)
Y=$(n 14.7)
Shape=Rectangle 0,0,(Max([MesureAffiche],0)*$(f 1.333)),$(n 5.3),$(n 2.7) | Fill Color 255,255,255,255 | StrokeWidth 0
DynamicVariables=1

[Pourcent]
Meter=String
UpdateDivider=-1
MeasureName=MesureAffiche
FontFace=#Police#
FontSize=$(n 8.7)
FontWeight=600
FontColor=255,255,255,255
AntiAlias=1
StringAlign=RightCenter
X=$(n 229.3)
Y=$(n 17.3)
Text=%1 %
"@
}
$montrer = "[!UpdateMeasure MesureAffiche][!UpdateMeter *][!Redraw][!Move `"$px`" `"$py`"][!ZPos `"2`"][!Show][!CommandMeasure Minuteur `"Stop 1`"][!CommandMeasure Minuteur `"Execute 1`"]"
$mesVolume = @"
Vol=-2

[MesureVolume]
; valeur envoyee par barre_reservee.ps1 quand Windows signale un changement (-1 = muet)
Measure=Calc
Formula=#Vol#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MesureVolume >= -1
IfTrueAction=$montrer
IfConditionMode=1

[MesureAffiche]
Measure=Calc
Formula=Clamp(MesureVolume, 0, 100)
UpdateDivider=-1
IfCondition=MesureVolume < 0
IfTrueAction=[!SetOption Icone Text "[\xE74F]"]
IfCondition2=(MesureVolume >= 0) && (MesureVolume < 34)
IfTrueAction2=[!SetOption Icone Text "[\xE993]"]
IfCondition3=(MesureVolume >= 34) && (MesureVolume < 67)
IfTrueAction3=[!SetOption Icone Text "[\xE994]"]
IfCondition4=MesureVolume >= 67
IfTrueAction4=[!SetOption Icone Text "[\xE995]"]
"@
$mesLum = @"
Lum=-1

[MesureLum]
Measure=Calc
Formula=#Lum#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MesureLum >= 0
IfTrueAction=$montrer
IfConditionMode=1

[MesureAffiche]
Measure=Calc
Formula=Clamp(MesureLum, 0, 100)
UpdateDivider=-1
"@
Ecrire (Join-Path $Skins 'Volume\Volume.ini') ((Pastille 'Volume' 'E995' $mesVolume).Replace('__UPDATE__','1000'))
Ecrire (Join-Path $Skins 'Luminosite\Luminosite.ini') ((Pastille 'Luminosite' 'E706' $mesLum).Replace('__UPDATE__','1000'))

[pscustomobject]@{ Echelle = $S; LargeurPx = $largeur; Batterie = $aBatterie; PastilleX = $px; PastilleY = $py; BarrePx = $hp }
