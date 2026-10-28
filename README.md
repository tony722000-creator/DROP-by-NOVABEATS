# DROP by NOVA BEAT

<p align="center"><img src="Branding/drop-icon-1024.png" width="160" alt="Icône DROP"></p>

**DROP** est une app macOS gratuite pour les beatmakers sous FL Studio : tu glisses un projet `.flp`,
elle retrouve tous les samples audio utilisés (`.wav`, `.mp3`, `.aif`, `.aiff`, `.flac`, `.ogg`),
les classe par type (808, kick, snare, clap, hihat…) et les **copie** dans un dossier propre, renommés.
Idéal pour préparer un drum kit ou envoyer les sons d'une prod.

```
<dossier de sortie>/<artiste> - <titre>/<type>/<type>-<artiste>-<titre>.<ext>
Sorties/wazanolimit - monalisa/808/808-wazanolimit-monalisa.wav
```

- 100 % local : aucune connexion internet nécessaire.
- Les fichiers originaux ne sont jamais déplacés ni modifiés.
- Fonctionne aussi avec des projets venus d'un autre ordinateur (chemins Windows, disque externe débranché…).

## Télécharger

👉 **[Télécharger la dernière version](../../releases/latest)** : prends `DROP-x.y.z.dmg`.

1. Ouvre le `.dmg` et glisse **DROP** dans **Applications**.
2. **Première ouverture** : l'app n'est pas signée par Apple, donc macOS la bloque par défaut.
   Fais **clic droit sur DROP → Ouvrir → Ouvrir**. Ensuite elle s'ouvre normalement.
   Si le message persiste : Réglages Système → Confidentialité et sécurité → « Ouvrir quand même ».
3. macOS demandera l'accès à Téléchargements / Documents / disques externes : accepte, c'est pour trouver tes sons.

Compatible macOS 14 et plus, Apple Silicon et Intel.

## Utilisation

1. Premier lancement : choisis ta bibliothèque de drums (modifiable dans les réglages, `⌘,`).
2. Glisse un ou plusieurs `.flp` dans la fenêtre (ou `⌘O`).
3. Vérifie la liste : décoche des sons, change le type en cliquant sur le badge coloré.
4. Remplis artiste, titre (vide = nom du `.flp`) et dossier de sortie.
5. Appuie sur **START** (ou Entrée). Un récapitulatif s'affiche à la fin.

Recherche des samples, dans l'ordre : chemin exact du `.flp` → bibliothèque → `~/Downloads` → dossiers de secours.
Sons introuvables : bouton « CHERCHER… » pour fouiller un autre dossier ou un disque externe.

## Outil en ligne de commande

```
dkw-flp projet.flp                       # liste les samples du .flp
dkw-flp projet.flp --library ~/Samples   # + vérifie s'ils sont retrouvés
dkw-flp --self-test                      # tests automatiques
```

## Construire depuis le code

Prérequis : Command Line Tools (pas besoin d'Xcode).

```
./build.sh
```

Produit `build/DROP.app`, `build/DROP-<version>.dmg`, `build/DROP-<version>.zip` et `build/dkw-flp`.

La détection des types se règle dans `Sources/DKWCore/Classification/ClassificationRules.swift`.
`Sources/DKWCore` contient toute la logique (lecture FLP, recherche, classification, copie) sans interface ;
`Sources/DROP` contient l'interface SwiftUI.

---

DROP by NOVA BEAT · logiciel pour beatmakers FL Studio sur Mac · extraction de samples · drum kit
