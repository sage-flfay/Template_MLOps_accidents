import os
import yaml
import mlflow
from mlflow.tracking import MlflowClient

def log_model_hash_to_mlflow():
    if not os.path.exists("dvc.lock"):
        print(f"❌ Erreur critique : {lock_path} introuvable.")
        return

    # 1. Lecture propre du fichier généré et verrouillé par DVC
    with open("dvc.lock", "r") as f:
        dvc_lock = yaml.safe_load(f)

    try:
        # Extraction rigoureuse du hash DVC
        stages = dvc_lock.get('stages', {})
        train_stage = stages.get('train', {})
        outputs = train_stage.get('outs', [])

        model_hash = None
        for out in outputs:
            if out['path'] == 'models/model.joblib':
                model_hash = out['md5']
                break

        if not model_hash:
            print("⚠️ Impossible de trouver le hash de 'models/model.joblib' dans le dvc.lock")
            return

        # Connexion au serveur MLflow local
        client = MlflowClient()

        # Récupération de l'expérience active
        experiment_name = "Accidents_Classification"
        experiment = client.get_experiment_by_name(experiment_name)

        if experiment is not None:
            exp_id = experiment.experiment_id
        else:
            # Au cas où l'expérience n'existe pas encore (Init ou rename)
            exp_id = mlflow.create_experiment(experiment_name)

        # On cherche le tout dernier run créé par train_model.py
        # Correction ici : on trie par date de début décroissante (le plus récent d'abord)
        runs = client.search_runs(
            experiment_ids=[exp_id],
            max_results=1,
            order_by=["attributes.start_time DESC"]
        )

        if not runs:
            print("❌ Aucun run actif trouvé dans MLflow pour cette expérience.")
            return

        last_run_id = runs[0].info.run_id

        # Injection du hash officiel DVC a posteriori
        client.log_param(last_run_id, "dvc_model_hash", model_hash)
        print(f"✅ [MLflow Tracker] Hash officiel DVC mis à jour avec succès : {model_hash}")

    except Exception as e:
        print(f"❌ Erreur lors de l'exécution du tracker : {e}")

if __name__ == "__main__":
    log_model_hash_to_mlflow()
