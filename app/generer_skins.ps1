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
$infos = Join-Path $App 'infos_batterie.ps1'
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
LeftMouseUpAction=[!CommandMeasure MesureMoteur "SendMessage 32769 10 0"]["wscript.exe" "$lanceur" "$infos"]
ToolTipText=#InfoBat#

[BatteriePct]
Meter=String
MeterStyle=StyleMenu
MeasureName=MesureBatterie
StringAlign=RightCenter
X=(#SCREENAREAWIDTH#-$(n 288))
Text=%1 %
LeftMouseUpAction=[!CommandMeasure MesureMoteur "SendMessage 32769 10 0"]["wscript.exe" "$lanceur" "$infos"]
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
NomApp=$nomMenu
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
Start=!CommandMeasure MesureMoteur "SendMessage 32769 14 0"

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
Text=#NomApp#
DynamicVariables=1
LeftMouseUpAction=[shell:::{3080F90D-D7AD-11D9-BD98-0000947B0257}]
ToolTipText=Afficher le bureau

[MenuFichiers]
Meter=String
MeterStyle=StyleMenu
X=0R
Text=Fichiers
LeftMouseUpAction=["explorer.exe"]

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
LeftMouseUpAction=[!CommandMeasure MesureMoteur "SendMessage 32769 13 0"]
ToolTipText=Calendrier et notifications

[CentreControle]
Meter=String
MeterStyle=StyleIcone
X=(#SCREENAREAWIDTH#-$(n 168))
Text=[\xE9E9]
LeftMouseUpAction=[!CommandMeasure MesureMoteur "SendMessage 32769 11 0"]
ToolTipText=Centre de contrôle

[Recherche]
Meter=String
MeterStyle=StyleIcone
X=(#SCREENAREAWIDTH#-$(n 196))
Text=[\xE721]
LeftMouseUpAction=[!CommandMeasure MesureMoteur "SendMessage 32769 12 0"]
ToolTipText=Spotlight (Alt + Espace)

[MesureMoteur]
; ouvre les panneaux via barre_reservee.ps1 (fenetre InterfaceMacMoteur)
Measure=Plugin
Plugin=WindowMessagePlugin
WindowName=InterfaceMacMoteur
UpdateDivider=-1

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

# ------------------------- Panneau batterie (clic sur l'icone) -------------------------
if ($aBatterie) {
New-Item -ItemType Directory -Force (Join-Path $Skins 'PanneauBatterie') | Out-Null
$etat = Join-Path $Skins 'PanneauBatterie\etat.inc'   # dans le skin : Rainmeter n'ecrit que dans ses dossiers
if (-not (Test-Path $etat)) { Ecrire $etat "[Variables]`r`nEcoForce=auto`r`nConservation=inconnu`r`n" }
$conservation = Join-Path $App 'conservation.ps1'
$pW = n 300; $pH = n 286
$panX = [math]::Max(0, $largeur - [int](n 276) + [int](n 36) - [int]$pW); $panY = [int]$hp + [int](n 6)
# zone de l'icone (un clic dessus ouvre/ferme deja le panneau) + rayon des coins, lus par barre_reservee.ps1
Set-Content (Join-Path $App 'zone_batterie.txt') ("{0},{1},0,{2},{3}" -f ($largeur - [int](n 330)), ($largeur - [int](n 276) + [int](n 34)), $hp, (n 14))
$segW = 268 / 3
function Segment($nom, $i, $texte, $valeur) {
  $x = 16 + $i * $segW
@"

[Seg$nom]
Meter=Shape
X=$(n ($x + 2))
Y=$(n 156)
Shape=Rectangle 0,0,$(n ($segW - 4)),$(n 22),$(n 6) | Fill Color #F$nom# | StrokeWidth 0
DynamicVariables=1
LeftMouseUpAction=[!SetVariable EcoForce $valeur][!WriteKeyValue Variables EcoForce $valeur "$etat"][!UpdateMeasure MesureEcoForce][!UpdateMeter *][!Redraw]

[SegTexte$nom]
Meter=String
MeterStyle=StyleTexte
X=$(n ($x + $segW / 2))
Y=$(n 167)
StringAlign=CenterCenter
FontSize=$(n 8.3)
FontColor=#T$nom#
Text=$texte
DynamicVariables=1
"@
}
function Ligne($y) { "`r`n[Sep$y]`r`nMeter=Shape`r`nX=$(n 16)`r`nY=$(n $y)`r`nShape=Rectangle 0,0,$(n 268),$(f 1),0 | Fill Color 255,255,255,40 | StrokeWidth 0`r`n" }
function Rangee($nom, $y, $libelle, $var) {
@"

[Lib$nom]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n $y)
FontColor=#Gris#
Text=$libelle

[Val$nom]
Meter=String
MeterStyle=StyleTexte
X=$(n 284)
Y=$(n $y)
StringAlign=RightCenter
Text=#$var#
DynamicVariables=1
"@
}
$panneau = @"
[Rainmeter]
Update=-1
AccurateText=1
OnRefreshAction=[!Move "$panX" "$panY"][!ZPos "2"][!Draggable "0"][!KeepOnScreen "0"][!SnapEdges "0"][!Hide]

[Metadata]
Name=Panneau batterie facon Apple
Information=S'ouvre au clic sur l'icone de batterie. Verre et fermeture au clic exterieur : barre_reservee.ps1.

[Variables]
Police=Segoe UI Variable Text
Txt=255,255,255,255
Gris=255,255,255,195
Source=…
Sante=…
Cycles=…
Capacite=…
EcoActif=…
FondVerre=
FAuto=255,255,255,230
FOn=0,0,0,1
FOff=0,0,0,1
TAuto=25,22,30,255
TOn=255,255,255,255
TOff=255,255,255,255
CFond=120,120,128,170
CRond=$(n 22)
ConsCible=On
@Include=$etat

[StyleTexte]
FontFace=#Police#
FontSize=$(n 9.3)
FontColor=#Txt#
AntiAlias=1
StringAlign=LeftCenter
SolidColor=0,0,0,0

[MesurePct]
Measure=Plugin
Plugin=PowerPlugin
PowerState=Percent

[MesureEcoForce]
Measure=String
String=#EcoForce#
DynamicVariables=1
IfMatch=^on$
IfMatchAction=[!SetVariable FAuto "0,0,0,1"][!SetVariable FOn "255,255,255,230"][!SetVariable FOff "0,0,0,1"][!SetVariable TAuto "#Txt#"][!SetVariable TOn "25,22,30,255"][!SetVariable TOff "#Txt#"]
IfMatch2=^off$
IfMatchAction2=[!SetVariable FAuto "0,0,0,1"][!SetVariable FOn "0,0,0,1"][!SetVariable FOff "255,255,255,230"][!SetVariable TAuto "#Txt#"][!SetVariable TOn "#Txt#"][!SetVariable TOff "25,22,30,255"]
IfMatch3=^(?!on$|off$)
IfMatchAction3=[!SetVariable FAuto "255,255,255,230"][!SetVariable FOn "0,0,0,1"][!SetVariable FOff "0,0,0,1"][!SetVariable TAuto "25,22,30,255"][!SetVariable TOn "#Txt#"][!SetVariable TOff "#Txt#"]
IfMatchMode=0

[MesureCons]
Measure=String
String=#Conservation#
DynamicVariables=1
IfMatch=^On$
IfMatchAction=[!SetVariable CFond "52,199,89,255"][!SetVariable CRond "$(n 31)"][!SetVariable ConsCible "Off"]
IfMatch2=^Off$
IfMatchAction2=[!SetVariable CFond "120,120,128,170"][!SetVariable CRond "$(n 13)"][!SetVariable ConsCible "On"]
IfMatch3=^attente$
IfMatchAction3=[!SetVariable CFond "255,255,255,70"][!SetVariable CRond "$(n 22)"][!SetVariable ConsCible "attente"]
IfMatch4=^(?!On$|Off$|attente$)
IfMatchAction4=[!SetVariable CFond "120,120,128,170"][!SetVariable CRond "$(n 22)"][!SetVariable ConsCible "On"]
IfMatchMode=0

[FondVerre]
Meter=Image
ImageName=#FondVerre#
X=0
Y=0
W=$(n 300)
H=$(n 286)
DynamicVariables=1

[Fond]
Meter=Shape
Shape=Rectangle $(f 0.5),$(f 0.5),$(f (300 - 1)),$(f (286 - 1)),$(n 14) | Fill Color 255,255,255,12 | StrokeWidth $(f 1.2) | Stroke Color 255,255,255,110

[Titre]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n 24)
FontSize=$(n 10.7)
FontWeight=600
Text=Batterie

[Pct]
Meter=String
MeterStyle=StyleTexte
MeasureName=MesurePct
X=$(n 284)
Y=$(n 24)
StringAlign=RightCenter
FontSize=$(n 10.7)
FontWeight=600
Text=%1 %

[Source]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n 46)
FontSize=$(n 8.3)
FontColor=#Gris#
Text=#Source#
DynamicVariables=1
$(Ligne 62)$(Rangee 'Sante' 82 'État de la batterie' 'Sante')$(Rangee 'Cycles' 104 'Nombre de cycles' 'Cycles')$(Ligne 122)
[LibEco]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n 140)
FontWeight=600
Text=Mode économie

