import os
from airflow import DAG
from airflow.utils.task_group import TaskGroup
from airflow.decorators import task
from airflow.providers.docker.operators.docker import DockerOperator
#from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from docker.types import Mount
from datetime import datetime
from pathlib import Path
# Airflow tab Admin choix Variable pour donner la valeur
from airflow.models import Variable
from airflow.operators.bash import BashOperator

# Récupèrer l'UID et le GID de l'utilisateur qui fait tourner Airflow (ubuntu)
# Par défaut 1000 si jamais on est dans un environnement restreint
# Le but est de l'utiliser dans les DockerOperators qui par défaut utilise root,
# ce qui est une défaillance de sécurité
UID = os.getuid()
GID = os.getgid()

# Configuration du chemin
# Remonte par rapport au fichier actuel pour trouver la racine
PROJECT_PATH = "/home/ubuntu/Template_MLOps_accidents"
# DANGER DU CHEMIN RELATIF qui n'est pas lu à partir du fichier dans Ubuntu
# mais à partir du container Sceduler, ce qui ne permet pas de trouver les
# fichiers dvc nécessaire pour les dags
# PROJECT_PATH = Path(__file__).resolve().parent.parent.parent.parent.as_posix()

# Chemins internes au Container Docker
CONTAINER_HOME = "/app"
# CONTAINER_WORK_DIR = f"{CONTAINER_HOME}/working_dir"
CONTAINER_WORK_DIR = f"{CONTAINER_HOME}"
CONTAINER_VENV_PATH = f"{CONTAINER_HOME}/.venv"

# Chemin "interne" à Airflow (utilisé pour les commandes Bash)
# AIRFLOW_HOME est déjà défini dans le conteneur Airflow
AIRFLOW_PATH = os.getenv("AIRFLOW_HOME", "/opt/airflow")

# Récupération de la variable injectée par le docker-compose (airflow environnement)
# On met une valeur par défaut au cas où
PROJECT_NAME = os.getenv("PROJECT_NAME", "accidents_severity")
# On récupère l'url pour le docker (donc http://service_name:port)
MLFLOW_URI = os.getenv("MLFLOW_TRACKING_URI", "http://mlflow_server:5000")
# On récupère le nom de l'expérience
MLFLOW_EXP = os.getenv("MLFLOW_EXPERIMENT_NAME", "accidents_severity")
# On reconstruit le nom du réseau airflow comme dans docker-compose.yml
NETWORK_NAME = f"{PROJECT_NAME}_airflow-net"

# image construite dans le Makefile, qui se siute à la racine
IMAGE_NAME = f"{PROJECT_NAME}-runner:1.0"

# Récupération de la variable (fait à chaque fois que Airflow scanne les Dag
# train_year = Variable.get("TRAIN_YEAR", default_var="2019")
# print(f"--- DAG PARSING: TRAIN_YEAR is set to {train_year} ---")

# NB: MLFLOW_EXPERIMENT_NAME
mlflow_env = {
    # Airflow, Tab Admin, Choix Variable, key à rechercher: TRAIN_YEAR
    # "TRAIN_YEAR": "{{ var.value.TRAIN_YEAR }}",
    # Ne sert à plus rien vu qu'on monte le bind sur params.yaml
    # et vu qu'on l'initialise dans le BashOperator.
    # En réalité, je ne sais pas si même avant c'était util car
    # on passait déjà via params.yaml
    # "TRAIN_YEAR": "{{ var.value.get('TRAIN_YEAR', '2019') }}",
    "MLFLOW_TRACKING_URI": MLFLOW_URI,
    "MLFLOW_EXPERIMENT_NAME": MLFLOW_EXP,
}

# Variables pour forcer l'usage du venv interne du docker
# On évite les téléchargements lors des runs d'airflow
# On garantit bien l'utilisation du docker en mode isolé
container_venv_env = {
    "VIRTUAL_ENV": CONTAINER_VENV_PATH,
    "PATH": f"{CONTAINER_VENV_PATH}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    # Utilisé par l'interpréteur python lors de l'import
    # pour aussi chercher à partir de ce chemin
    "PYTHONPATH": CONTAINER_WORK_DIR,
    # Crucial pour que uv ne cherche pas de .venv dans working_dir
    # Evite le ghosting où parfois uv est utilisé dans l'image
    "UV_IGNORE_DOT_VENV": "1",
}

# Montage du volume pour que le container accède au code et aux données
# bind (<=> pont bidirectionnel): source et target deviennent de miroirs,
# tout update sur la source ou target se retrouve sur la target ou source
# NB: le target est /app/working_dir et non pas /app. SINON le répertoire /app
# du docker (IMAGE_NAME) serait SUBSTITUé/MASQUé par celui du target et les outils/scr
# ne seraient pas cherchés dans l'IMAGE mais dans Ubuntu, ce qui serait une erreur
# et rendrait l'utilisation de l'image INUTILE
# NB: Pont trop global: en fait, tout est fait sur ubuntu. L'image devient inutile!!!
# project_mount = Mount(source=PROJECT_PATH, target=CONTAINER_WORK_DIR, type="bind")

