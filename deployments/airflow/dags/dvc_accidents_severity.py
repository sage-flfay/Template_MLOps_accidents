import os
from airflow import DAG
from airflow.utils.task_group import TaskGroup
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator

# from airflow.operators.bash import BashOperator

# Migration DockerOperator → KubernetesPodOperator
# DockerOperator incompatible k3s (pas de daemon Docker dans les pods)
# KubernetesPodOperator crée un pod K8s par tâche — équivalent exact
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import (
    KubernetesPodOperator,
)
from kubernetes.client import models as k8s
from datetime import datetime

# ============================================================
# CONFIGURATION — identique à l'original sauf PROJECT_PATH
# et NETWORK_NAME supprimés (inutiles en K8s)
# ============================================================

CONTAINER_HOME = "/app"
CONTAINER_WORK_DIR = CONTAINER_HOME
CONTAINER_VENV_PATH = f"{CONTAINER_HOME}/.venv"

# Récupérés depuis le ConfigMap app-config injecté dans le pod Airflow
MLFLOW_URI = os.getenv("MLFLOW_TRACKING_URI", "http://mlflow-service:5000")
MLFLOW_EXP = os.getenv("MLFLOW_EXPERIMENT_NAME", "accidents_severity")
PROJECT_NAME = os.getenv("PROJECT_NAME", "accidents_severity")
TRAIN_YEAR = os.getenv("TRAIN_YEAR", "2019")

K8S_NAMESPACE = "accidents-severity"

# Équivalent de IMAGE_NAME = f"{PROJECT_NAME}-runner:1.0"
# En K8s on utilise l'image train (même contenu que runner)
IMAGE_NAME = f"localhost:8081/{PROJECT_NAME}-train:1.0"

# ============================================================
# VARIABLES D'ENVIRONNEMENT POUR LES PODS DE TÂCHES
# Équivalent de mlflow_env + container_venv_env dans l'original
# ============================================================


def make_env_vars():
    """Équivalent de {**mlflow_env, **container_venv_env} du docker-compose."""
    return [
        k8s.V1EnvVar(name="TRAIN_YEAR", value=TRAIN_YEAR),
        # --- mlflow_env ---
        k8s.V1EnvVar(name="MLFLOW_TRACKING_URI", value=MLFLOW_URI),
        k8s.V1EnvVar(name="MLFLOW_EXPERIMENT_NAME", value=MLFLOW_EXP),
        # --- container_venv_env ---
        k8s.V1EnvVar(name="VIRTUAL_ENV", value=CONTAINER_VENV_PATH),
        k8s.V1EnvVar(
            name="PATH",
            value=f"{CONTAINER_VENV_PATH}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        ),
        k8s.V1EnvVar(name="PYTHONPATH", value=CONTAINER_WORK_DIR),
        k8s.V1EnvVar(name="UV_IGNORE_DOT_VENV", value="1"),
        k8s.V1EnvVar(name="GIT_PYTHON_REFRESH", value="quiet"),
        # --- Secrets DagsHub (équivalent .dvc/config.local) ---
        k8s.V1EnvVar(
            name="AWS_ACCESS_KEY_ID",
            value_from=k8s.V1EnvVarSource(
                secret_key_ref=k8s.V1SecretKeySelector(
                    name="dagshub-secret", key="DAGSHUB_ACCESS_KEY_ID"
                )
            ),
        ),
        k8s.V1EnvVar(
            name="AWS_SECRET_ACCESS_KEY",
            value_from=k8s.V1EnvVarSource(
                secret_key_ref=k8s.V1SecretKeySelector(
                    name="dagshub-secret", key="DAGSHUB_SECRET_ACCESS_KEY"
                )
            ),
        ),
    ]


# ============================================================
# VOLUMES K8S
# Équivalent des Mount() du docker-compose :
#   persistance_mounts  → data-pvc + reports-pvc + models-pvc
#   mlflow_volume_mount → mlflow-artifacts-pvc
#   dvc_state_mounts    → embarqués dans l'image (.dvc/, dvc.lock, dvc.yaml)
#   simu_data_web       → embarqué dans l'image (retiré du .dockerignore)
#   src/, dvc.yaml      → embarqués dans l'image
# NB: user_id_mount et group_id_mount supprimés
#     (K8s gère les identités via securityContext)
# ============================================================

k8s_volumes = [
    k8s.V1Volume(
        name="data",
        persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
            claim_name="data-pvc"
        ),
    ),
    k8s.V1Volume(
        name="reports",
        persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
            claim_name="reports-pvc"
        ),
    ),
    k8s.V1Volume(
        name="models",
        persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
            claim_name="models-pvc"
        ),
    ),
    # Équivalent mlflow_volume_mount (type="volume" docker-compose)
    k8s.V1Volume(
        name="artifacts",
        persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
            claim_name="mlflow-artifacts-pvc"
        ),
    ),
]

k8s_volume_mounts = [
    k8s.V1VolumeMount(name="data", mount_path=f"{CONTAINER_WORK_DIR}/data"),
    k8s.V1VolumeMount(name="reports", mount_path=f"{CONTAINER_WORK_DIR}/reports"),
    k8s.V1VolumeMount(name="models", mount_path=f"{CONTAINER_WORK_DIR}/models"),
    k8s.V1VolumeMount(name="artifacts", mount_path=f"{CONTAINER_WORK_DIR}/artifacts"),
]

