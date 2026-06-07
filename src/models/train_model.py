# train_model.py (version ed01) dans src/models/

import sys
import os
from pathlib import Path

# import sklearn
import pandas as pd
from sklearn import ensemble
import joblib
import numpy as np

import mlflow
import mlflow.sklearn
from mlflow.models import infer_signature

# Pour setter l'alias au tout premier run
from mlflow import MlflowClient

from sklearn import metrics
import logging

import yaml
import json

# Pour Sauvegarde sur DAGSHUB
import shutil

# Ignorer le messages de niveau WARNING pour le module qui cherche la version de pip
# Ce warning contient mlflow.utils.environment qui est le filtre utilisé pour l'ignorer
logging.getLogger("mlflow.utils.environment").setLevel(logging.ERROR)

# Vérification de la version de joblib pour la compatibilité (en cas de problème)
print(f"----- 📦 Version de joblib utilisée pour la sauvegarde : {joblib.__version__}")

# Initialisation des variables
model_name = "Accidents_Severity_Classifier"

# ---- CONFIGURATION de MLflow
# On récupère MLFLOW_TRACKING_URI via l'environnement (définie dans le Makefile)
# Si non défini, on utilise par défaut localhost:5000 pour ne pas bloquer
tracking_uri = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
mlflow.set_tracking_uri(tracking_uri)

print(f"----- 📡 Connexion au serveur MLflow sur : {tracking_uri}")

# Regroupe les runs sous le nom de projet donné.
mlflow.set_experiment("Accidents_Classification")

# On récupère les chemins (Crash ici si le dvc.yaml est incomplet)
try:
    input_filepath = Path(sys.argv[1])
    output_model_path_filename = Path(sys.argv[2])
except IndexError:
    print("❌ Erreur : dvc.yaml n'a pas fourni assez d'arguments.")
    sys.exit(1)

# On vérifie si le chemin d'entrée EXISTE vraiment
if not input_filepath.exists():
    print(
        "❌ Erreur de syntaxe dans dvc.yaml : "
        f"Le chemin '{input_filepath}' n'existe pas !"
    )
    print(f"----- 📍 Emplacement actuel : {Path.cwd()}")
    sys.exit(1)

# Sécurité : On s'assure que le dossier PARENT existe (ici "models/")
# .parent récupère "models" à partir de "models/model.joblib"
output_model_path_filename.parent.mkdir(parents=True, exist_ok=True)

# Si on arrive ici, tout est OK
print(f"✅ Source path checked : {input_filepath}")
print("")

X_train = pd.read_csv(f"{input_filepath}/X_train.csv")
X_test = pd.read_csv(f"{input_filepath}/X_test.csv")
y_train = pd.read_csv(f"{input_filepath}/y_train.csv")
y_test = pd.read_csv(f"{input_filepath}/y_test.csv")
y_train = np.ravel(y_train)
y_test = np.ravel(y_test)

# MLFLOW WEB - Colonne "Dataset" vide
# Création de l'objet dataset MLflow
source_X_train_csv = f"{input_filepath}/X_train.csv"
source_y_train_csv = f"{input_filepath}/y_train.csv"
# y_train est un vecteur NumPy (non structuré) après le prétraitement.
# Or pour l'objet, le dataframe est requis pour garantir la traçabilité du schéma
y_train_raw = pd.read_csv(f"{input_filepath}/y_train.csv")

# Dataset Features
dataset_X_train = mlflow.data.from_pandas(
    X_train,
    name="features_train",
    source=source_X_train_csv
)
# Dataset Labels
dataset_y_train = mlflow.data.from_pandas(
    y_train_raw,
    name="labels_train",
    source=source_y_train_csv
)

