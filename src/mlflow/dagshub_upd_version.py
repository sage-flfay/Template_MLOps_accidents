import os
import mlflow
import yaml
import time
import json

PROJECT_NAME = os.environ.get("PROJECT_NAME", "Accidents_Severity")

def get_experiment_with_retry(name, retries=3):
    for i in range(retries):
        experiment = mlflow.get_experiment_by_name(name)
        if experiment is not None:
            return experiment
        time.sleep(1) # On n'attend que si c'est nécessaire !
    return None

def run_upd_on_dagshub():
    # Configuration du serveur distant dagshub
    # NB: MLflow lit automatiquement ces variables d'environnement définies dans le dag
    # (MLFLOW_TRACKING_USERNAME et MLFLOW_TRACKING_PASSWORD)
    mlflow.set_tracking_uri(
        "https://dagshub.com/ntepal/Template_MLOps_accidents.mlflow"
    )

    # PROJECT_NAME est défini dans l'env du dag qui appelle cette fonction
    # Idempotent: créé ou récupré
    mlflow.set_experiment(PROJECT_NAME)

    CONTAINER_MODEL_PATH = "/app/data/mlruns_latest"

    # 1. Lire la version directement depuis le fichier local
    with open(f"{CONTAINER_MODEL_PATH}/registered_model_meta", "r") as f:
        meta = yaml.safe_load(f)
        current_version = str(meta.get('model_version'))

    # 2. Récupération de l'expérience et de l'ID
    # experiment = mlflow.get_experiment_by_name(PROJECT_NAME)
    # Retenter en cas de problème passager avec le dagshub
    experiment = get_experiment_with_retry(PROJECT_NAME)
    if experiment is None:
        print(f"Expérience {PROJECT_NAME} introuvable.")
        return
    experiment_id = experiment.experiment_id

    # 3. Vérifier si cette version existe déjà sur DagsHub
    client = mlflow.tracking.MlflowClient()
    runs = client.search_runs(
        experiment_ids=[experiment_id],
        # Recherche si présence de la version. Si non runs est vide
        filter_string=f"tags.model_version = '{current_version}'"
    )

    if len(runs) > 0:
        print(
            f"Version {current_version} déjà présente sur DagsHub. "
            "Rien à faire. ✅"
        )
        return

    # 4. Si on arrive ici, c'est que la version n'existe pas : on crée le run
    print(f"Nouvelle version {current_version} détectée. Upload en cours...")
    run_name_dagshub = f"{PROJECT_NAME}_version_{current_version}"

    try:
        with mlflow.start_run(run_name=run_name_dagshub):
            # Le tag est utilisé pour éviter d'inscrire des runs à chaque fois
            # La vérification est faite ci-dessus
            mlflow.set_tag("model_version", current_version)

            # Lecture et log des métriques/params depuis le JSON
            params_metrics_file = f"{CONTAINER_MODEL_PATH}/params_and_metrics.json"
            if os.path.exists(params_metrics_file):
                print(f"DEBUG: le fichier existe = {params_metrics_file}")
                with open(params_metrics_file, "r") as f:
                    # On récupère le dictionnaire
                    data = json.load(f)
                    # Le json peut être imprécis. Par sécurité, on garantit le
                    # format 100% compatible avec mlflow
                    if "params" in data:
                        # On s'assure que les params sont bien du texte
                        print(f"DEBUG: params présent dans {params_metrics_file}")
                        params = {k: str(v) for k, v in data["params"].items()}
                        print(f"DEBUG: Paramètres nettoyés : {params}")
                        mlflow.log_params(params)
                    if "metrics" in data:
                        print(f"DEBUG: params présent dans {params_metrics_file}")
                        # On force TOUTES les métriques à être des float purs
                        metrics = {k: float(v) for k, v in data["metrics"].items()}
                        print(f"DEBUG: Métriques nettoyés : {metrics}")
                        mlflow.log_metrics(metrics)
            # Log des artefacts (les 8 fichiers sont uploadés sur le S3 de DagsHub
            # Sur le dagshub, ils sont stockés dans le sous-dossier model de Artifact
            mlflow.log_artifacts(CONTAINER_MODEL_PATH, artifact_path="model")
            print("✅ Nouvelle version dans Dagshub réussie !")
    except Exception as e:
        print(
            f"⚠️ L'upload vers DagsHub a échoué, mais le pipeline continue. "
            f"Erreur : {e}"
        )

if __name__ == "__main__":
    run_upd_on_dagshub()