# ============================================================
# ARGUMENTS COMMUNS KubernetesPodOperator
# Équivalent de common_DockerOperator_args
# ============================================================

common_k8s_args = {
    "namespace": K8S_NAMESPACE,
    "image": IMAGE_NAME,
    "image_pull_policy": "IfNotPresent",
    "env_vars": make_env_vars(),
    "volumes": k8s_volumes,
    "volume_mounts": k8s_volume_mounts,
    # Équivalent auto_remove='force'
    "is_delete_operator_pod": True,
    # Affiche les logs du pod dans les logs Airflow
    "get_logs": True,
    # ServiceAccount avec RBAC pour créer des pods (07-airflow.yaml)
    "service_account_name": "airflow-sa",
}

# ============================================================
# DAG — structure identique à l'original
# ============================================================

with DAG(
    dag_id="dvc_accidents_severity",
    default_args={},
    start_date=datetime(2019, 1, 1),
    schedule_interval="*/2 * * * *",
    catchup=False,
    max_active_runs=1,
    tags=["1-SIMULATION", "2-DVC", "3-Freq=2min", "4-K8s"],
) as dag:

    dag.doc_md = """
    ### 🚀 Mode Simulation K8s
    **Fréquence :** Toutes les 2 minutes.
    **Migration :** DockerOperator → KubernetesPodOperator
    """

    # 1. Init table Postgres — inchangé
    init_db = SQLExecuteQueryOperator(
        task_id="runs_history_table",
        conn_id="postgres_default",
        sql="CREATE TABLE IF NOT EXISTS runs (id SERIAL, date TIMESTAMP, status TEXT);",
    )

    # # 2. Génération params.yaml
    # # Équivalent exact du BashOperator original — même logique,
    # # mais écrit dans AIRFLOW_HOME qui est monté sur le PVC airflow-dags-pvc
    # # Le params.yaml est ensuite lu par chaque pod via le même PVC
    # prepare_params = BashOperator(
    #     task_id="prepare_params_file",
    #     bash_command=(
    #         f'echo "--- PREPARE PARAMS: Setting TRAIN_YEAR to '
    #         f'{{{{ var.value.get("TRAIN_YEAR", "2019") }}}} ---" && '
    #         f'echo "TRAIN_YEAR: {{{{ var.value.get("TRAIN_YEAR", "2019") }}}}" '
    #         f'> /opt/airflow/params.yaml'
    #     )
    # )

    # 3. Pipeline ML
    with TaskGroup("ml_pipeline") as ml_pipeline:

        with TaskGroup("data_preparation") as data_prep:

            # Équivalent : DockerOperator command="dvc repro import"
            # params.yaml copié depuis /opt/airflow/ avant le dvc repro
            import_data = KubernetesPodOperator(
                task_id="dvc_import",
                name="dvc-import",
                **common_k8s_args,
                cmds=["sh", "-c"],
                arguments=[
                    (
                        # TRAIN_YEAR injecté via env_var → params.yaml généré
                        # Équivalent du bind mount sur params.yaml dans docker-compose
                        'echo "TRAIN_YEAR: ${TRAIN_YEAR:-2019}" > params.yaml && '
                        "dvc repro import"
                    )
                ],
            )

            # Équivalent : DockerOperator command="dvc repro process"
            process_data = KubernetesPodOperator(
                task_id="dvc_process",
                name="dvc-process",
                **common_k8s_args,
                cmds=["sh", "-c"],
                arguments=[
                    (
                        'echo "TRAIN_YEAR: ${TRAIN_YEAR:-2019}" > params.yaml && '
                        "dvc repro process"
                    )
                ],
            )

            import_data >> process_data

        with TaskGroup("model_train_and_eval") as model_workflow:

            # Équivalent : DockerOperator command="dvc repro train"
            train_model = KubernetesPodOperator(
                task_id="dvc_train",
                name="dvc-train",
                **common_k8s_args,
                cmds=["sh", "-c"],
                arguments=[
                    (
                        'echo "TRAIN_YEAR: ${TRAIN_YEAR:-2019}" > params.yaml && '
                        "dvc repro train"
                    )
                ],
            )

            # Équivalent : DockerOperator command="dvc repro evaluate"
            evaluate_model = KubernetesPodOperator(
                task_id="dvc_evaluate",
                name="dvc-evaluate",
                **common_k8s_args,
                cmds=["sh", "-c"],
                arguments=[
                    (
                        'echo "TRAIN_YEAR: ${TRAIN_YEAR:-2019}" > params.yaml && '
                        "dvc repro evaluate"
                    )
                ],
            )

            train_model >> evaluate_model

        data_prep >> model_workflow

    # 4. Enregistrement succès — inchangé
    record_success = SQLExecuteQueryOperator(
        task_id="runs_history_record",
        conn_id="postgres_default",
        sql="INSERT INTO runs (date, status) VALUES (NOW(), 'SUCCESS');",
    )

    init_db >> prepare_params >> ml_pipeline >> record_success