# --- DEBUT DU TRACKING MLFLOW ---
print("🧠 Entraînement du modèle en cours.")
print("⏳ Cela peut prendre plusieurs dizaines de secondes...")
print("")
# Crée une session d'entraînement.
# Si le script plante, le run s'arrête proprement.
with mlflow.start_run():

    # MLFLOW WEB - Colonne "Dataset" vide
    # Loguer les infos générales
    mlflow.log_input(dataset_X_train, context="training")
    mlflow.log_input(dataset_y_train, context="training")
    # Loguer les artefacts
    mlflow.log_artifact(source_X_train_csv, artifact_path="data")
    mlflow.log_artifact(source_y_train_csv, artifact_path="data")

    # On récupère l'année depuis l'environnement (injectée par Airflow/Docker)
    # Si absent, 2019 par défaut
    # training_year = os.getenv('TRAIN_YEAR', '2019') ne fonctionne pas
    try:
        with open("params.yaml", 'r') as f:
            config = yaml.safe_load(f)
            # On récupère la clé exacte vue dans le fichier qui est TRAIN_YEAR: XXXX
            training_year = str(config.get('TRAIN_YEAR', '2019'))
    except Exception as e:
        print(f"⚠️ Erreur lors de la lecture de params.yaml : {e}")
        training_year = "2019"

    print(f"📌 Année récupérée depuis params.yaml : {training_year}")

    mlflow.log_param("training_year_trigger", training_year)
    print(f"📌 MLflow Param -> training_year_trigger: {training_year}")

    # Paramètres du modèle
    params = {"n_estimators": 100, "n_jobs": -1, "random_state": 42}

    rf_classifier = ensemble.RandomForestClassifier(**params)
    # rf_classifier = ensemble.RandomForestClassifier(n_jobs=-1)

    # -- Train the model
    rf_classifier.fit(X_train, y_train)

    # -- Evaluation
    predictions = rf_classifier.predict(X_test)
    # Définition explicite des noms pour correspondre aux labels (0, 1)
    # Reprendre la même terminologie que celle utilisée dans evaluate.py
    target_classe_names = ["classe_0_benin", "classe_1_grave"]
    # Générer le rapport complet sous forme de dictionnaire
    report = metrics.classification_report(
        y_test, predictions, target_names=target_classe_names, output_dict=True
    )

    # -- Log MLflow (Paramètres, Métriques, Modèle)
    # Enregistre la configuration
    mlflow.log_params(params)
    # Enregistre les métriques stratégiques
    mlflow.log_metric("recall_grave", report["classe_1_grave"]["recall"])
    # Clé standard scikit-learn à utiliser : macro avg (pour avg des 2 f1-scores)
    mlflow.log_metric("f1_macro_avg", report["macro avg"]["f1-score"])
    # Clé standard scikit-learn à utiliser : accuracy
    mlflow.log_metric("accuracy", report["accuracy"])

    # Eliminer l'affichage du warning suivant:
    # WARNING mlflow.models.model: Model logged without a signature and input example
    # infer_signature(in, out) analyse X_train pour extraire noms et types de colonnes
    # xxx.predict(X_train) pour définir le type et la structure de la cible
    X_train_set_to_astype_float = X_train.iloc[:5].astype(float)
    signature = infer_signature(
        X_train_set_to_astype_float, rf_classifier.predict(X_train_set_to_astype_float)
    )

    # Liste minimale des dépendances pour le mlflow.sklearn.log_model
    requirements = ["scikit-learn", "pandas", "joblib", "mlflow"]

    # Log du modèle directement dans MLflow
    # Enregistre le modèle dans le format standard MLflow (plus complet que .joblib)
    # mlflow.sklearn.log_model(rf_classifier, "model")
    # Enregistrer le modèle avec sa signature et un exemple pour supprimer le warning
    latest_model = mlflow.sklearn.log_model(
        sk_model=rf_classifier,
        # name="model", obsolète avec les nouvelles versions MLFLOW
        artifact_path="model",
        signature=signature,
        # astype(float) accepte les nans ==> élimine le warning mlflow sur potentiel nan
        input_example=X_train_set_to_astype_float,
        # Stocker les models avec le nom qui commence par Accidents_Severity_Classifier
        # registered_model_name="Accidents_Severity_Classifier",
        registered_model_name=model_name,
        # MLflow fige les versions de requirements (comme pip freeze) cette liste et
        # ajoute automatiquement les dépendances secondaires (ex: numpy)
        pip_requirements=requirements,
    )

    # Récupération des infos nécessaires pour l'automatisation des alias
    latest_v = latest_model.registered_model_version
    latest_recall = report["classe_1_grave"]["recall"]

    # -- Sauvegarde locale (joblib actuel)
    joblib.dump(rf_classifier, output_model_path_filename)
    print("")
    print("###########################################################################")
    print(f"✅ recall grave: {report['classe_1_grave']['recall']:.2%}")
    print(f"✅ F1-score avg: {report['macro avg']['f1-score']:.2%}")
    print(f"✅ Accuracy: {report['accuracy']:.2%}")
    print(
        "✅ Model tracé dans MLflow, localement sauvé dans: "
        f"{output_model_path_filename} et enregistré avec la version: {latest_v}"
    )
    print("###########################################################################")
    print("")

    # --- AUTOMATISATION DE L'ALIAS POUR TOUS LES RUN ---
    client = MlflowClient()
    # Mise à jour SYSTÉMATIQUE de la description du Model registry Mlflow
    client.update_model_version(
        name=model_name,
        version=latest_v,
        description=(
            f"Recall Grave: {latest_recall:.2%}. "
            "Critère best model basé sur le meilleur Recall Grave"
        )
    )
    # Ajouter un tag pour l'année des données par exemple
    client.set_model_version_tag(
        name=model_name,
        version=latest_v,
        key="TRAIN_YEAR",
        value=f"{training_year}"
    )
    print(f"✅ Tag et Description ajoutée à la Version {latest_v}")

    # Pour Sauvegarde sur le disque local (pour ensuite le sauvegarder su Dagshub)
    # models: protocole qui indique à MLflow d'utiliser l'API du Model Registry.
    # model_name: nom que donné par registered_model_name=model_name dans
    #             mlflow.sklearn.log_model.
    # latest_v: numéro de version
    model_uri = f"models:/{model_name}/{latest_v}"
    # NB: On monte le volume dans le dag pour le dockerOperator du train
    # pour faire correspondre /home/ubuntu/Template_MLOps_accidents/data/mlruns_latest
    # avec /app/data/mlruns_latest
    local_path = "/app/data/mlruns_latest"
    # On supprime et on crée le répertoire mlruns_latest pour être sûr qu'il est propre
    if os.path.exists(local_path):
        shutil.rmtree(local_path)
    # NB: exist_ok=True pour ne pas générer d'erreur si une autre entité
    # a déjà créé le répertoire (impossible ici mais pour bonne pratique)
    os.makedirs(local_path, exist_ok=True)
    # On récupère le run associé à cette version dans le registre
    model_version_details = client.get_model_version(model_name, latest_v)
    run_id = model_version_details.run_id # C'est le run ID d'origine !
    # On récupère toutes les infos du run d'origine
    original_run = mlflow.get_run(run_id)
    # On récupère les params et metrics:
    params = original_run.data.params
    metrics = original_run.data.metrics
    # On les sauvegarde dans un fichier JSON dans le local_path
    with open(f"{local_path}/params_and_metrics.json", "w") as f:
        json.dump({"params": params, "metrics": metrics}, f)
    # Télécharger/Sauvegarder le modèle
    mlflow.artifacts.download_artifacts(artifact_uri=model_uri, dst_path=local_path)
    print(
        "✅ Sur la VM, le nouveau run complet mlflow est sauvegardé dans "
        "./data/mlflow_runs à partir de la racine"
    )
    try:
        # On vérifie si l'alias 'best_model' existe déjà dans le registre
        try:
            # Si le best_model n'existe pas encore, on passe dans le except
            current_best = client.get_model_version_by_alias(model_name, "best_model")

            print("Alias 'best_model' déjà attribué.")
            print(
                "On lance la procédure d'affectation automatique "
                "du best_model au meilleur modèle."
            )
            current_best_run_id = current_best.run_id

            # On récupère sa performance (recall enregistré lors de son entraînement)
            current_best_run_data = client.get_run(current_best_run_id).data
            # O si non trouvé mais logiquement ça ne doit jamais arriver
            current_best_recall = current_best_run_data.metrics.get("recall_grave", 0)

            print(
                f"📊 Comparaison : Ancien Best ({current_best_recall:.4f}) "
                f"vs Nouveau ({latest_recall:.4f})"
            )

            # Logique de promotion
            if latest_recall > current_best_recall:
                client.set_registered_model_alias(model_name, "best_model", latest_v)
                print(f"🏆 Nouveau champion ! Version {latest_v} devient 'best_model'.")
            else:
                print(f"🛡️ Le champion actuel reste en place. La nouvelle version n'est pas meilleure.")

        except:
            # L'alias n'existe pas (cas du 1er run ou suppression manuelle)
            # On l'assigne automatiquement à la version qu'on vient de produire
            client.set_registered_model_alias(model_name, "best_model", latest_v)
            print(
                "🚀 Succès : Premier modèle détecté. Alias 'best_model' assigné"
                f"automatiquement à la Version {latest_v} !"
            )
            print(f"💡 API FastAPI est maintenant opérationnelle immédiatement.")

    except Exception as e:
        print(f"⚠️  Attention : Impossible d'automatiser l'alias ({e}).")
        print(f"⚠️  Veuillez vérifier l'onglet 'Models' dans MLflow.")