# Dockerfile crée son propre .venv (espace vide) grâce à 'source' à None.
# Ainsi, il ne modifie plus celui d'ubuntu evitant de générer des conflits sur ubuntu.
# Ainsi isolation complète du Docker
# ERROR: on n'utilise plus le .venv de l'image et donc téléchargement systématique
# sur internet à chaque run de Airflow et on perd donc toute l'utilité du Docker
#venv_docker = Mount(source=None, target="/app/working_dir/.venv", type="volume")

# Définition des ponts par catégories
# NB: on ne monte que les ponts utiles, on peut garder CONTAINER_WORK_DIR = /app.
# Ainsi tout ce qui n'est pas défini ci-dessous (et notemment /app/.ven) sera
# bien pris dans l'image et non pas sur le terminal local (ici ubuntu)
def create_mount(path):
    """Génère un bind mount entre l'hôte et le conteneur."""
    path_target = path
    return Mount(
        source=f"{PROJECT_PATH}/{path}",
        target=f"{CONTAINER_WORK_DIR}/{path}",
        type="bind"
    )

# Configuration chirurgicale compacte
# persistance_mounts = [create_mount(p) for p in ["data", "mlflow_artifacts",
# "reports"]]
# persistance_mounts = [create_mount(p) for p in ["data", "reports", "simu_data_web"]]
# Ajout de models utilisé par dvc pour stocker le modèle
persistance_mounts = (
    [create_mount(p) for p in ["data", "reports", "simu_data_web", "models"]]
)
dvc_state_mounts = [create_mount(p) for p in [".dvc", "dvc.lock", "params.yaml"]]
# Seulement utile pour le débug. En mode produciton on peut le supprimer
# Warning: modif à librairies constantes sinon conflit
# dev_mounts = [create_mount(p) for p in ["src", "dvc.yaml", "models"]]
dev_mounts = [create_mount(p) for p in ["src", "dvc.yaml"]]

# On remplace "mlflow_artifacts" par le volume définit dans le docker-compose.yml
# Ainsi dès que le volume est updaté par airflow, mlflow et api et train ont aussi
# cet update. Type "volume" pour indiquer à Docker que c'est lui qui gère ce volume
# en interne vu qu'il est déclaré dans le docker-compose.yml
mlflow_volume_mount = Mount(
    source=f"{PROJECT_NAME}_mlflow-artifacts-volume",
    target=f"{CONTAINER_WORK_DIR}/artifacts",
    # C'est un volume Docker
    type="volume"
)

# On prête ces infos pour fournir le nom utilisateur
# pour les id fournis dans dans os.getuid et os.getgid
user_id_mount = Mount(
    source='/etc/passwd', target='/etc/passwd', type='bind', read_only=True
)

# NB: En vérifiant, on voit que le groupe est toujours à root mais il est important
# de le garder car en interne il sait que le groupe est bien le user
# NB: Même si Docker force souvent le GID à 'root' sur l'hôte, ce montage est CRUCIAL :
# Identité: permet au conteneur de résoudre l'ID 1000 en nom de groupe (ex: 'ubuntu')
# Stabilité: évite que les librairies (OS, MLflow) ne plantent en cherchant
# un groupe "fantôme".
# Sécurité: maintient le processus dans un environnement non-root cohérent.
group_id_mount = Mount(
    source='/etc/group', target='/etc/group', type='bind', read_only=True
)

common_DockerOperator_args = {
    'image': IMAGE_NAME,
    'network_mode': NETWORK_NAME,
    'environment': {**mlflow_env, **container_venv_env},
    # On garantit que les DockerOperator utiliseront le usr user et non pas root qui
    # est le user par défaut et ainsi éviter tout conflit et défaillance de sécurité
    'user': f"{UID}:{GID}",
    # mounts ne supporte que le format liste: on concatène les listes
    'mounts': (
        persistance_mounts +
        dvc_state_mounts +
        dev_mounts +
        [mlflow_volume_mount, user_id_mount, group_id_mount]
    ),
    # Equivalent à faire cd /app/working_dir
    'working_dir': CONTAINER_WORK_DIR,
    # Une fois terminée, la tâche s'auto-détruit
    # Version récente de DockerOperator force <=> True
    'auto_remove': 'force',
    # Permet à Airflow (dans Docker) de parler au Docker de la machine
    # Ubuntu pour lancer les containers de tâches.
    'docker_url': "unix://var/run/docker.sock",
    # Ne pas demander à Ubuntu de monter quoi que ce soit d'automatique
    # dans /tmp. Ce n'est pas la peine car Airflow fournit déjà tout ce
    # qu'il faut via project_mount
    'mount_tmp_dir': False,
}

