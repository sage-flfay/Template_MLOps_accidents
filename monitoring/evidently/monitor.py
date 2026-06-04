import os
import time
import pandas as pd
from datetime import datetime
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset

REFERENCE_DATA_PATH = "X_train.csv"
PRODUCTION_LOGS_PATH = "/app/data/production_logs.csv"
REPORT_OUTPUT_PATH = "/app/reports/data_drift_report.html"

def run_evidently_analysis():
    print(f"[{datetime.now()}] 🔄 Analyse de dérive (Data Drift) lancée...")
    if not os.path.exists(PRODUCTION_LOGS_PATH):
        print(f"ℹ️ [Evidently] En attente de données dans {PRODUCTION_LOGS_PATH}. Pause...")
        return
    if not os.path.exists(REFERENCE_DATA_PATH):
        print(f"❌ Erreur Critique : Le fichier de référence {REFERENCE_DATA_PATH} est introuvable.")
        return

    df_reference = pd.read_csv(REFERENCE_DATA_PATH)
    df_production = pd.read_csv(PRODUCTION_LOGS_PATH)

    if "timestamp" in df_production.columns:
        df_production = df_production.drop(columns=["timestamp"])

    columns_to_monitor = [col for col in df_reference.columns if col in df_production.columns]
    reference_sample = df_reference[columns_to_monitor]
    production_sample = df_production[columns_to_monitor]

    print(f"📊 Comparaison de {len(production_sample)} requêtes réelles avec la référence d'entraînement...")
    drift_report = Report(metrics=[DataDriftPreset()])
    drift_report.run(reference_data=reference_sample, current_data=production_sample)

    os.makedirs(os.path.dirname(REPORT_OUTPUT_PATH), exist_ok=True)
    drift_report.save_html(REPORT_OUTPUT_PATH)
    print(f"✅ Rapport MLOps généré avec succès : {REPORT_OUTPUT_PATH}")
if __name__ == "__main__":
    print("🚀 Démarrage du microservice de monitoring Evidently...")
    while True:
        try:
            run_evidently_analysis()
        except Exception as e:
            print(f"❌ Erreur lors de l'exécution du monitoring : {e}")
        time.sleep(60)
