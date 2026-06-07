import time
import os
import subprocess
import logging

# Configuration des logs pour voir ce qui se passe dans docker logs
logging.basicConfig(level=logging.INFO)

def monitoring_daemon():
    logging.info("Démon de monitoring démarré...")
    default_path = "/app/data/evidently"
    PATH = os.getenv("EVIDENTLY_PATH", default_path)
    MONITOR_DAEMON_TIMER = int(os.getenv("MONITOR_DAEMON_TIMER", 30))
    logging.info(
        "fichier src/monitoring/evidently_monitor_daemon.py..."
        f"On vérifie les variables: PATH = {PATH}; "
        f"MONITOR_DAEMON_TIMER = {MONITOR_DAEMON_TIMER}"
    )
    if not os.path.exists(PATH):
        logging.warning(f"Attention : Le répertoire PATH {PATH} n'existe pas encore.")
    else:
        logging.info(f"Le répertoire PATH {PATH} est accessible.")

    cur_path_file = "/app/data/users/fastapi_data.csv"
    last_modified_time = 0
    first_start_run_done = False

    while True:
        try:
            should_run = False

            if os.path.exists(cur_path_file):
                current_mtime = os.path.getmtime(cur_path_file)
                if current_mtime > last_modified_time:
                    logging.info("Nouveau fichier détecté. Lancement de l'analyse...")
                    should_run = True
                    last_modified_time = current_mtime
            elif not first_start_run_done:
                # NB: une fois fastapi_data.csv créé, le if se fera toujours même si
                # first_start_run_done = False (cas où on passe dans le except)
                first_start_run_done = True
                # --- INITIALISATION SYSTÈME ---
                # On force une exécution au démarrage pour garantir la création
                # du workspace Evidently et du projet
                # avant l'arrivée des premières données.
                logging.info("Initialisation : premier lancement du monitoring...")
                should_run = True

            if should_run:
                subprocess.run(["python3", "src/monitoring/evidently_monitor.py"], check=True)

            # Si pas d'exception alors mise à jour du heartbeat
            with open(f"{PATH}/heartbeat.txt", "w") as f:
                f.write(str(time.time()))

        except subprocess.CalledProcessError as e:
            logging.error(f"Le monitoring a échoué: {e}")
            # Puisque l'exception a été levée, le run a échoué.
            # On réinitialise simplement le flag pour forcer une nouvelle tentative
            # au prochain cycle (ou la prochaine détection de fichier).
            first_start_run_done = False
        except Exception as e:
            logging.error(f"Erreur inattendue dans le démon: {e}")
            first_start_run_done = False

        # Attendre MONITOR_DAEMON_TIMER secondes avant de relancer une analyse
        time.sleep(MONITOR_DAEMON_TIMER)

if __name__ == "__main__":
    monitoring_daemon()
