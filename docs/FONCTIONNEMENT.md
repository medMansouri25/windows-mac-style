# Fonctionnement technique

## Vue d'ensemble

```
Ouverture de session
   └─ Tâche planifiée « Interface Mac - demarrage »
        └─ wscript lancer_invisible.vbs  (aucune fenêtre)
             └─ demarrer_interface.ps1
                  ├─ barre_reservee.ps1  (tourne en permanence, invisible)
                  │     ├─ AppBar : réserve la bande du haut (SHAppBarMessage)
                  │     ├─ surveille Rainmeter → relance si fermé
                  │     ├─ toutes les 3 s : état batterie → variables Rainmeter
                  │     ├─ batterie / économie 15 s → economie.ps1 Activer/Desactiver
                  │     ├─ toutes les 6 s : signal Wi-Fi (API WinRT) → icône Wi-Fi
                  │     ├─ événement WMI WmiMonitorBrightnessEvent → pastille luminosité
                  │     └─ événement Core Audio (IAudioEndpointVolume) → pastille volume
                  ├─ Rainmeter (__COMPAT_LAYER=~ HIGHDPIAWARE)
                  │     ├─ MacWidgets\BarreMenus   (barre des menus + batterie.lua)
                  │     ├─ MacWidgets\Volume       (pastille, valeur envoyée par le moteur)
                  │     └─ MacWidgets\Luminosite   (pastille, valeur envoyée par le moteur)
                  └─ fond d'écran (IDesktopWallpaper) seulement s'il a changé
Windhawk (service) → modules injectés dans explorer.exe → dock
```

## Le dock (Windhawk)

La barre des tâches de Windows reste la vraie barre des tâches. Elle est seulement transformée par 4 modules Windhawk :

| Module | Version | Réglages |
|---|---|---|
| windows-11-taskbar-styler | 1.11.2 | thème `LiquidGlass2` + masquage de la recherche, des widgets et de la vue des tâches ; heure et wifi rendus invisibles (largeur 0, opacité 0) ; pastille d'icônes vide masquée via une variable de style `ActualWidth=>largeurTray` |
| taskbar-dock-animation | 1.9.2 | effet loupe 150 %, rayon 200, sans rebond |
| taskbar-icon-size | 1.3.11 | hauteur 68, icônes 26 |
| on-screen-indicator-position | 1.6.1 | indicateurs volume et luminosité de Windows masqués |

L'installateur installe les modules comme le bouton « Install » de Windhawk : il télécharge la DLL précompilée depuis `mods.windhawk.net`, la copie dans `C:\ProgramData\Windhawk\Engine\Mods\64`, et écrit la configuration dans `HKLM\SOFTWARE\Windhawk\Engine\Mods\<id>` (avec `Settings`). Les réglages sont aplatis comme le fait Windhawk : `controlStyles[0].target`, `controlStyles[0].styles[0]`…

Réglages Windhawk appliqués : `ModTasksDialogDelay=600000` et `DontAutoShowToolkit=1`, pour qu'aucune fenêtre Windhawk n'apparaisse au démarrage.

## La barre des menus (Rainmeter)

