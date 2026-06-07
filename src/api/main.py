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
from mlflow.exceptions import MlflowException

# PROMETHEUS&GRAFANA - Librairies
# Pour le calcul du temps (time.time())
import time
# Pour la route /metrics
from fastapi import Response
# Créer les métriques
from prometheus_client import Counter, Histogram, Gauge, generate_latest
import json

# Pour récupérer de DVC
import boto3
import joblib
import io

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

# Récupération des variables d'environnement du service api de docker-compose
DAGSHUB_REPO_NAME = os.getenv("DAGSHUB_REPO_NAME")
DAGSHUB_USER = os.getenv("DAGSHUB_USER")
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")

S3_ENDPOINT_URL = f"https://dagshub.com/{DAGSHUB_USER}/{DAGSHUB_REPO_NAME}.s3"
BUCKET_NAME = "dvc"  # Dagshub, dans DATA, le bucket s'appelle "dvc"

# Initialisation du client S3 pour DagsHub
s3_client = boto3.client(
    "s3",
    endpoint_url=S3_ENDPOINT_URL,
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY
)

#MODEL = None
#MODEL_INFO = {"loaded": False}
current_model = None
current_model_info = {
    "loaded": False, "version": None, "message": "En attente du premier chargement..."
}
current_version = None

# PROMETHEUS&GRAFANA - Déclaration des métriques (technical KPIs)
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

# EVIDENTLY - Déclaration des métriques (Data Quality KPI)
# WARNING: ce KPI est updaté dans src/monitoring/evidently_monitor.py
# Le FastApi sert ici de passerelle pour que Evidently communique avec
# Prometheus via /api/metrics
#DRIFT_STATUS = Gauge(
#    "accident_model_drift_status",
#    "1 si un drift est détecté, 0 sinon"
#)
DRIFT_STATUS = Gauge(
    "accident_model_drift_status",
    "Status",
    ["model_name"],
)
DRIFT_SCORE = Gauge(
    "accident_model_drift_score",
    "Score",
    ["model_name"]
)

# NB: Image Evidently version 0.6.7 python 3.10 mais obligé d'avoir version numpy < 2.0
# Mais l'image FastApi est avec version numpy > 2.0 donc l'image n'est pas la même et
# conflit. L'idée est de passer par un fichier dédié
#def update_drift_from_file():
#    try:
#        with open("/app/data/evidently/drift_status.txt", "r") as f:
#            val = int(f.read().strip())
#            DRIFT_STATUS.set(val)
#    except:
#        # Par défaut, pas d'alarme car le fichier n'est pas encore créé et
#        # donc le drift test n'a pas encore démarré dans evidently
#        DRIFT_STATUS.set(0)

def update_full_drift_from_file():
    try:
        with open("/app/data/evidently/full_drift_status.json", "r") as f:
            data = json.load(f)
            DRIFT_STATUS.labels(model_name=data["model_name"]).set(data["drift_status"])
            DRIFT_SCORE.labels(model_name=data["model_name"]).set(data["drift_score"])
    except:
        # Par défaut, pas d'alarme car le fichier n'est pas encore créé et
        # donc le drift test n'a pas encore démarré dans evidently
        DRIFT_STATUS.labels(model_name="accidents_severity").set(0)
        DRIFT_SCORE.labels(model_name="accidents_severity").set(0)

@app.on_event("startup")
def load_model_on_startup():
    # Pour le démarrage, juste une info console
    # Au démarrage des services, le modèle est forcément absent
    # Seul utilité est lors du démarrage à chaud mais l'utilisateur
    # peut tout simplement cliquer sur le bouton de mise à jour de version
    print("🚀 API lancée. Modèle non chargé par défaut.")
    print(
        "👉 Le modèle doit être charge via le bouton 'Mettre à jour le modèle' "
        "(instruction via /update_model)"
    )

# ------------------------------------------------------------
# HEALTHCHECK
# ------------------------------------------------------------
@app.get("/health")
def healthz():
    return current_model_info


