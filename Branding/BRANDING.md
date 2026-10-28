# DROP by NOVABEATS — identité visuelle

Fichiers à intégrer dans l'app macOS DROP (Swift Package Manager, sans Xcode).

## Fichiers

| Fichier | Taille | Usage |
|---|---|---|
| `AppIcon.icns` | 16 → 1024 px | Icône de l'app (Dock, Finder). À copier dans `DROP.app/Contents/Resources/` par `build.sh`, avec `CFBundleIconFile = AppIcon` dans `Info.plist`. Déjà au format macOS (carré arrondi + ombre) : ne pas re-masquer. |
| `drop-icon-1024.png` | 1024×1024 | Même icône en PNG (README GitHub, page de Release). |
| `drop-logo.png` | 1613×622, fond transparent | Logo complet « DROP by NOVABEATS ». Écran d'accueil / zone de glisser-déposer vide, fenêtre « À propos ». |
| `drop-logo@1x.png` | 806×311, fond transparent | Version plus légère du logo. |

Dans le package Swift : placer les PNG dans `Sources/<cible de l'app>/Resources/`, déclarer `resources: [.process("Resources")]` dans `Package.swift`, et les charger avec `Bundle.module` (ex. `NSImage(contentsOf: Bundle.module.url(forResource: "drop-logo", withExtension: "png")!)`). Pas d'Asset Catalog.

Le logo est conçu pour un fond sombre. En mode clair, l'afficher sur un panneau sombre arrondi plutôt que sur du blanc.

## Couleurs « violet espace »

| Nom | Hex | Usage |
|---|---|---|
| Espace (fond) | `#08050F` | Fond principal, mode sombre |
| Nébuleuse | `#1A1033` | Cartes, panneaux, zones secondaires |
| Violet électrique | `#8B5CF6` | Couleur d'accent (boutons, sélection, badges) |
| Violet profond | `#5B21B6` | Bas des dégradés, états appuyés |
| Magenta lueur | `#C026D3` | Haut des dégradés, halos |
| Lavande | `#C4B5FD` | Texte secondaire sur fond sombre |

Dégradé signature : de `#C026D3` (haut) à `#5B21B6` (bas), comme sur le mot DROP. Utiliser `#8B5CF6` comme `accentColor` de toute l'app.

## Direction artistique : « pédale d'effet »

L'app doit ressembler à une pédale d'effet de guitare haut de gamme : un boîtier en métal peint violet, texturé, avec des commandes blanches/crème physiques. **Suivre `maquette-ui.jpg` comme référence visuelle** pour la disposition et le style (c'est une image d'inspiration, pas une capture à découper).

### Fichiers

| Fichier | Usage |
|---|---|
| `maquette-ui.jpg` | Maquette de référence de l'écran principal. Le fond de fenêtre doit être aussi texturé que sur cette maquette (peinture violette martelée, rayures, usure). Les images nécessaires (texture, bouton START, vis…) seront fournies à la demande. |

### Éléments à reproduire en SwiftUI (pas en images)

- **Bouton principal START** : gros bouton poussoir analogique carré aux coins arrondis, blanc cassé, façon pad de boîte à rythmes vintage, monté dans un cadre en métal sombre avec vis. Le mot « START » en noir gras dessus. Il est un peu sale et usé, avec des éclaboussures et coulures de peinture violette. Au clic : le bouton s'enfonce (décalage vers le bas + ombre réduite), puis remonte.
- **LED** : petit point violet lumineux (`#A78BFA` + halo `#8B5CF6`) à côté du bouton. Éteinte quand rien n'est chargé, allumée quand des samples sont prêts, clignote pendant la copie.
- **Autres boutons et champs** (Artiste, Titre, Dossier de sortie, Choisir…) : fond crème `#F2EEE8`, texte violet très foncé `#1E0B3A`, coins arrondis 8 pt, léger biseau (bordure haute claire, ombre basse), police monospace ou à chasse large en majuscules.
- **Étiquettes** : petites majuscules blanches espacées (tracking ~2), comme la sérigraphie d'une pédale : « ARTISTE », « TITRE », « DOSSIER DE SORTIE », « SAMPLES DÉTECTÉS ».
- **Panneaux** (zone de dépôt, liste des samples) : creusés dans le boîtier. Fond violet un peu plus sombre et translucide (noir à 25 %), ombre intérieure, bordure fine claire à 10 %. La zone de dépôt a une bordure en pointillés crème et une icône SF Symbol blanche.
- **Vis** : 4 petites vis métalliques dans les coins de la fenêtre (cercle gris dégradé + fente), purement décoratives.
- **Badges de type** : capsules de couleur avec texte blanc en majuscules : 808 `#9333EA`, KICK `#2563EB`, CLAP `#EAB308`, HIHAT `#0D9488`, OPEN HAT `#06B6D4`, SNARE `#E11D48`, PERC `#F97316`, RIM `#84CC16`, CRASH `#F59E0B`, FX `#EC4899`, VOX `#14B8A6`, LOOP `#6366F1`, AUTRES `#6B7280`.
- **Cases à cocher** : petits carrés crème avec coche violet foncé.

Le style est le même en mode clair et en mode sombre (c'est un objet physique) : ne pas inverser les couleurs.