[EtatEco]
Meter=String
MeterStyle=StyleTexte
X=$(n 284)
Y=$(n 140)
StringAlign=RightCenter
FontSize=$(n 8.3)
FontColor=#Gris#
Text=#EcoActif#
DynamicVariables=1

[Piste]
Meter=Shape
X=$(n 16)
Y=$(n 154)
Shape=Rectangle 0,0,$(n 268),$(n 26),$(n 8) | Fill Color 255,255,255,28 | StrokeWidth 0
$(Segment 'Auto' 0 'Auto' 'auto')$(Segment 'On' 1 'Activé' 'on')$(Segment 'Off' 2 'Désactivé' 'off')$(Ligne 196)
[LibCons]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n 214)
FontWeight=600
Text=Conservation de la batterie

[SousCons]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n 232)
FontSize=$(n 7.7)
FontColor=#Gris#
Text=Charge limitée à 80 %

[Interrupteur]
Meter=Shape
X=$(n 240)
Y=$(n 210)
Shape=Rectangle 0,0,$(n 44),$(n 26),$(n 13) | Fill Color #CFond# | StrokeWidth 0
Shape2=Ellipse #CRond#,$(n 13),$(n 11) | Fill Color 255,255,255,255 | StrokeWidth 0
DynamicVariables=1
LeftMouseUpAction=["wscript.exe" "$lanceur" "$conservation" "#ConsCible#"][!SetVariable Conservation attente][!UpdateMeasure MesureCons][!UpdateMeter *][!Redraw]
ToolTipText=Windows va demander l'autorisation (Oui/Non)
$(Ligne 250)
[Reglages]
Meter=String
MeterStyle=StyleTexte
X=$(n 16)
Y=$(n 268)
Text=Réglages de la batterie…
LeftMouseUpAction=["ms-settings:batterysaver"][!Hide]
MouseOverAction=[!SetOption Reglages FontColor "120,180,255,255"][!UpdateMeter Reglages][!Redraw]
MouseLeaveAction=[!SetOption Reglages FontColor "#Txt#"][!UpdateMeter Reglages][!Redraw]
"@
Ecrire (Join-Path $Skins 'PanneauBatterie\PanneauBatterie.ini') $panneau
}