# ------------------------------------------------------------
# PROMETHEUS&GRAFANA&EVIDENTLY
# ------------------------------------------------------------
@app.get("/metrics")
def metrics():
    # On récupère les valeurs de DRIFT dans le fichier avant de les exposer
    # update_drift_from_file()
    update_full_drift_from_file()
    # On expose tous les KPIs dans le lien @IP/api/metrics
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

    # PROMETHEUS&GRAFANA - initialisation du timer
    start_time = time.time()

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

        # EVIDENTLY
        # Si le répertoire n'existe pas (donc au démarrage) alors on le crée
        os.makedirs("data/users", exist_ok=True)
        # On ajoute la prédiction au DataFrame AVANT de sauvegarder
        # C'est seulement utilisé par la test_suite
        # df["predict_result"] = float(prediction)
        # Stockage immédiat des données (Source de vérité)
        # On ajoute la ligne au fichier existant ou on le crée
        df.to_csv("data/users/fastapi_data.csv",
                  mode='a',
                  header=not os.path.exists("data/users/fastapi_data.csv"),
                  index=False)

        # PROMETHEUS&GRAFANA - Récupération du nb de prédiction et du temps de réponse
        PREDICTION_COUNT.inc()
        PREDICTION_LATENCY.observe(time.time() - start_time)

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
        #raw_uri = client.get_model_version_download_uri(MODEL_NAME, model_data.version)
        #print(f"DEBUG RAW: {raw_uri}")
        #model_uri = raw_uri
        print(f"🔄 Nouvelle version détectée (v{remote_version}).")
        #print(f"🚀 Chargement du modèle : {model_uri}")
        #new_model = mlflow.sklearn.load_model(model_uri)

        dl_via_S3 = False
        try:
            # ON RECUPERE LE MODELE SUR LE S3 GRACE AU  HASH
            # On va chercher le RUN MLflow pour récupérer le paramètre dvc_model_hash
            run_info = client.get_run(remote_run_id)
            dvc_hash = run_info.data.params.get("dvc_model_hash")

            if not dvc_hash:
                raise ValueError(
                    "Le paramètre 'dvc_model_hash' est introuvable "
                    f"dans le run {remote_run_id}."
                )

            # Reconstruction du chemin DVC unique sur le S3
            # DVC stocke les fichiers sous la forme : .dvc/cache/files/md5/ab/cdef12345...
            # Donc dans S3 la structure est files/md5/ab/cdef12345...
            folder_prefix = dvc_hash[:2]   # Les 2 premiers caractères
            file_suffix = dvc_hash[2:]     # Le reste du hash
            s3_key = f"files/md5/{folder_prefix}/{file_suffix}"

            print(f"🚀 Téléchargement direct depuis S3... Clé: {s3_key}")

            # Téléchargement du binaire depuis le S3 de DagsHub en mémoire
            s3_response = s3_client.get_object(Bucket=BUCKET_NAME, Key=s3_key)
            model_bytes = s3_response["Body"].read()

            # Chargement du modèle avec joblib
            new_model = joblib.load(io.BytesIO(model_bytes))

            # Téléchargement via S3 est un succès
            dl_via_S3 = True

        except Exception as e:
            # Ici, vous capturez TOUT :
            # - Erreurs réseau S3
            # - Erreurs de clé manquante (votre ValueError)
            # - Erreurs de chargement joblib
            print(f"⚠️ Échec du chargement S3 ({e}). Bascule en local.")
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

        #success_message = f"Nouvelle version de model v{current_version} chargée."
        if dl_via_S3:
            success_message = (
                f"Nouvelle version de modèle v{current_version} chargée "
                "directement depuis S3."
            )
        else:
            success_message = f"Nouvelle version de model v{current_version} chargée."

        print(f"✅ {success_message}")

        # PROMETHEUS&GRAFANA - Récupération de la version courante
        MODEL_VERSION.set(int(current_version))

        return {
            "status": "success",
            "message": success_message,
            "version": current_version,
            "run_id": remote_run_id[:8]
        }

    except MlflowException as e:
        # CAS 1 : Le modèle n'existe pas encore dans le Registry (DAG non lancé)
        if e.error_code == "RESOURCE_DOES_NOT_EXIST" or "not found" in str(e).lower():
            message = (
                "⚠️ Aucun modèle trouvé dans le registre. "
                "Veuillez d'abord lancer le DAG Airflow."
            )
            print(f"ℹ️ {message}")
            return {
                "status": "dag_not_run",
                "message": "",
                "version": "Aucun modèle (Lancer le DAG Airflow)",
                "run_id": ""
            }

        # Autre erreur MLflow (ex: problème de droits, mauvaise URL...)
        else:
            error_msg = f"❌ Erreur MLflow imprévue : {e.message}"
            return {
                "status": "error",
                "message": error_msg,
                "version": "",
                "run_id": ""
            }

    except Exception as e:
        # CAS 2 : Vraie erreur technique ou problème inattendu
        error_msg = (
            "❌ Impossible de récupérer le modèle. "
            "Vérifier si la connexion réseau ou si le serveur MLflow est accessible."
            "ou si l'alias 'best_model' est bien présent dans Mlflow, "
        )
        print(f"🔴 {error_msg} Détails: {e}")

        return {
            "status": "error",
            "message": error_msg,
            "version": "",
            "run_id": ""
        }

# ------------------------------------------------------------
# PAGE D'ACCUEIL
# ------------------------------------------------------------
@app.get("/")
async def home(request: Request):
    global current_version

    # Si au démarrage (startup) aucun modèle n'a pu être chargé,
    # assure-toi que ta variable 'current_version' vaut None ou ""
    if not current_version:
        version_id = "Aucun modèle (Lancer le DAG Airflow)"
        status_id = ""
    else:
        version_id = current_version
        status_id = f"ℹ️ Modèle déjà à jour avec la version {current_version}."

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
            "version_to_display": version_id,
            "status_to_display": status_id,
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
