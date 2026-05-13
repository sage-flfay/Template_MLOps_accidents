# import os
# import joblib
import pandas as pd

# from pathlib import Path
from fastapi import FastAPI, Request

# from fastapi.responses import JSONResponse, HTMLResponse

# os et from pathlib import Path seulement utilisés dans config.py
# from src.api.config import MODEL_PATH, FEATURES

# FEATURES, FEATURE_LABELS, CHOICES, SAMPLE utilisés dans templates.py
# from src.api.TemplateInterfaceWeb import HTML

from fastapi.responses import JSONResponse
from fastapi.templating import Jinja2Templates

# On importe toutes les infos de config pour les donner au HTML
# from src.api.config import MODEL_PATH, FEATURES, FEATURE_LABELS, CHOICES, SAMPLE
from src.api.config import FEATURES, FEATURE_LABELS, CHOICES, SAMPLE

from src.features.build_features import apply_feature_remapping

# Découper l’application en microservices et concevoir une orchestration simple
# import mlflow.pyfunc
import mlflow.sklearn
import os
from pydantic import create_model

# Pour update_model_version
import mlflow.tracking

# app = FastAPI(title="Accident ML API")
# -----------------------------------------------------------------------------
# CONFIGURATION DU ROOT_PATH
# -----------------------------------------------------------------------------
# En définissant root_path="/api", FastAPI devient "conscient" qu'il est
# derrière un reverse proxy (Nginx).
# 1. Le navigateur enverra toutes les requêtes (ex: formulaires, JS) vers /api/...
# 2. Les routes comme @app.post("/predict") seront accessibles via /api/predict.
# 3. La doc Swagger (/api/docs) trouvera son fichier /api/openapi.json sans erreur.
# Cela permet de simplifier le nginx.conf à un seul bloc 'location /api/'.
# -----------------------------------------------------------------------------
app = FastAPI(title="Accident ML API", root_path="/api")


# Configuration du chemin

# Découper l’application en microservices et concevoir une orchestration simple
# --- CONFIGURATION MLFLOW ---
# On récupère l'URL du serveur MLflow (sera utile pour Docker plus tard)
MLFLOW_TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
MODEL_NAME = "Accidents_Severity_Classifier"
# MLFLOW / Tab Models / Accidents_Severity_Classifier
# Clique on Version X, look section Aliases and add best_model
MODEL_ALIAS = "best_model"

# --- CONFIGURATION JINJA2 ---
J2Templates = Jinja2Templates(directory="src/html")

#MODEL = None
#MODEL_INFO = {"loaded": False}
current_model = None
current_model_info = {
    "loaded": False, "version": None, "message": "En attente du premier chargement..."
}
current_version = None

@app.on_event("startup")
def load_model_on_startup():
    #global MODEL, MODEL_INFO
    global current_model, current_version, current_model_info
    client = mlflow.tracking.MlflowClient()

    try:
        # On tente de voir s'il y a déjà un champion
        print("On regarde s'il y a déjà un model taggé comme best_model")
        model_data = client.get_model_version_by_alias(MODEL_NAME, MODEL_ALIAS)

        # Si oui, alors on continue (sinon on passe dans le except)
        # raw_uri = model_data.source
        raw_uri = client.get_model_version_download_uri(MODEL_NAME, model_data.version)
        print(f"DEBUG RAW: {raw_uri}")
        model_uri = raw_uri
        print(f"🚀 Chargement du modèle : {model_uri}")
        current_model = mlflow.sklearn.load_model(model_uri)
        current_version = model_data.version
        current_model_info = {
            "loaded": True,
            "version": current_version,
            "has_proba": hasattr(current_model, "predict_proba")
        }
        print(f"✅ Modèle trouvé au démarrage : v{current_version}")

    except Exception as e:
        # On attrape l'erreur et on continue !
        print(
            "⚠️ Info : Aucun modèle disponible au démarrage "
            "(MLflow vide ou alias absent)."
        )
        print(
            "🚀 FastAPI est prêt, mais le modèle doit être chargé "
            "via le bouton 'Update'."
        )
        # On laisse current_model à None, FastAPI ne crash pas.

# ------------------------------------------------------------
# HEALTHCHECK
# ------------------------------------------------------------
@app.get("/health")
def healthz():
    return current_model_info


# ------------------------------------------------------------
# PREDICT (JSON brut)
# ------------------------------------------------------------
# Exemple de données réalistes
EXAMPLE_DATA = {
    "place": 1,
    "catu": 1,
    "sexe": 1,
    "secu1": 0,
    "year_acc": 2019,
    "victim_age": 46.0,
    "catv": 2,
    "obsm": 2,
    "motor": 1,
    "catr": 1,
    "circ": 2,
    "surf": 1,
    "situ": 1,
    "vma": 90.0,
    "jour": 18,
    "mois": 11,
    "lum": 1,
    "dep": 45,
    "com": 45072,
    "agg_": 1,
    "int": 1,
    "atm": 1,
    "col": 1,
    "lat": 47.964066,
    "long": 1.927586,
    "hour": 17,
    "nb_victim": 2,
    "nb_vehicules": 2,
}

