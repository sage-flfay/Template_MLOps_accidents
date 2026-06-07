#################################################################################################################
# Localisation : Dockerfile est dans src/api
#                et le fichier d'exclusion .dockerignore est à la racine.
# Initialisation = commande "docker compose build" à la racine:
#   - Lecture du docker-compose.yml pour identifier le contexte (context: .) et le fichier de build.
#   - Filtrage immédiat à lecture de .dockerignore pour exclure tout ce qui y est listé du répertoire réel.
#   - Création temporaire d'une arborescence virtuelle (le contexte) contenant uniquement les fichiers autorisés.
#   - Exécution du Dockerfile en utilisant uniquement cette référence virtuelle.
#     Si un fichier a été ignoré, il est "invisible" pour les commandes COPY ou ADD.
#################################################################################################################


# Utilisation d'une image légère
# Commande docker run --rm python:3.12-slim sh -c "python --version && cat /etc/os-release | grep VERSION_CODENAME"
# Pour avoir la version complète utilisé ici (language-empreinte-OS)
# FROM python:3.12-slim
FROM python:3.12.13-slim-trixie

# Installation de uv. On fige la version (validée sur Ubuntu) pour garantir l'immuabilité du build.
# Le binaire /uv de l'image officielle est copié dans /bin/uv du conteneur. 
COPY --from=ghcr.io/astral-sh/uv:0.11.3 /uv /bin/uv

# Création du répertoire de travail
WORKDIR /app

# Copier les fichiers de dépendances dans le répertoire courant (= de travail)
COPY pyproject.toml uv.lock /app/

# Installer les dépendances 
# --frozen : utiliser le .lock en READ ONLY
# --no-cache : ne pas sauvegarder dans le cache car inutile (et image plus lourde)
# --no-install-project : NE PAS exiger la présence immédiate du dossier src/ (faite dans le COPY . .)
#                        Ainsi, on s'assure de ne pas recommencer la réinstallation complète des 
#                        librairies (couteux en temps) à chaque modification d'une ligne dans scr
RUN uv sync --frozen --no-cache --no-install-project

# Copier TOUS, SAUF ce qui est indiqué dans le .dockerignore (filtre) vers /app/..
# src préférable à src/models en cas de fonctions partagées
COPY src /app/src/

# Ajouter le chemin de l'environnement virtuel créé par uv au PATH
ENV PATH="/app/.venv/bin:$PATH"

# Exposition du port
EXPOSE 8000

# Lancement de l'API (uvicorn trouvé dans le .venv grâce au PATH)
# 0.0.0.0 pour que l'API écoute toutes les interfaces réseau internes au container
# --forwarded-allow-ips="*" : uvicorn voit l'IP réelle du client au lieu de l'IP interne de nginx.
# Indispensable pour la sécurité et les logs (ex: 1000 requêtes d'un coup qui proviennent de nginx,
# sans voir que ce sont tous des clients différent, il peut penser à du piratage et tou bloquer)
CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--forwarded-allow-ips", "*"]
