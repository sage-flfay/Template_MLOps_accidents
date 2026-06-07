import os
import pandas as pd
import logging
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset, DataQualityPreset
from evidently.test_preset import (
    DataDriftTestPreset,
    DataQualityTestPreset,
    #DataStabilityTestPreset,
)
from evidently.tests import TestColumnValueMean
from evidently.ui.workspace import Workspace
from evidently.test_suite import TestSuite
from evidently.pipeline.column_mapping import ColumnMapping
from datetime import datetime
import time
import warnings
import numpy as np
import json

#import sys
# Ajouter le dossier parent (/app) au chemin de recherche de Python
# Pour que le src.api.config se fasse depuis /app
# et non pas le répertoire courant
#sys.path.append('/app')
# On importe toutes les infos de config pour les donner au HTML
#from src.api.config import FEATURES
# Le FastApi sert de passerelle via /api/metrics/ pour que Evidently
# puisse transmettre le status du drift à Prometheus
# Pas possible car l'image FastApi et Evidently sont différentes et
#from src.api.main import DRIFT_STATUS


# On ignore spécifiquement les warnings de division par zéro de numpy
warnings.filterwarnings('ignore', category=RuntimeWarning, module='numpy')

# Ce code est relancé périodiquement.
# La seule façon de ne pas refaire ce qui est inutile est de créer un fichier témoin
# On le stocke dans le répertoire temporaire du container
FLAG_FILE = "/tmp/env_validated.flag"

# Configuration du logging
logging.basicConfig(level=logging.INFO)

def check_environment(base_path: str):
    """Vérifie que les dossiers nécessaires existent et sont accessibles."""
    # heartbeat est dans evidently_monitor_daemon.py

    # Si on a déjà validé, on sort immédiatement
    if os.path.exists(FLAG_FILE):
        return

    #sub_dirs = ["snapshots", "reports", "flags", "heartbeat"]
    sub_dirs = ["reports"]

    for sub in sub_dirs:
        # Construction du chemin réel
        directory = os.path.join(base_path, sub)
        # Vérification de l'existence
        if not os.path.exists(directory):
            raise FileNotFoundError(
                f"Répertoire manquant : {directory}. "
                "Veuillez vérifier que les volumes sont "
                "bien montés dans docker-compose.yaml"
            )

        # Test d'écriture (accès en écriture)
        if not os.access(directory, os.W_OK):
            raise PermissionError(
                f"Le dossier {directory} n'est pas accessible en écriture. "
                "Vérifiez les permissions sur la machine hôte (chown/chmod)."
            )

        print(f"Environnement {directory} validé avec succès.")

    # Si tout est OK, on crée le fichier pour "mémoriser" la réussite
    with open(FLAG_FILE, 'w') as f:
        f.write(
            "Les répertoires sont présents. Intutile de revérifier "
            "à chaque fois dans src/monitoring/evidently_monitor.py "
        )
    print(f"Environnement validé et mémorisé sur le container dans {FLAG_FILE}.")


def create_ws_project(ws_name: str, project_name: str, project_description: str):
    # Création/intialisation ou récupération du workspace.
    # Une fois créé/initialisé, on ne fait que récupérer
    ws = Workspace.create(ws_name)
    # ws = Workspace(ws_name) ==> on indente à chaque fois et pb

    # On cherche explicitement dans la liste des projets existants
    # Donc même si le projet est temporairement verrouillé, cela
    # n'impacte pas
    project = None
    for p in ws.list_projects():
        if p.name == project_name:
            project = p
            logging.info(f"Projet '{project_name}' trouvé avec succès.")
            break

    # Créer uniquement si strictement nécessaire
    if project is None:
        project = ws.create_project(project_name)
        project.description = project_description
        project.save()
        logging.info(f"Projet '{project_name}' créé et sauvegardé avec succès.")
        # Petit délai pour laisser le système de fichier marquer la création
        time.sleep(2)

    return ws, project

def create_and_run_test_suite(ref_data, curr_data, save_report=True):
    """
    Exécute une suite complète : Qualité, Drift statistique et Règles métier.
    """
    # fmt: off
    # NB: la commande ci-dessus empêche BLACK (vérificateur de code) de transformer
    # ces 2 listes en ligne en des listes en colonne (ce qui devient illisible)
    # Configuration des colonnes
    cat_features = [
        "place", "catu", "sexe","secu1", "catv", "obsm", "motor",
        "catr", "circ", "surf", "situ", "jour", "mois", "lum",
        "dep", "com", "agg_", "int", "atm", "col"
    ]

    num_features = [
        "year_acc", "victim_age", "vma", "lat", "long", "hour",
        "nb_victim", "nb_vehicules"
    ]
    # fmt: on
    # NB: commande ci-dessus pour indiquer que BLACK continue le check normalement

    # Mapping pour Evidently
    column_mapping = ColumnMapping(
        categorical_features=cat_features,
        numerical_features=num_features,
        #prediction="predict_result",
        #task="classification",
    )

    test_suite = TestSuite(tests=[
        # Audit général
        DataQualityTestPreset(),
        # Drift sur les variables
        DataDriftTestPreset(),
        # Règle métier exemple
        TestColumnValueMean(column_name='victim_age', gte=0, lte=120),
    ])

    test_suite.run(reference_data=ref_data, current_data=curr_data, column_mapping=column_mapping)

    if save_report:
        timestamp = datetime.now().strftime("%Y-%m-%d")
        test_suite_filename = f"/app/data/evidently/reports/test_suite_{timestamp}.html"
        test_suite.save_html(test_suite_filename)
        logging.info(f"Rapport HTML généré dans {test_suite_filename}")

    return test_suite


