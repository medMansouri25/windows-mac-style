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
                  │     └─ événement WMI WmiMonitorBrightnessEvent → pastille luminosité
                  ├─ Rainmeter (__COMPAT_LAYER=~ HIGHDPIAWARE)
                  │     ├─ MacWidgets\BarreMenus   (barre des menus + batterie.lua)
                  │     ├─ MacWidgets\Volume       (Win7AudioPlugin, pastille)
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

## Mode économie

`barre_reservee.ps1` lit `GetSystemPowerStatus` toutes les 3 s. Après 5 lectures identiques (15 s), il lance `economie.ps1 Activer` ou `Desactiver`. Le mode est ignoré sur un PC sans batterie.

- Fermeture : programmes de `config.json`, avec une seconde passe 3 s plus tard (certains se relancent seuls). Pour NVIDIA Overlay, le relanceur `nvcontainer` de la session (`SPUser`) est aussi arrêté.
- Relance : via l'identifiant du menu Démarrer (`shell:AppsFolder\<AppID>`), mémorisé à la fermeture. La fenêtre est réduite, avec un nouvel essai si le programme s'est arrêté.
- Écran : fréquence via `ChangeDisplaySettingsEx` (`frequence_ecran.ps1`), luminosité via WMI `WmiSetBrightness`. Les valeurs d'origine sont mémorisées dans `economie_ecran.json`.

## Panneaux Windows depuis la barre

Le centre de contrôle et les notifications s'ouvrent en simulant **⊞ + A** et **⊞ + N** (`raccourci.ps1`). Ouverts par l'URI `ms-actioncenter:`, ces panneaux n'avaient pas le focus et ne se fermaient pas au clic extérieur.

## Fichiers installés

| Emplacement | Contenu |
|---|---|
| `%LOCALAPPDATA%\InterfaceMac\` | scripts, `config.json`, fond d'écran, journaux, `sauvegarde\` |
| `Documents\Rainmeter\Skins\MacWidgets\` | barre et pastilles générées |
| `%APPDATA%\Rainmeter\Rainmeter.ini` | configuration Rainmeter (l'original est sauvegardé) |
| `HKLM\SOFTWARE\Windhawk\Engine\Mods\…` | les 4 modules |
| Tâche planifiée « Interface Mac - demarrage » | démarrage |
