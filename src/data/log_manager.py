import os
import csv
from datetime import datetime

LOG_FILE_PATH = "/app/data/production_logs.csv"

def log_prediction_request(data):
    """
    Prend les données d'une requête de prédiction (Pydantic ou dict),
    les convertit proprement, ajoute un timestamp et force l'écriture.
    """
    # CORRECTIF DU PROBLÈME INITIAL : Conversion sécurisée en dictionnaire Python
    if hasattr(data, "dict"):
        payload = data.dict()
    elif hasattr(data, "model_dump"):
        payload = data.model_dump()
    else:
        payload = dict(data)

    # 1. Préparation de la ligne avec le timestamp actuel
    row_to_write = payload.copy()
    row_to_write["timestamp"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # 2. Détermination dynamique des en-têtes (fieldnames)
    # Si le fichier existe déjà, on respecte l'ordre de l'en-tête existant
    if os.path.exists(LOG_FILE_PATH) and os.path.getsize(LOG_FILE_PATH) > 0:
        try:
            with open(LOG_FILE_PATH, mode="r", encoding="utf-8") as f:
                reader = csv.reader(f)
                fieldnames = next(reader)
        except Exception:
            fieldnames = list(row_to_write.keys())
    else:
        # Sinon, on génère l'en-tête à partir des clés reçues
        fieldnames = list(row_to_write.keys())
    
    # 3. Écriture physique et libération immédiate du buffer
    try:
        file_exists = os.path.exists(LOG_FILE_PATH) and os.path.getsize(LOG_FILE_PATH) > 0
        
        with open(LOG_FILE_PATH, mode="a", newline="", encoding="utf-8") as csv_file:
            # extrasaction='ignore' garantit l'immunité contre les décalages de clés
            writer = csv.DictWriter(csv_file, fieldnames=fieldnames, extrasaction='ignore', restval="")
            
            if not file_exists:
                writer.writeheader()
                
            writer.writerow(row_to_write)
            csv_file.flush()  # Force l'écriture sur le volume Kubernetes
            print(f"📝 [API_LOG] Ligne de production interceptée et écrite avec succès.")
    except Exception as e:
        print(f"❌ [API_LOG] Erreur d'écriture : {str(e)}")