- `generer_skins.ps1` mesure l'écran (DPI, largeur en pixels réels, batterie présente ou non) et écrit les fichiers `.ini` en **pixels réels**, avec des valeurs entières pour un rendu net.
- Rainmeter est lancé avec `__COMPAT_LAYER=~ HIGHDPIAWARE` et la même valeur dans `HKCU\...\AppCompatFlags\Layers`. Sans ça, Windows étire Rainmeter (flou) à 125 % ou 150 %.
- La barre se remet en `0,0` chaque seconde si elle est déplacée (`batterie.lua`).
- Les pastilles se repositionnent et repassent au premier plan à chaque affichage.
- **Aucune interrogation en boucle** pour le volume et la luminosité : c'est Windows qui prévient le moteur. Pour le volume, le moteur s'abonne aux changements de la sortie audio par défaut (`IAudioEndpointVolumeCallback`, revérifiée toutes les 36 s si vous changez de casque ou d'écran) et envoie la valeur à Rainmeter par `WM_COPYDATA`, sans lancer de processus. L'ancienne pastille interrogeait le volume 4 fois par seconde avec `Win7AudioPlugin` : environ 5 % d'un cœur sur batterie, contre 0,5 % maintenant.
- La batterie n'est redessinée que si son état change.

## Mode économie

`barre_reservee.ps1` lit `GetSystemPowerStatus` toutes les 3 s. Après 5 lectures identiques (15 s), il lance `economie.ps1 Activer` ou `Desactiver`. Le mode est ignoré sur un PC sans batterie.

- Fermeture : programmes de `config.json`, avec une seconde passe 3 s plus tard (certains se relancent seuls). Pour NVIDIA Overlay, le relanceur `nvcontainer` de la session (`SPUser`) est aussi arrêté.
- Relance : via l'identifiant du menu Démarrer (`shell:AppsFolder\<AppID>`), mémorisé à la fermeture. La fenêtre est réduite, avec un nouvel essai si le programme s'est arrêté.
- Écran : fréquence via `ChangeDisplaySettingsEx` (`frequence_ecran.ps1`), luminosité via WMI `WmiSetBrightness`. Les valeurs d'origine sont mémorisées dans `economie_ecran.json`. Si l'écran est **déjà** à la fréquence réduite au moment d'activer (PC démarré sur batterie, ou fréquence baissée par Windows ou le logiciel du fabricant), c'est la **fréquence maximale** de l'écran qui est mémorisée : au rebranchement, il repasse par exemple à 240 Hz au lieu de rester à 60 Hz.

### Couleur de la batterie

`barre_reservee.ps1` envoie à la barre la variable `Economie` = 1 quand l'économiseur de batterie de Windows est actif **ou** quand notre mode économie est appliqué (après les 15 s). Il renvoie l'état à chaque changement et toutes les 36 s, au cas où Rainmeter aurait été rechargé. `batterie.lua` choisit la couleur dans cet ordre :

| Priorité | État | Couleur |
|---|---|---|
| 1 | branché et en charge | verte avec éclair |
| 2 | branché, recharge en pause (limite de charge) | blanche avec éclair |
| 3 | sur batterie, moins de 20 % | **rouge** (l'alerte passe avant le jaune) |
| 4 | mode économie actif | **jaune** (icône et pourcentage) |
| 5 | sur batterie, autres cas | blanche |

Juste après le débranchement, la batterie reste blanche pendant les 15 s d'attente, puis devient jaune.

## Icône Wi-Fi

Depuis Windows 11 24H2, l'ancienne API Wi-Fi (`WlanAPI`, utilisée par le plugin `WiFiStatus` de Rainmeter et par `netsh wlan`) exige l'accès à la **localisation**. On ne touche pas à ce réglage : `barre_reservee.ps1` lit plutôt le signal comme la barre des tâches de Windows, avec l'API WinRT `NetworkInformation.GetInternetConnectionProfile()` (`GetSignalBars()` de 0 à 5, et `GetNetworkConnectivityLevel()`).

- Lecture toutes les 6 s. La barre n'est prévenue qu'en cas de changement, plus un rappel toutes les 36 s : variables `WifiNiv` et `WifiInfo`.
- Niveaux : 0 = pas de connexion ou pas d'Internet (icône barrée) ; 1 à 4 = arcs allumés (barres 0-1 → 1, 2 → 2, 3 → 3, 4-5 → 4). Une connexion par câble s'affiche comme un signal plein.
- Affichage : une icône Wi-Fi grise en fond, avec par-dessus en blanc le nombre d'arcs du niveau, comme sur Mac. Le survol indique le nom du réseau et le signal.

## Panneaux Windows depuis la barre

Le centre de contrôle et les notifications s'ouvrent en simulant **⊞ + A** et **⊞ + N** (`raccourci.ps1`). Ouverts par l'URI `ms-actioncenter:`, ces panneaux n'avaient pas le focus et ne se fermaient pas au clic extérieur.

- **Loupe** : simule **⊞ + S** (recherche Windows, champ prêt pour la saisie).
- **Logo et « Applications »** : `raccourci.ps1 Demarrer` envoie `WM_SYSCOMMAND` / `SC_TASKLIST` à la barre des tâches (`Shell_TrayWnd`), ce qui ouvre le menu Démarrer. Avec Ctrl+Échap ou la touche ⊞ simulés après un clic sur la barre, le menu ne s'ouvrait pas.

## Fichiers installés

| Emplacement | Contenu |
|---|---|
| `%LOCALAPPDATA%\InterfaceMac\` | scripts, `config.json`, fond d'écran, journaux, `sauvegarde\` |
| `Documents\Rainmeter\Skins\MacWidgets\` | barre et pastilles générées |
| `%APPDATA%\Rainmeter\Rainmeter.ini` | configuration Rainmeter (l'original est sauvegardé) |
| `HKLM\SOFTWARE\Windhawk\Engine\Mods\…` | les 4 modules |
| Tâche planifiée « Interface Mac - demarrage » | démarrage |