# ------------------------- Centre de controle facon Mac (clic sur l'icone) -------------------------
New-Item -ItemType Directory -Force (Join-Path $Skins 'CentreControle') | Out-Null
$ccW = 320; $ccH = 358
$ccX = [math]::Max(0, $largeur - [int](n 8) - [int](n $ccW)); $ccY = [int]$hp + [int](n 6)
$icCC = $largeur - [int](n 168)
# zone de l'icone + rayon + curseurs luminosite et son (x,y,largeur,hauteur relatifs au panneau), lus par barre_reservee.ps1
Set-Content (Join-Path $App 'zone_centre.txt') ("{0},{1},0,{2},{3},{4},{5},{6},{7},{8},{9},{10},{11}" -f ($icCC - [int](n 16)), ($icCC + [int](n 16)), $hp, (n 14), (n 24), (n 128), (n 272), (n 22), (n 24), (n 212), (n 232), (n 22))
$msg = '[!CommandMeasure MesureMoteur "SendMessage 32769 {0} 0"]'
function Tuile($x, $y, $w, $h) { "Shape=Rectangle $(n $x),$(n $y),$(n $w),$(n $h),$(n 12) | Fill Color 255,255,255,24 | StrokeWidth $(f 0.8) | Stroke Color 255,255,255,30" }
function Radio($nom, $x, $icone, $titre, $varFond, $varTexte, $cmd, $liste) {
@"

[Rond$nom]
Meter=Shape
Group=Radios
Shape=Ellipse $(n ($x + 28)),$(n 48),$(n 16) | Fill Color #$varFond# | StrokeWidth 0
DynamicVariables=1
LeftMouseUpAction=$($msg -f $cmd)
ToolTipText=Activer / désactiver

[Icone$nom]
Meter=String
MeterStyle=StyleTexte
X=$(n ($x + 28))
Y=$(n 48)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 9.5)
Text=[\x$icone]

[Zone$nom]
Meter=Shape
Shape=Rectangle $(n ($x + 48)),$(n 22),$(n 92),$(n 52) | Fill Color 0,0,0,1 | StrokeWidth 0
LeftMouseUpAction=["$liste"][!Hide]

