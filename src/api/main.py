# import os
import joblib
import pandas as pd
import time

# from pathlib import Path
from fastapi import FastAPI, Request
from fastapi import Response


from fastapi.responses import JSONResponse, HTMLResponse

# os et from pathlib import Path seulement utilisés dans config.py
from src.api.config import MODEL_PATH, FEATURES

# FEATURES, FEATURE_LABELS, CHOICES, SAMPLE utilisés dans templates.py
# from src.api.TemplateInterfaceWeb import HTML

from fastapi.responses import JSONResponse
from fastapi.templating import Jinja2Templates

# On importe toutes les infos de config pour les donner au HTML
from src.api.config import MODEL_PATH, FEATURES, FEATURE_LABELS, CHOICES, SAMPLE
from src.api.config import FEATURES, FEATURE_LABELS, CHOICES, SAMPLE

# Découper l’application en microservices et concevoir une orchestration simple
# import mlflow.pyfunc
import mlflow.sklearn
import os
from pydantic import create_model

from prometheus_client import generate_latest
from prometheus_client import Counter, Histogram, Gauge, generate_latest

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

PREDICTION_COUNT = Counter(
    "accident_predictions_total",
    "Nombre total de prédictions effectuées"
)

PREDICTION_LATENCY = Histogram(
    "accident_prediction_latency_seconds",
    "Temps de réponse des prédictions en secondes"
)

MODEL_VERSION = Gauge(
    "accident_model_version",
    "Version du modèle en production"
)

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

MODEL = None
MODEL_INFO = {}


@app.on_event("startup")
def load_model():
    global MODEL, MODEL_INFO
    try:
        print(f"Chargement du modèle local : {MODEL_PATH}")
        MODEL = joblib.load(MODEL_PATH)
        MODEL_INFO = {
            "loaded": True,
            "source": "Local joblib",
            "path": str(MODEL_PATH),
            "has_proba": hasattr(MODEL, "predict_proba"),
        }
        MODEL_VERSION.set(1)
        print("✅ Modèle local chargé avec succès.")
    except Exception as e:
        MODEL_INFO = {"loaded": False, "error": str(e)}
        print(f"❌ Impossible de charger le modèle local : {e}")

# ------------------------------------------------------------
# HEALTHCHECK
# ------------------------------------------------------------
@app.get("/health")
def healthz():
    return MODEL_INFO


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type="text/plain")

# ------------------------------------------------------------
# PREDICT (JSON brut)
# ------------------------------------------------------------
# Exemple de données réalistes
EXAMPLE_DATA = {
    "place": 1,
    "catu": 1,
    "sexe": 1,
    "secu1": 0,
    "year_acc": 2021,
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

# Pydantic création dynamique du schéma (structure) à partir
# de la liste de features existante
# Utile pour remplir le POST / predict de IP_Ubuntu:8000/docs
# (float, ...) : en flottant et obligatoire (...)
# AccidentSchema = create_model(
#    "AccidentSchema",
#    **{feature: (float, ...) for feature in FEATURES},
#    __config__=type("Config", (), {"json_schema_extra": {"example": EXAMPLE_DATA}}),
# )

# Nouvelle syntaxe compatible Pydantic v2
# AccidentSchema = create_model(
#    "AccidentSchema",
#    **{feature: (float, ...) for feature in FEATURES},
#    __pydantic_config__={
#        "json_schema_extra": {
#            "examples": [EXAMPLE_DATA]
#        }
#    },
# )

# Créer le modèle
AccidentSchema = create_model(
    "AccidentSchema", **{feature: (float, ...) for feature in FEATURES}
)

# Injecter l'exemple dans le schéma JSON
AccidentSchema.model_config["json_schema_extra"] = {"examples": [EXAMPLE_DATA]}


@app.post("/predict")
# async def predict(request: Request):
async def predict(data: AccidentSchema):
    start_time = time.time()

    if not MODEL_INFO.get("loaded"):
        return JSONResponse({"error": "model not loaded"}, status_code=500)

    try:
        # data = await request.json()
        # Validation des features
        # missing = [f for f in FEATURES if f not in data]
        # if missing:
        #     return JSONResponse(
        #         {"error": f"missing features: {missing}"}, status_code=400
        #     )
        # Conversion en float
        # row = {}
        # for f in FEATURES:
        #     try:
        #         row[f] = float(data[f])
        #     except Exception as e:
        #         return JSONResponse(
        #             {"error": f"feature '{f}' must be numeric: {e}"}, status_code=400
        #         )
        # df = pd.DataFrame([row])

        # Pydantic a déjà vérifié les données, on convertit en DataFrame
        df = pd.DataFrame([data.dict()])

        # Forcer l'ordre des colonnes qui est primordial
        # On réordonne le dataframe selon liste FEATURES de config.py
        df = df[FEATURES]

        prediction = MODEL.predict(df)[0]

        print("DEBUG - Colonnes dans l'ordre FEATURES :", df.columns.tolist())
        print("DEBUG - Première ligne envoyée :", df.values[0])

        result = {"prediction": float(prediction)}

        if hasattr(MODEL, "predict_proba"):
            proba = MODEL.predict_proba(df)[0].tolist()
            result["probabilities"] = proba

        PREDICTION_COUNT.inc()
        PREDICTION_LATENCY.observe(time.time() - start_time)

        return JSONResponse(result)

    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


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
