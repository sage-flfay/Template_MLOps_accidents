#################################################################################################################
# Localisation : Dockerfile est dans src/monotoring pour l'image evidently
#                et le fichier d'exclusion .dockerignore est à la racine.
# Initialisation = commande "docker compose build" à la racine:
#   - Lecture du docker-compose.yml pour identifier le contexte (context: .) et le fichier de build.
#   - Filtrage immédiat à lecture de .dockerignore pour exclure tout ce qui y est listé du répertoire réel.
#   - Création temporaire d'une arborescence virtuelle (le contexte) contenant uniquement les fichiers autorisés.
#   - Exécution du Dockerfile en utilisant uniquement cette référence virtuelle.
#     Si un fichier a été ignoré, il est "invisible" pour les commandes COPY ou ADD.
#################################################################################################################


# Utilisation d'une image légère
FROM python:3.10.20-slim

# Installation de uv. On fige la version (validée sur Ubuntu) pour garantir l'immuabilité du build.
# Le binaire /uv de l'image officielle est copié dans /bin/uv du conteneur. 
COPY --from=ghcr.io/astral-sh/uv:0.11.3 /uv /bin/uv

# Création du répertoire de travail
WORKDIR /app
RUN mkdir -p /app/monitoring

# Copier les fichiers de dépendances dans le répertoire courant (= de travail)
# Le .venv est généré dans src/monitoring. On garde donc la même structure
COPY src/monitoring/pyproject.toml /app/monitoring/pyproject.toml
COPY src/monitoring/uv.lock /app/monitoring/uv.lock

# Installer les dépendances 
# --frozen : utiliser le .lock en READ ONLY
# --no-cache : ne pas sauvegarder dans le cache car inutile (et image plus lourde)
# --no-install-project : NE PAS exiger la présence immédiate du dossier src/ (faite dans le COPY . .)
#                        Ainsi, on s'assure de ne pas recommencer la réinstallation complète des 
#                        librairies (couteux en temps) à chaque modification d'une ligne dans scr
RUN uv sync --frozen --no-cache --project /app/monitoring --no-install-project

# Copier TOUS, SAUF ce qui est indiqué dans le .dockerignore (filtre) vers /app/..
# src préférable à src/models en cas de fonctions partagées
COPY src /app/src/

# Ajouter le chemin de l'environnement virtuel créé par uv au PATH
ENV PATH="/app/monitoring/.venv/bin:$PATH"

# Exposition du port
EXPOSE 8000

# On appelle directement le module UI d'Evidently.
# Note : comme 'evidently' est dans pyproject.toml, il est installé dans .venv
# Donc si pas de command dans le docker-compose.yaml, on affiche la démo pour vérifier que ça marche bien
CMD ["evidently", "ui", "--demo-projects", "all", "--host", "0.0.0.0"]