[Titre$nom]
Meter=String
MeterStyle=StyleTexte
X=$(n ($x + 52))
Y=$(n 40)
FontWeight=600
Text=$titre

[Etat$nom]
Meter=String
MeterStyle=StyleTexte
Group=Radios
X=$(n ($x + 52))
Y=$(n 57)
W=$(n 88)
ClipString=1
FontSize=$(n 7.7)
FontColor=#Gris#
Text=#$varTexte#
DynamicVariables=1
"@
}
function Glissiere($nom, $var, $y, $w, $icone) {
@"

[Piste$nom]
Meter=Shape
Group=$var
Shape=Rectangle $(n 24),$(n $y),$(n $w),$(n 22),$(n 11) | Fill Color 255,255,255,40 | StrokeWidth 0
Shape2=Rectangle $(n 24),$(n $y),(Max($(n 22),Max(#$var#,0)*$(f ($w / 100)))),$(n 22),$(n 11) | Fill Color 255,255,255,235 | StrokeWidth 0
Shape3=Ellipse ($(n 24)+Max($(n 11),Max(#$var#,0)*$(f ($w / 100))-$(n 11))),$(n ($y + 11)),$(n 11) | Fill Color 255,255,255,255 | StrokeWidth $(f 0.8) | Stroke Color 0,0,0,40
DynamicVariables=1

[Pictogramme$nom]
Meter=String
MeterStyle=StyleTexte
Group=$var
X=$(n 36)
Y=$(n ($y + 11))
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 8)
FontColor=70,70,80,255
Text=[\x$icone]
"@
}
$cc = @"
[Rainmeter]
Update=-1
AccurateText=1
OnRefreshAction=[!Move "$ccX" "$ccY"][!ZPos "2"][!Draggable "0"][!KeepOnScreen "0"][!SnapEdges "0"][!Hide]

[Metadata]
Name=Centre de controle facon Mac
Information=S'ouvre au clic sur l'icone de la barre. Verre, curseurs, Wi-Fi, Bluetooth et musique : barre_reservee.ps1.

[Variables]
Police=Segoe UI Variable Text
Icones=Segoe Fluent Icons
Txt=255,255,255,255
Gris=255,255,255,195
WifiFond=255,255,255,45
WifiTexte=…
BtFond=255,255,255,45
BtTexte=…
Lum=50
Son=50
MusTitre=Aucune lecture
MusArtiste=
MusEtat=0
MusImage=
FondVerre=

[StyleTexte]
FontFace=#Police#
FontSize=$(n 9.3)
FontColor=#Txt#
AntiAlias=1
StringAlign=LeftCenter
SolidColor=0,0,0,0

[MesureMoteur]
Measure=Plugin
Plugin=WindowMessagePlugin
WindowName=InterfaceMacMoteur
UpdateDivider=-1

[MesureLum]
Measure=Calc
Formula=#Lum#
DynamicVariables=1
UpdateDivider=-1

[MesureSon]
Measure=Calc
Formula=#Son#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MesureSon < 0
IfTrueAction=[!HideMeter PictogrammeSon][!ShowMeter Muet]
IfFalseAction=[!ShowMeter PictogrammeSon][!HideMeter Muet]

[MesureMus]
Measure=Calc
Formula=#MusEtat#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MesureMus = 1
IfTrueAction=[!HideMeter Lecture][!ShowMeter Pause]
IfFalseAction=[!ShowMeter Lecture][!HideMeter Pause]

[FondVerre]
Meter=Image
ImageName=#FondVerre#
X=0
Y=0
W=$(n $ccW)
H=$(n $ccH)
DynamicVariables=1

[Fond]
Meter=Shape
Shape=Rectangle $(f 0.5),$(f 0.5),$(f ($ccW - 1)),$(f ($ccH - 1)),$(n 14) | Fill Color 255,255,255,12 | StrokeWidth $(f 1.2) | Stroke Color 255,255,255,110
Shape2=Rectangle $(n 12),$(n 12),$(n 144),$(n 72),$(n 12) | Fill Color 255,255,255,24 | StrokeWidth $(f 0.8) | Stroke Color 255,255,255,30
Shape3=Rectangle $(n 164),$(n 12),$(n 144),$(n 72),$(n 12) | Fill Color 255,255,255,24 | StrokeWidth $(f 0.8) | Stroke Color 255,255,255,30
Shape4=Rectangle $(n 12),$(n 96),$(n 296),$(n 64),$(n 12) | Fill Color 255,255,255,24 | StrokeWidth $(f 0.8) | Stroke Color 255,255,255,30
Shape5=Rectangle $(n 12),$(n 172),$(n 296),$(n 72),$(n 12) | Fill Color 255,255,255,24 | StrokeWidth $(f 0.8) | Stroke Color 255,255,255,30
Shape6=Rectangle $(n 12),$(n 256),$(n 296),$(n 72),$(n 12) | Fill Color 255,255,255,24 | StrokeWidth $(f 0.8) | Stroke Color 255,255,255,30
$(Radio 'Wifi' 12 'E701' 'Wi-Fi' 'WifiFond' 'WifiTexte' 4 'ms-availablenetworks:')$(Radio 'Bt' 164 'E702' 'Bluetooth' 'BtFond' 'BtTexte' 5 'ms-settings:bluetooth')
[TitreEcran]
Meter=String
MeterStyle=StyleTexte
X=$(n 24)
Y=$(n 113)
FontWeight=600
Text=Écran
$(Glissiere 'Lum' 'Lum' 128 272 'E706')
[TitreSon]
Meter=String
MeterStyle=StyleTexte
X=$(n 24)
Y=$(n 194)
FontWeight=600
Text=Son
$(Glissiere 'Son' 'Son' 212 232 'E995')
[Muet]
Meter=String
MeterStyle=StyleTexte
X=$(n 36)
Y=$(n 223)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 8)
FontColor=70,70,80,255
Text=[\xE74F]
Hidden=1

[BoutonMuet]
Meter=Shape
Shape=Ellipse $(n 282),$(n 223),$(n 14) | Fill Color 255,255,255,40 | StrokeWidth 0
LeftMouseUpAction=$($msg -f 6)
ToolTipText=Couper / remettre le son

[IconeMuet]
Meter=String
MeterStyle=StyleTexte
X=$(n 282)
Y=$(n 223)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 8.5)
Text=[\xE74F]

[FondPochette]
Meter=Shape
Shape=Rectangle $(n 24),$(n 268),$(n 48),$(n 48),$(n 8) | Fill Color 255,255,255,30 | StrokeWidth 0

[NotePochette]
Meter=String
MeterStyle=StyleTexte
X=$(n 48)
Y=$(n 292)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 12)
FontColor=255,255,255,120
Text=[\xE8D6]

[Pochette]
Meter=Image
Group=Musique
ImageName=#MusImage#
X=$(n 24)
Y=$(n 268)
W=$(n 48)
H=$(n 48)
PreserveAspectRatio=2
DynamicVariables=1

[MusTitre]
Meter=String
MeterStyle=StyleTexte
Group=Musique
X=$(n 84)
Y=$(n 283)
W=$(n 150)
ClipString=1
FontWeight=600
Text=#MusTitre#
DynamicVariables=1

[MusArtiste]
Meter=String
MeterStyle=StyleTexte
Group=Musique
X=$(n 84)
Y=$(n 302)
W=$(n 150)
ClipString=1
FontSize=$(n 7.7)
FontColor=#Gris#
Text=#MusArtiste#
DynamicVariables=1

[Lecture]
Meter=String
MeterStyle=StyleTexte
X=$(n 258)
Y=$(n 292)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 12)
Text=[\xF5B0]
SolidColor=0,0,0,1
LeftMouseUpAction=$($msg -f 1)

[Pause]
Meter=String
MeterStyle=StyleTexte
X=$(n 258)
Y=$(n 292)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 12)
Text=[\xF8AE]
SolidColor=0,0,0,1
LeftMouseUpAction=$($msg -f 1)
Hidden=1

[Suivant]
Meter=String
MeterStyle=StyleTexte
X=$(n 288)
Y=$(n 292)
StringAlign=CenterCenter
FontFace=#Icones#
FontSize=$(n 10)
Text=[\xF8AD]
SolidColor=0,0,0,1
LeftMouseUpAction=$($msg -f 2)

[PlusReglages]
Meter=String
MeterStyle=StyleTexte
X=$(n 24)
Y=$(n 342)
FontSize=$(n 8.7)
Text=Plus de réglages…
LeftMouseUpAction=[!Hide]["wscript.exe" "$lanceur" "$raccourci" "A"]
MouseOverAction=[!SetOption PlusReglages FontColor "120,180,255,255"][!UpdateMeter PlusReglages][!Redraw]
MouseLeaveAction=[!SetOption PlusReglages FontColor "#Txt#"][!UpdateMeter PlusReglages][!Redraw]
"@
Ecrire (Join-Path $Skins 'CentreControle\CentreControle.ini') $cc

[pscustomobject]@{ Echelle = $S; LargeurPx = $largeur; Batterie = $aBatterie; PastilleX = $px; PastilleY = $py; BarrePx = $hp }
