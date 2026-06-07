#################################################################################################################
# Localisation : Dockerfile à la racine
#                et le fichier d'exclusion .dockerignore est à la racine.
# TYPE : Runner MLOps (Image Éphémère)
# WARNING: Ne PAS déclarer ce runner comme un 'service' dans le docker-compose.yml.
# Cette image est conçue pour une utilisation "On-Demand" via l'Airflow DockerOperator.
# FLUX : 
# 1. Build via Makefile -> Image stockée dans le registre local.
# 2. Exécution via Airflow -> Création d'un container temporaire qui s'autodétruit après le job.
#
# Initialisation = commande "docker compose build" à la racine:
#   - Lecture du docker-compose.yml pour identifier le contexte (context: .) et le fichier de build.
#   - Filtrage immédiat à lecture de .dockerignore pour exclure tout ce qui y est listé du répertoire réel.
#   - Création temporaire d'une arborescence virtuelle (le contexte) contenant uniquement les fichiers autorisés.
#   - Exécution du Dockerfile en utilisant uniquement cette référence virtuelle.
#     Si un fichier a été ignoré, il est "invisible" pour les commandes COPY ou ADD.
#################################################################################################################


# -------------------------------------------------------
# ------ Base et outils systèmes. NE CHANGE JAMAIS ------
# -------------------------------------------------------
# Utilisation d'une image légère
# Commande docker run --rm python:3.12-slim sh -c "python --version && cat /etc/os-release | grep VERSION_CODENAME"
# Pour avoir la version complète utilisé ici (language-empreinte-OS)
# FROM python:3.12-slim
FROM python:3.12.13-slim-trixie
# Installation des outils système (Git, curl, etc.)
# Ils ne changent jamais, donc Docker mettra cette couche en cache une fois pour toutes.
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
# Installation de uv. On fige la version (validée sur Ubuntu) pour garantir l'immuabilité du build.
# Le binaire /uv de l'image officielle est copié dans /bin/uv du conteneur. 
COPY --from=ghcr.io/astral-sh/uv:0.11.3 /uv /bin/uv

# -------------------------------------------------------
# ------ Préparation de l'environnement de travail ------
# -------------------------------------------------------
# Création du répertoire de travail
WORKDIR /app
# On prépare TOUS les points d'ancrage (dossiers) utilisés par les dags
# Dans le dag, on monte un pont (bind) pour chacun de ceux ci-dessous
# Ainsi on garantit la structure pour l'utilisation par les dags
RUN mkdir -p data reports simu_data_web .dvc
# On créer des fichiers vides pour les verrous/params 
# pour être sûr que Docker ne les transforme pas en dossiers
RUN touch dvc.lock params.yaml

# -------------------------------------------------------
# --------------------- Dépendances ---------------------
# -------------------------------------------------------
# Copier les fichiers de dépendances dans le répertoire courant (= de travail)
COPY pyproject.toml uv.lock /app/
# Installer les dépendances 
# --frozen : utiliser le .lock en READ ONLY
# --no-cache : ne pas sauvegarder dans le cache car inutile (et image plus lourde)
# --no-install-project : NE PAS exiger la présence immédiate du dossier src/ (faite dans le COPY . .)
#                        Ainsi, on s'assure de ne pas recommencer la réinstallation complète des 
#                        librairies (couteux en temps) à chaque modification d'une ligne dans scr
RUN uv sync --frozen --no-cache --no-install-project

# -------------------------------------------------------
# -------- Code source et installation locale -----------
# -------------------------------------------------------
# Copier TOUS vers /app/
COPY . /app/
# Installation du projet en mode éditable (-e).
# Le "." indique à uv/pip que la racine du projet est le répertoire actuel (WORKDIR /app).
# Cela crée un lien logique permettant à Python d'importer les modules depuis /app,
# ce qui, couplé avec le "bind mount" du volume dans le DAG, garantit que
# le code modifié sur la VM est immédiatement pris en compte par le conteneur.
RUN uv pip install -e .
# Ajouter le chemin de l'environnement virtuel créé par uv au PATH
ENV PATH="/app/.venv/bin:$PATH"

# -------------------------------------------------------
# ---------------------- Commande -----------------------
# -------------------------------------------------------
# Commande par défaut (exécutée si aucune commande n'est fournie par l'orchestrateur).
# 1. Performance : Appel direct de 'dvc' via le PATH (évite l'overhead de vérification de 'uv run').
# 2. Immuabilité : Garantit l'utilisation de l'environnement scellé lors du build,
#    évitant que 'uv' ne tente de synchroniser le runtime avec un volume monté (drift).
CMD ["dvc", "repro"]
