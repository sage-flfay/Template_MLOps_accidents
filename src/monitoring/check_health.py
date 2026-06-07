import time
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)

def check_heartbeat(file, max_age_seconds):
    """Vérifie si le fichier existe et s'il a été mis à jour récemment."""
    if not os.path.exists(file):
        print(f"Erreur : Le fichier {file} n'existe pas.")
        return False

    file_mtime = os.path.getmtime(file)
    age = time.time() - file_mtime

    if age > max_age_seconds:
        print(f"Erreur : Le heartbeat est trop vieux ({int(age)} secondes).")
        return False

    return True

if __name__ == "__main__":
    default_path = "/app/data/evidently"
    PATH = os.getenv("EVIDENTLY_PATH", default_path)
    MONITOR_DAEMON_TIMER = int(os.getenv("MONITOR_DAEMON_TIMER", 30))
    max_age_seconds = MONITOR_DAEMON_TIMER + 5

    logging.info(
        "Dans src/monitoring/check_health.py. "
        f"On vérifie les variables: PATH = {PATH}; "
        f"MONITOR_DAEMON_TIMER = {MONITOR_DAEMON_TIMER}"
    )
    if not os.path.exists(PATH):
        logging.warning(f"Attention : Le répertoire PATH = {PATH} n'existe pas encore.")
    else:
        logging.info(f"Le répertoire PATH = {PATH} est accessible.")


    #heartbeat_file = "/app/data/evidently/heartbeat/heartbeat.txt"
    heartbeat_file = f"{PATH}/heartbeat.txt"

    if check_heartbeat(heartbeat_file, max_age_seconds):
        sys.exit(0) # Le conteneur est sain
    else:
        sys.exit(1) # Le conteneur est en mauvaise santé