def run_monitoring():

    default_path = "/app/data/evidently"
    default_ws_name = "/app/data/evidently/accidents_severity-workspace"
    default_project_name = "accidents_severity"
    PATH = os.getenv("EVIDENTLY_PATH", default_path)
    WS_NAME = os.getenv("EVIDENTLY_WORKSPACE", default_ws_name)
    PROJECT_NAME = os.getenv("PROJECT_NAME", default_project_name)
    PROJECT_DESCRIPTION = "Evidently Accidents Dashboards"

    # S'assurer que l'environnement est bon sinon inutile de continuer
    check_environment(PATH)

    ws, project = create_ws_project(WS_NAME, PROJECT_NAME, PROJECT_DESCRIPTION)

    # On prend X_test.csv car pas utilisé pour générer le modèle
    ref_path_file = "/app/data/preprocessed/X_test.csv"
    cur_path_file = "/app/data/users/fastapi_data.csv"

    # ... au début de run_monitoring() ...
    if not os.path.exists(cur_path_file):
        print(
            "En attente de données : "
            "aucun fichier de production trouvé pour le moment."
        )
        # Donc on ne vas pas plus loin
        return

    # ---- Chargement
    #ref_data = pd.read_csv(ref_path_file)
    df_full = pd.read_csv(ref_path_file)
    # 1. On réserve 10% pour la Référence (Fixed)
    ref_data = df_full.sample(frac=0.1, random_state=42)
    # 2. On prend les 90% restants pour créer la source du "Current"
    df_remaining = df_full.drop(ref_data.index)
    #current_data = pd.read_csv(cur_path_file)
    # -------------------------------------------------------------------------
    # NB: Les données issues du fastapi_data sont peu nombreuses car produites
    # manuellement. Or pendant cette phase, le datadrift s'active de facto dû
    # à un manque suffisant de données et donc ce n'est pas significatif.
    # Pour le tromper pendant la phase de remplissage du fastapi_data,
    # on ajoute une partie des données aussi issue du X_test.csv comme suit:
    # On récupère le fichier fastapi_data.csv
    fastapi_data = pd.read_csv(cur_path_file)
    # On prend 3% du X_test non utilisé par le ref_data
    current_base_data = df_remaining.sample(frac=0.03, random_state=42)
    # Important: dans cet ordre, le fastapi_data est APRèS current_base_data
    current_data = pd.concat([current_base_data, fastapi_data], ignore_index=True)
    # Buffer management: on garde les 600 derniers enregistrements
    # Et comme fastapi_data est après current_base_data, on conserve bien les
    # données issues de fastapi_data pour remplir ce fichier
    current_data = current_data.tail(600)

    # ---- Analyse
    # Calcul du drift
    # Initialize the report with desired metrics
    report = Report(metrics=[DataDriftPreset(),DataQualityPreset()])
    # Run the report
    report.run(reference_data=ref_data, current_data=current_data)

    # Sauvegarde du rapport en HTML (Pour l'instant 1 seul par jour)
    # timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    timestamp = datetime.now().strftime("%Y-%m-%d")
    report_filename = f"{PATH}/reports/drift_report_{timestamp}.html"
    report.save_html(report_filename)
    logging.info(f"Rapport HTML généré dans {report_filename}")

    try:
        ws.add_report(project.id, report)
        logging.info(f"Nouveau rapport ajouté au projet {PROJECT_NAME}.")
    except Exception as e:
        logging.error(f"ERREUR lors de l'ajout du rapport au Workspace: {e}")

    test_suite = create_and_run_test_suite(
        ref_data,
        current_data,
        save_report=True)
    try:
        ws.add_test_suite(project.id, test_suite)
        logging.info(f"Nouvelle test_suite ajouté au projet {PROJECT_NAME}.")
    except Exception as e:
        logging.error(f"ERREUR lors de l'ajout de la test_suite au Workspace: {e}")

    # Analyse du résultat
    drift_result = report.as_dict()["metrics"][0]["result"]
    # Le score global de dérive
    drift_score = drift_result["share_of_drifted_columns"]
    # Status
    is_drifted = drift_result["dataset_drift"]

    # Le FastApi sert de passerelle via /api/metrics/ pour que Evidently
    # puisse transmettre le status du drift à Prometheus
    # Pas possible de récupérer le DRITF_STATUS de src/api/main.py
    # car l'image FastApi et Evidently sont différentes et cela génère
    # des erreurs (FastApi avec numpy>2 et Evidently avec numpy<2)
    # On passe donc par la mise à jour du fichier drift_status.txt
    # Chemin vers le fichier partagé
    #drift_file_path = f"{PATH}/drift_status.txt"
    # On écrit le résultat (1 ou 0) dans le fichier
    #with open(drift_file_path, "w") as f:
    #    f.write("1" if is_drifted else "0")

    # Fichier plus complet pour avoir toutes les infos
    # Fichier json est le plus adapté
    model_name = default_project_name
    data_to_save = {
        "model_name": model_name,
        "drift_status": 1 if is_drifted else 0,
        "drift_score": drift_score
    }
    full_drift_file_path = f"{PATH}/full_drift_status.json"
    with open(full_drift_file_path, "w") as f:
        json.dump(data_to_save, f)

    if is_drifted:
        logging.warning("ALERTE : Dérive détectée !")
    else:
        logging.info("Modèle stable.")

if __name__ == "__main__":
    run_monitoring()
