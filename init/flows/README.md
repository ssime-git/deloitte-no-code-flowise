# Flows pré-construits

Placez ici les fichiers JSON exportés depuis Flowise.

Chaque fichier `.json` sera importé automatiquement au démarrage de la stack via
le service `init` (profil `init`).

## Export depuis Flowise

1. Ouvrir un chatflow dans Flowise
2. Menu → **Export**
3. Sauvegarder le fichier `.json` dans ce dossier

## Import automatique

```bash
docker compose --profile init up -d
```

Les flows déjà présents (même nom) sont ignorés.
