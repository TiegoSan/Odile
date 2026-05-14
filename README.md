# Odile

App macOS SwiftUI qui lit la session Pro Tools ouverte via PTSL et fabrique une EDL musique en tableau pour les pistes selectionnees dans Pro Tools.

## Fonctionnement

- Connexion a Pro Tools sur `localhost:31416` avec `PTSLC_CPP`.
- Appel PTSL `GetTrackList` pour reperer les pistes selectionnees dans Pro Tools.
- Appel PTSL `ExportSessionInfoAsText` avec `include_track_edls`.
- Parsing des sections de pistes selectionnees.
- Affichage en tableau editable: event chronologique, morceau, in, out, duree.
- Les noms de pistes sont utilises en interne pour analyser la session, mais ne sont pas affiches dans le tableau ni exportes.
- Suppression de ligne via le bouton poubelle, le bouton `Supprimer`, ou la commande Delete sur une ligne selectionnee.
- Copier/coller de timecodes directement dans les cellules, avec menu contextuel sur chaque ligne.
- Timecodes affiches en `HH:MM:SS:FF`, avec offset optionnel `+/-HH:MM:SS:FF`.
- Les sources techniques `Audio Process Stream` sont ignorees.
- Les blocs generiques `mu`, `mu_`, `mus`, `mus_` colles a un bloc nomme sont integres au morceau nomme adjacent.
- Export XLSX avec mise en page Excel: cartouche titre/date, en-tetes colores, lignes espacees, colonnes ajustees, filtres et volet fige.
- Copie CSV dans le presse-papiers pour les collages rapides.
- Import des lignes du tableau comme Memory Locations / markers dans la session Pro Tools ouverte.

## Build

```sh
xcodebuild -project Odile.xcodeproj -scheme Odile -configuration Debug build
```

Pro Tools doit etre lance avec une session ouverte pour charger une EDL reelle.

## Architecture

L'application a été récemment migrée vers une architecture claire composant de :
- L'architecture **MVVM (Model-View-ViewModel)** via `OdileViewModel.swift` pour stocker tout l'état de l'application.
- `ContentView.swift` : L'interface SwiftUI principale, qui ne contient désormais plus de logique métier.
- L'interface C++ de Pro Tools `PTSLWrapper.mm` est propre avec peu/pas de warnings de compilation et analyse intelligemment les erreurs pour l'interface utilisateur.
