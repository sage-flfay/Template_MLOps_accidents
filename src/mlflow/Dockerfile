#################################################################################################################
# Localisation : Dockerfile est dans src/mlflow
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
COPY src/mlflow /app/src/mlflow

# Ajouter le chemin de l'environnement virtuel créé par uv au PATH
ENV PATH="/app/.venv/bin:$PATH"

# Exposition du port
EXPOSE 5000

# Si DATABASE_URL n'est pas fournie au lancement dans le .en, alors lien par défaut
ENV DATABASE_URL=postgresql://airflow:airflow@postgres:5432/airflow
# Commande pour lancer le mlflow, avec les options de base de données et d'artefacts
# "--backend-store-uri", "sqlite:////app/mlflow_db/mlflow.db": MLflow prend toutes les infos
# (accuracy, hyperparamètres, ID du run, durée) et les insère comme des lignes dans
# des tables SQL à l'intérieur du fichier mlflow.db
# NB: syntaxe JSON avec appel au Shell ("sh") indispensable pour interpréter les variables
# NB: allowed-hosts et --cors-allowed-origins indispensables pour MLFLOW 3.x suite 
# au passage en version Python 3.12 (MLFLOW 2.x en Python 3.8)
# Ces champs sont signalés via docker logs -f mlflow_server qui tourne sur une fenêtre
# quand on fait make docker-train sur une autre fenêtre

CMD ["sh", "-c", "mlflow server \
     --host 0.0.0.0 \
     --port 5000 \
     --backend-store-uri ${DATABASE_URL} \
     --default-artifact-root /app/artifacts \
     --allowed-hosts '*' \
     --cors-allowed-origins '*'"]