with DAG(
    dag_id="dvc_accidents_severity",
    # Arguments appliqués automatiquement à chaque DockerOperator
    # Donc inutile de le remettre pour chaque DockerOperator
    # Simplifie le DockerOperator
    default_args=common_DockerOperator_args,
    start_date=datetime(2019, 1, 1),
    # end_date=datetime(2019, 12, 31), # retiré pour accepter données plus récentes
    # Entrainement périodique mensuelle ou annuelle
    # schedule_interval='@monthly', # schedule_interval='@yearly',
    # catchup=True, # exécute ce qui est dans data/raw
    # Pour la simulation, on lance un run toutes les 2mn
    schedule_interval="*/2 * * * *",
    # Pour ne par lancer milliers de run pour rattraper l'année
    catchup=False,
    # Pas plus d'un run à la fois pour éviter les risques de conflits/saturation
    # Ainsi le dag n'est jamais lancé plusieurs fois en parallèle
    max_active_runs=1,
    tags=["1-SIMULATION", "2-DVC", "3-Freq=2min"],
) as dag:

    dag.doc_md = """
    ### 🚀 Mode Simulation - data/raw updaté manuellement
    **Fréquence :** Toutes les 2 minutes.
    **Objectif :** Tester la détection de nouvelles données par DVC et l'envoi vers MLflow.
    """

    # 1. Préparation/Init de la table de suivi en BDD
    # PostgresOperator remplacé par SQLExecuteQueryOperator
    init_db = SQLExecuteQueryOperator(
        task_id="runs_history_table",
        #postgres_conn_id="postgres_default",
        conn_id="postgres_default",
        sql="CREATE TABLE IF NOT EXISTS runs (id SERIAL, date TIMESTAMP, status TEXT);"
    )

    # Etape de préparation pour partager la variable avec tous les dockers
    # On prend le TRAIN_YEAR défini dans Airflow/Admin, on le place dans
    # le fichier params.yaml en l'écrasant systématiquement
    # le bind avec params.yaml est monté pour les Dockers.
    # Ainsi, pour chaque Docker qui fait dvc ..., le dvc.yaml est lu et
    # DVC sait qu'il doit chercher le params.yaml pour obtenir la valeur
    # de TRAIN_YEAR
    prepare_params = BashOperator(
        task_id='prepare_params_file',
        bash_command=(
            # Ici quand on clique sur le bouton = flèche pour Trigger DAG
            #f'echo "TRAIN_YEAR: {{{{ dag_run.conf.get("year", 2019) }}}}"'
            # Ici, on passe par la variable dans Admin/Variable
            # Le premier echo est pour l'affichage dans les logs
            f'echo "--- PREPARE PARAMS: Setting TRAIN_YEAR to '
            f'{{{{ var.value.get("TRAIN_YEAR", "2019") }}}} ---" && '
            f'echo "TRAIN_YEAR: {{{{ var.value.get("TRAIN_YEAR", "2019") }}}}" '
            f'> {AIRFLOW_PATH}/params.yaml'
        )
    )

    # 2. Pipeline Machine Learning (Containers)
    with TaskGroup("ml_pipeline") as ml_pipeline:
        # Groupe DATA PREPARATION (Import + Process)
        with TaskGroup("data_preparation") as data_prep:
            import_data = DockerOperator(
                task_id="dvc_import",
                command="dvc repro import",
                # \" pour confirmer que la chaine de caratères commence bien ici
                # et se temine bien au prochain \"
                # var.value.TRAIN_YEAR récupère la valeur de la key définie dans
                # le webserver Airflow partie Admin/Variable
                # Devient obsolète car création du BashOperator
                #command=(
                #    "sh -c \"echo 'TRAIN_YEAR: "
                #    "{{ var.value.get('TRAIN_YEAR', '2019') }}' "
                #    "> params.yaml && dvc repro import\""
                #)
            )

            process_data = DockerOperator(
                task_id="dvc_process", command="dvc repro process",
            )

            import_data >> process_data

        # Groupe MODEL TRAINING (Train + Evaluate)
        with TaskGroup("model_train_and_eval") as model_workflow:
            train_model = DockerOperator(
                task_id="dvc_train",
                # On le force à recommencer
                command="dvc repro train",
            )

            # Dans ton TaskGroup ml_pipeline
            evaluate_model = DockerOperator(
                task_id="dvc_evaluate", command="dvc repro evaluate",
            )

            train_model >> evaluate_model

        # Chaînage
        data_prep >> model_workflow

    # 3. Enregistrement du succès dans Postgres
    # PostgresOperator remplacé par SQLExecuteQueryOperator
    record_success = SQLExecuteQueryOperator(
        task_id="runs_history_record",
        # postgres_conn_id="postgres_default",
        conn_id="postgres_default",
        sql="INSERT INTO runs (date, status) VALUES (NOW(), 'SUCCESS');"
    )

    init_db >> prepare_params >> ml_pipeline >> record_success