# Créer le modèle (automatiquement validé par Pydantic)
AccidentSchema = create_model(
    "AccidentSchema", **{feature: (float, ...) for feature in FEATURES}
)

# Injecter l'exemple dans le schéma JSON
AccidentSchema.model_config["json_schema_extra"] = {"examples": [EXAMPLE_DATA]}


@app.post("/predict")
# async def predict(request: Request):
async def predict(data: AccidentSchema):
    if current_model is None:
        return JSONResponse(
            status_code=503,
            content={
                "error": "Model not loaded",
                "message": (
                    "API est en ligne mais le modèle n'a pas encore été récupéré "
                    "depuis MLflow. Veuillez cliquer sur 'Mettre à jour le modèle'."
                )
            }
        )

    try:
        # Pydantic a déjà vérifié les données, on convertit en DataFrame
        df = pd.DataFrame([data.dict()])

        # On applique les grouping modalities pour être conforme à ce qui a été
        # appris par le modèle
        df = apply_feature_remapping(df)

        # Forcer l'ordre des colonnes qui est primordial
        # On réordonne le dataframe selon liste FEATURES de config.py
        df = df[FEATURES]

        prediction = current_model.predict(df)[0]

        print("DEBUG - Colonnes dans l'ordre FEATURES :", df.columns.tolist())
        print("DEBUG - Première ligne envoyée :", df.values[0])

        result = {"prediction": float(prediction)}

        if hasattr(current_model, "predict_proba"):
            proba = current_model.predict_proba(df)[0].tolist()
            result["probabilities"] = proba

        return JSONResponse(result)

    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# --------------------------------------------------------------
# BOUTON POUR UPDATER LE MODEL SI NOUVEAU SINON AFFICHE L'ANCIEN
# --------------------------------------------------------------
@app.post("/update_model_version")
async def update_model_version():
    global current_model, current_version, current_model_info

    new_model = None
    client = mlflow.tracking.MlflowClient()

    try:
        # On tente de voir s'il y a déjà un champion
        print("On regarde s'il y a déjà un model taggé comme best_model")
        model_data = client.get_model_version_by_alias(MODEL_NAME, MODEL_ALIAS)

        # Si oui, alors on continue (sinon on passe dans le except)
        # On récupère la version précise depuis le Model Registry
        remote_version = model_data.version
        remote_run_id = model_data.run_id

        # Si modèle déjà à jour
        if remote_version == current_version:
            message = f"Modèle déjà à jour avec la version {current_version}."
            print(f"ℹ️ {message}")
            # On sort avec le status
            return {
                "status": "no_change",
                "message": message,
                "version": current_version
            }

        # Si oui, alors on continue (sinon on passe dans le except)
        # raw_uri = model_data.source
        raw_uri = client.get_model_version_download_uri(MODEL_NAME, model_data.version)
        print(f"DEBUG RAW: {raw_uri}")
        model_uri = raw_uri
        print(f"🔄 Nouvelle version détectée (v{remote_version}).")
        print(f"🚀 Chargement du modèle : {model_uri}")
        new_model = mlflow.sklearn.load_model(model_uri)

        # Si le chargement a réussi
        current_model = new_model
        current_version = remote_version
        current_model_info = {
            "loaded": True,
            "version": current_version,
            "has_proba": hasattr(current_model, "predict_proba")
        }

        success_message = f"Nouvelle version de model v{current_version} chargée."
        print(f"✅ {success_message}")

        return {
            "status": "success",
            "message": success_message,
            "version": current_version,
            "run_id": remote_run_id[:8]
        }

    except Exception as e:
        # Si MLflow est vide, l'alias n'existe pas, ou problème réseau
        error_msg = (
            "⚠️ Impossible de récupérer le modèle. "
            "Vérifiez si le modèle et/ou l'alias 'best_model' existe dans MLflow."
        )
        print(f"{error_msg} Détails: {e}")
        return JSONResponse(
            status_code=404,
            content={"status": "error", "message": error_msg, "details": str(e)}
        )


# ------------------------------------------------------------
# PAGE D'ACCUEIL
# ------------------------------------------------------------
@app.get("/")
async def home(request: Request):
    # On injecte les variables dans le fichier HTML
    # Python 3.12 changement de syntaxe
    return J2Templates.TemplateResponse(
        request=request,
        name="TemplateInterfaceWeb.html",
        context={
            "features": FEATURES,
            "labels": FEATURE_LABELS,
            "samples": SAMPLE,
            "choices": CHOICES,
        },
    )
    # Python 3.8 ancienne syntaxe
    # return J2Templates.TemplateResponse(
    #    "TemplateInterfaceWeb.html",
    #    {
    #        "request": request,
    #        "features": FEATURES,
    #        "labels": FEATURE_LABELS,
    #        "samples": SAMPLE,
    #        "choices": CHOICES,
    #    },
    # )


# @app.get("/", response_class=HTMLResponse)
# def home():
#    return HTML
