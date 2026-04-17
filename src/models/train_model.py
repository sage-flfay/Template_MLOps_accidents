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
from sklearn import metrics

import logging

# Ignorer le messages de niveau WARNING pour le module qui cherche la version de pip
# Ce warning contient mlflow.utils.environment qui est le filtre utilisé pour l'ignorer
logging.getLogger("mlflow.utils.environment").setLevel(logging.ERROR)

# Vérification de la version de joblib pour la compatibilité (en cas de problème)
print(f"----- 📦 Version de joblib utilisée pour la sauvegarde : {joblib.__version__}")

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

# --- DEBUT DU TRACKING MLFLOW ---
print("🧠 Entraînement du modèle en cours.")
print("⏳ Cela peut prendre plusieurs dizaines de secondes...")
print("")
# Crée une session d'entraînement.
# Si le script plante, le run s'arrête proprement.
with mlflow.start_run():

    # Paramètres du modèle
    params = {"n_estimators": 100, "n_jobs": -1, "random_state": 42}

    rf_classifier = ensemble.RandomForestClassifier(**params)
    # rf_classifier = ensemble.RandomForestClassifier(n_jobs=-1)

    # --Train the model
    # rf_classifier.fit(X_train, y_train)

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
    mlflow.sklearn.log_model(
        sk_model=rf_classifier,
        name="model",
        signature=signature,
        # astype(float) accepte les nans ==> élimine le warning mlflow sur potentiel nan
        input_example=X_train_set_to_astype_float,
        # Stocker les models avec le nom qui commence par Accidents_Severity_Classifier
        registered_model_name="Accidents_Severity_Classifier",
        # MLflow fige les versions de requirements (comme pip freeze) cette liste et
        # ajoute automatiquement les dépendances secondaires (ex: numpy)
        pip_requirements=requirements,
    )

    # -- Sauvegarde locale (joblib actuel)
    joblib.dump(rf_classifier, output_model_path_filename)
    print("")
    print("###########################################################################")
    print(f"✅ recall grave: {report['classe_1_grave']['recall']:.2%}")
    print(f"✅ F1-score avg: {report['macro avg']['f1-score']:.2%}")
    print(f"✅ Accuracy: {report['accuracy']:.2%}")
    print(
        f"✅ Model tracked in MLflow and saved locally at: {output_model_path_filename}"
    )
    print("###########################################################################")
    print("")

# --Save the trained model to a file
# joblib.dump(rf_classifier, output_model_path_filename)
# print(f"✅ Model trained and saved successfully here : {output_model_path_filename}")
