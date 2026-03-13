# train_model.py (version ed01) dans src/models/

import sys
from pathlib import Path

# import sklearn
import pandas as pd
from sklearn import ensemble
import joblib
import numpy as np

print(joblib.__version__)

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
    print(f"📍 Emplacement actuel : {Path.cwd()}")
    sys.exit(1)

# Sécurité : On s'assure que le dossier PARENT existe (ici "models/")
# .parent récupère "models" à partir de "models/model.joblib"
output_model_path_filename.parent.mkdir(parents=True, exist_ok=True)

# Si on arrive ici, tout est OK
print(f"✅ Source path checked : {input_filepath}")

X_train = pd.read_csv(f"{input_filepath}/X_train.csv")
X_test = pd.read_csv(f"{input_filepath}/X_test.csv")
y_train = pd.read_csv(f"{input_filepath}/y_train.csv")
y_test = pd.read_csv(f"{input_filepath}/y_test.csv")
y_train = np.ravel(y_train)
y_test = np.ravel(y_test)

rf_classifier = ensemble.RandomForestClassifier(n_jobs=-1)

# --Train the model
rf_classifier.fit(X_train, y_train)

# --Save the trained model to a file
joblib.dump(rf_classifier, output_model_path_filename)
print(f"✅ Model trained and saved successfully here : {output_model_path_filename}")
