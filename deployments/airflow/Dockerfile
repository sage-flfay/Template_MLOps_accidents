#################################################################################################################
# Localisation : Dockerfile est dans deployments/airflow
#                et le fichier d'exclusion .dockerignore est à la racine.
# Initialisation = commande "docker compose build" à la racine:
#   - Lecture du docker-compose.yml pour identifier le contexte (context: .) et le fichier de build.
#   - Filtrage immédiat à lecture de .dockerignore pour exclure tout ce qui y est listé du répertoire réel.
#   - Création temporaire d'une arborescence virtuelle (le contexte) contenant uniquement les fichiers autorisés.
#   - Exécution du Dockerfile en utilisant uniquement cette référence virtuelle.
#     Si un fichier a été ignoré, il est "invisible" pour les commandes COPY ou ADD.
#################################################################################################################

# Image Airflow officielle la plus récente et stable et compatible avec l'environnement python 3.12
#FROM apache/airflow:2.8.1
FROM apache/airflow:2.10.5-python3.12

# Installation de uv
COPY --from=ghcr.io/astral-sh/uv:0.11.3 /uv /bin/uv

# On passe en root pour préparer les dossiers si nécessaire
USER root

# Ajout de /app au chemin de recherche Python pour les imports de 'src'
# On prend le ${PYTHONPATH} déjà défini dans l'image auquel on rajoute /app
ENV PYTHONPATH="${PYTHONPATH}:/app"

# NB: airflow est le nom user et aussi le nom groupe définis par défaut dans l'image
# NB: Dans le docker-compose, on définit le user/groupe a utiliser et qui écrasera
# ce user/groupe défini par dans cette image
# airflow a besoin des droits user:groupe pour écrire dans /app
# chown airflow:0 : droits user:groupe donnés à /app; le groupe 0 est root
RUN mkdir -p /app && chown airflow:0 /app

# On définit le répertoire de travail
WORKDIR /app

# Fait sous user root pour le uv pip install
# Copie des fichiers de dépendances avec les droits user et groupe airflowvers
COPY --chown=airflow:0 pyproject.toml uv.lock /app/
# Copie de src car les dags peuvent faire appels aux codes sources
COPY --chown=airflow:airflow src /app/src/

# Environnement Airflow existe déjà dans l'image officielle
# On AJOUTE les dépendances du projet via pip install
# Pour garantir la reproductibilité, on se base sur uv.lock (et non pas requirements.txt)
# qui contient les versions exactes
# --system : installe dans le Python de l'image (en USER root)
# --no-cache: la copie dans l'archive est supprimée car inutile et alourdit l'image
# --frozen: on prend le contenu de uv.lock sans rien modifier
# Le uv.lock est transformé en uv_lock_format_pour_pip.txt qui est au même format que requirements.txt
RUN uv export --frozen --output-file uv_lock_format_pour_pip.txt
RUN uv pip install --no-cache --system -r uv_lock_format_pour_pip.txt
RUN rm uv_lock_format_pour_pip.txt

RUN pip install \
    apache-airflow-providers-cncf-kubernetes>=10.4.2 \
    apache-airflow-providers-postgres>=6.4.1 \
    apache-airflow-providers-common-sql>=1.26.0

# On repasse en utilisateur airflow (pour écrire dans les sous-répertoires de airflow)
USER airflow

# Copie des DAGs vers le chemin standard d'Airflow
# Fait en mode user airflow car spécifique à Airflow
COPY --chown=airflow:airflow deployments/airflow/dags /opt/airflow/dags

# Pas de CMD ! On laisse l'image Airflow utiliser son propre entrypoint pour lancer 
# le webserver ou le scheduler selon le service Docker Compose.
