# Dépannage

### La barre du haut n'apparaît pas après le démarrage
- Regardez `%LOCALAPPDATA%\InterfaceMac\demarrage.log` : la dernière ligne doit être « Demarrage termine ».
- Vérifiez la tâche : *Planificateur de tâches* → « Interface Mac - demarrage ».
- Relance manuelle : double-clic sur `%LOCALAPPDATA%\InterfaceMac\lancer_invisible.vbs` en lui passant `demarrer_interface.ps1`, ou relancez `INSTALLER.bat`.

### La barre est floue ou trop grande
Rainmeter n'est pas en pleine résolution. Fermez Rainmeter (icône dans la zone de notification → Quitter) : le moteur le relance correctement en 3 secondes. Si ça persiste, relancez `INSTALLER.bat`.

### Des widgets « Welcome / Clock / System » apparaissent
Ce sont les exemples de Rainmeter. Le démarrage les désactive. Relancer `INSTALLER.bat` réécrit la configuration Rainmeter.

### Le dock est redevenu une barre des tâches normale
Windhawk s'est peut-être mis en **mode sans échec** après un plantage de l'Explorateur.
- Ouvrez Windhawk : s'il affiche « Safe mode », désactivez-le dans ses paramètres.
- Relancez `INSTALLER.bat` : il détecte les plantages et retire automatiquement les réglages en cause.
- ⚠️ Ne jamais masquer un élément `SystemTray.*` avec `Visibility=Collapsed` dans le Styler : ça fait planter l'Explorateur au démarrage. Utiliser `Width=0` et `Opacity=0`.

### Le panneau des réglages rapides ne se ferme pas
Il doit s'ouvrir via l'icône de la barre, qui simule ⊞ + A. S'il a été ouvert autrement, appuyez sur Échap.

### Le mode économie ferme un programme que je veux garder
Retirez-le de `economie.programmes` dans `%LOCALAPPDATA%\InterfaceMac\config.json`, ou mettez `"actif": false` pour couper tout le mode.

### Après un changement d'écran ou d'échelle d'affichage
La barre et les pastilles sont calculées pour l'écran présent lors de l'installation. Relancez `INSTALLER.bat`, ou seulement :
```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\InterfaceMac\generer_skins.ps1"
```
puis fermez Rainmeter (il se relance seul).

### L'installation échoue
Le journal complet est dans `%TEMP%\InterfaceMac_installation.log`. Causes fréquentes : pas d'Internet, `winget` absent (installez « App Installer » depuis le Microsoft Store), compte non administrateur.
