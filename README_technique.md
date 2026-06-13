# STEP 4 - PARTIE Api Mlflow Airflow Prometheus Grafana Evidently + Alarme Drift + Dagshub update pour les nouvelles versions
### Ubuntu
VM UBUNTU A UTILISER IMPERATIVEMENT A PARTIR DE Sprint3: AIRFLOW / Airflow avancé - Deux nouveaux opérateurs >
Faire reinitialiser pour être sûr quelle redémarre de 0
LA VM a 16GO de RAM et 24GO de disk. Très important car les services consomment beaucoup de RAM

#### Récupérer à partir d'une machine vierge
git clone -b mlops_accidents https://github.com/sage-flfay/Template_MLOps_accidents.git

### Makefile
Taper **`make`** : Affichage de toutes les commandes avec un bref commentaire.

### CONFIGURATION AVANT DE DEMARRER
1. **DAGSHUB**
   * Configurer la visibilité à S3: aller dans Settings/Integrations, sélectionner "S3 compatible" pour remplir les champs,
on prend les infos dans files/data (gros bounton vert) et on descend jusqu'a Setup credentials et on prend le user et le password
2. **EVIDENTLY**
   * Pour que l'alarme soit transmise à webhook, aller sur le site https://webhook.site/ ==> il affiche un lien.
   * Copier ce lien et le mettre dans docker-compose.yml, service grafana, variable GF_WEBHOOK_URL et ainsi grafana sera correctement configuré

### COMMANDE A LANCER:
1. **`make install`** : Mettre à jour l’env complet. Elle s'arrete car elle demande à renseigner
   * **Warning** : il demandera les keys de sécurité dagshub. Commande améliorée. Laissez-vous guidé
   * NB: les key sont dans le DagsHub, Data, à la fin S3 Crédential copier la clé XXX
   * NB: Lors de la demande, l'affichage des key est masquée (comme pour le token demandé lors d'un push github)

2. **`make install`** : maitenant, toute l'installation va se faire
3. **`make docker-FullClean-full-build`**
   * **Suppression des projets** : nettoyage total de tout (donc si plusieurs projets en //, tout est supprimé (pas notre cas))
   * **Demande Airflow usr/pwd** : par défaut, press enter vide donne admin/admin
   * **Demande du mode** : mode débug (HTTP) ou mode prod (HTTPS)
   * **Création des images** : création  de toutes les images nécessaires au projet
   * **Affichage** : affichage des images générées, des infos ubuntu usage (important pour savoir si assez de resources)

4. **`WARNING: LA COMMANDE A CHANGé DE NOM. DEMARRAGE BEAUCOUP PLUS RAPIDE`**
   **`make docker-full-start-WoInitialTrain_fast`**
   * **Démarrage de tous les services bcp plus rapide**
   * **Maintenant la commande docker-reset-for-full-simu est aussi incluse pour un redémarrage complet et cohérent**
   * **Affichage** : rappel du mode pour accéder aux différents service web, affichage des services et des infos ubuntu usage
   * **NB** : 2 dags sont présents dans Airflow.
     * dvc_accidents_severity_WoDvcTrackPush: fait toute la procédure sans faire le hash du modèle et ni le dvc push.
       * Donc dans le fastapi, le bouton "Mettre à jour le modèle" se fera directement en interne
     * dvc_accidents_severity: le hash du modèle et le dvc push est fait (NB: l'utilisation de dvc.yaml fait automatiquement le dvc add)
       * Donc dans le fastapi, le bouton "Mettre à jour le modèle" se fera directement en questionnant le S3 pour récupérer le modèle

5. **`make drift-on`** :
   * Sauvegarde du fichier d'origine data/users/fastapi_data.csv
   * Copie du fichier simu_data_drift/fastapi_data_ForDriftAlerterDemo.csv dans data/users/fastapi_data.csv
   * La copie est importante car elle actualise l'heure. Le fichier est fourni à evidently qui regarde son heure pour savoir s'il n'est pas ancien et donc déjà traité
   * Le drift doit être détecté et une alarme doit être générée sur prometheus et grafana

6. **`make drift-off`** : revient au fastapi_data.csv d'origine. Il n'y a plus de drift et l'alarme est supprimée

7. **`make docker-reset-for-full-simu`** : Forcer la regénération de tous models via le run du web airflow (inutile la première fois car vierge)

8. **`make docker-status`** : affiche l'état des services et les ports actifs

9. **`make ubuntu_usage`** : vérification de la VM pour RAM, DISK, CPU par service


### INFOS GENERALES:
1. **DAGSHUB**
   * Onglet experiment updaté pour chaque version
   * S3 : Dans files, aller jusqu'à "Storage buckets" puis cliquer sur s3://dvc et descendre jusqu'aux fichiers pour voir ce qui est stocké

2. **MLFLOW** :
   * Model/training: Runs des versions avec le Dataset updaté, les paramètres et les metrics (et la metric dvc_model_hash présente si dag dvc_accidents_severity utilisé) 
   * Model/training: Models des versions avec le Dataset vide et accès au run concerné et paramètres et metrics identiques.
   * Model registry: Avec sélection automatique du "best model" en appliquant le critère de Recall Grave

3. **AIRFLOW** : 2 dags sont présents dans deployment/airflow/dags
   * dvc_accidents_severity.py et dvc_accidents_severity_WoDvcTrackPush.py qui ont pour contenu:
     * init_db = SQLExecuteQueryOperator  ==> pour la initialiser/préparer la database
     * prepare_params = BashOperator      ==> pour transmettre l'année de référence pour l'entrainement (mise à jour sur Airflow dans Admin/Variables)
     * Chaque DockerOperator utilise l'image accidents_severity-runner (définie à la racine dans Dockerfile)
     * On a un DockerOperator par commande "dvc repro xxx" du dvc.yaml qui contient les stages xxx:
       * import, 
       * process,
       * train, 
       * evaluate
       * dvc_hash  (UNIQUEMENT dans dvc_accidents_severity.py)
     * On a un DockerOperator pour la commande "dvc push" (UNIQUEMENT dans dvc_accidents_severity.py)
     * On a un DockerOperator pour la commande 'python3 /app/src/mlflow/dagshub_upd_version.py' pour versionner sur le dagshub
     * record_success = SQLExecuteQueryOperator  ==> enregistrement dans la database
   * Modifier la valeur de la key : dans le web airflow, aller dans Admin/Variable. Updater l'année: 2019, 2020, 2021, 2022, 2023, 2024 autorisés
   * Temps de génération** : si le modèle n'existe pas, la génération prend de 2 à 3mn. Si déjà existant, alors autour d'une minute pour juste les verifs

4. **EVIDENTLY** : Intégration du travail de Julien avec
   * Image spécifique (src/monitoring) car la version Evidently 0.6.7 ne supporte que numpy version < 2.0 contrairement aux autres images
   * Ajout des alarmes de drift dans prometheus et grafana avec configuration pour webhook (alarme reçu sur webhook)
   * Ajout dans le dashboard grafana d'un double panel drift pour le status et le score
   * Evidently triggé sur update du fichier data/users/fastapi_data.csv. La vérification de l'horodatage de ce fichier se fait toutes les 30s
   * Lors du trig, les variables de drifts sont stockées dans le fichier data/evidently/full_drift_status.json

5. **FASTAPI** : c'est le service api.
   * Avant de prédire, il faut mettre à jour le modèle et selon le dag appliqué dans Airflow
     * Si le dag dvc_accidents_severity a été lancé, la mise à jour se fera automatiquement à partir du S3 du dagshub (donc plus long)
     * Si le dag dvc_accidents_severity_WoDvcTrackPush a été lancé, la mise à jour se fera automatiquement à partir du Mlflow local (donc beaucoup plus rapide)
   * A chaque prédiction, le fichier data/users/fastapi_data.csv est updaté avec l'ensemble de ses variables et valeurs
   * Les KPIs de drift (data/evidently/full_drift_status.json) sont exposés dans /metrics

6. **PROMETHEUS** : Intégration du travail de Abdessamed + ajout de endpoint node-exporter pour le dashboard VM usage et cadvisor pour le dashboard des containers
   * scrape_interval: 5s, ce qui permet d'avoir une mise à jours rapide des KPIs 
   * evaluation_interval: 5s, ce qui permet de remonter l'alarme rapidement
   * Création de l'alarme de drift (NB: on constate qu'elle est automatiquement remontée au grafana)

7. **GRAFANA** : Intégration du travail de Abdessamed + ajout des dashboard (importés) pour VM usage et pour le monitoring des containers
   * Création de l'alarme de drift avec remonté rapide de l'alarme pour une démonstration rapide du bon fonctionnement
     * NB: elle fait doublon avec l'alarme créée dans prometheus qui remonte au grafana mais on la garde dans le contexte de projet de formation
   * Envoie de l'alarme firing ou resolved au webhook au bout de 10s la toute première fois et ensuite au bout de 20s (monitoring/grafana/provisionning/alerting/notification_policies.yaml)
   * IMPORTANT :
     * Le lien webhook est obtenu sur https://webhook.site mais n'a qu'une durée de vie limitée.
     * Pour palier à ce problème, dans le docker-compose.yaml service grafana, updater la variable GF_WEBHOOK_URL=https://webhook.site/id_fourni_par_le_site avant de lancer le service
     * NB: si trop de messages sont envoyé, alors le site bloque toute réception de messages et on peut voir l'information dans Alerting/Contact points
     * NB suite: en ouvrant le browser en mode privé, on peut avoir un nouveau lien (si on retente sur le browser d'origine, le id ne change pas et donc on est toujours bloqué)
   * Grafana Notification Policies : fichier notification_policies.yaml modifié pour envoyer l'alarme fired ou resolved au bout de 20s

8. **Makefile simplifié** : nettoyage du makefile pour ne garder que l'essentiel.

9. **Conformité PEP8** : make quality permet de vérifier la conformité PEP8 pour le code source (update des fichiers .py fait).

10.**LIVE CYCLE ARBORESCENCE**
   * Arborescence des artefacts : aborescence avec les répertoires présent par défaut et ceux créés lors du cycle de vie du projet
   * Répertoires inutilisés : la template de base a introduit des répertoires qui ne sont utilisés pour le projet et qui sont:
     * notebooks, reference, src/template_mlops_accidents, src/visualization, test

```
Template_MLOps_accidents
├── Dockerfile
├── LICENSE
├── Makefile
├── README.md
├── data
│   ├── evidently
│   │   ├── accidents_severity-ws
│   │   ├── full_drift_status.json
│   │   ├── heartbeat.txt
│   │   └── reports
│   │       ├── drift_report_2026-06-10.html
│   │       └── test_suite_2026-06-10.html
│   ├── mlruns_latest
│   ├── preprocessed
│   ├── raw
│   └── users
│       └── fastapi_data.csv
├── deployments
│   ├── airflow
│   │   ├── Dockerfile
│   │   ├── README.md
│   │   ├── dags
│   │   │   ├── __init__.py
│   │   │   ├── dvc_accidents_severity.py
│   │   │   └── dvc_accidents_severity_WoDvcTrackPush.py
│   │   ├── logs
│   │   └── plugins
│   └── nginx
│       ├── Dockerfile
│       ├── certs
│       │   ├── nginx.crt
│       │   └── nginx.key
│       ├── nginx.conf
│       └── nginx_debug.conf
├── docker-compose.yml
├── dvc.lock
├── dvc.yaml
├── logs
├── mlflow-logrotate.conf
├── models
│   └── model.joblib
├── monitoring
│   ├── grafana
│   │   ├── dashboards_json
│   │   │   ├── VMusage-dashboard.json
│   │   │   ├── accidents-dashboard.json
│   │   │   └── containers-dashboard.json
│   │   └── provisioning
│   │       ├── alerting
│   │       │   ├── alert_drift.yaml
│   │       │   ├── contact_points.yaml
│   │       │   └── notification_policies.yaml
│   │       ├── dashboards
│   │       │   └── dashboard.yml
│   │       └── datasources
│   │           └── datasource.yml
│   └── prometheus
│       ├── prometheus.yml
│       └── rules
│           └── alert_rules.yml
├── notebooks
│   └── 1.0-ldj-initial-data-exploration.ipynb
├── params.yaml
├── pyproject.toml
├── references
├── reports
│   ├── figures
│   └── metrics.json
├── requirements.txt
├── setup.cfg
├── setup_daemon_json.sh
├── setup_dagshub_key.sh
├── simu_data_drift
│   └── fastapi_data_ForDriftAlerterDemo.csv
├── simu_data_web
│   ├── caracteristiques-2019.csv
│   ├── caracteristiques-2020.csv
│   ├── caracteristiques-2021.csv
│   ├── caracteristiques-2022.csv
│   ├── caracteristiques-2023.csv
│   ├── caracteristiques-2024.csv
│   ├── lieux-2019.csv
│   ├── lieux-2020.csv
│   ├── lieux-2021.csv
│   ├── lieux-2022.csv
│   ├── lieux-2023.csv
│   ├── lieux-2024.csv
│   ├── usagers-2019.csv
│   ├── usagers-2020.csv
│   ├── usagers-2021.csv
│   ├── usagers-2022.csv
│   ├── usagers-2023.csv
│   ├── usagers-2024.csv
│   ├── vehicules-2019.csv
│   ├── vehicules-2020.csv
│   ├── vehicules-2021.csv
│   ├── vehicules-2022.csv
│   ├── vehicules-2023.csv
│   └── vehicules-2024.csv
├── src
│   ├── __init__.py
│   ├── api
│   │   ├── Dockerfile
│   │   ├── __init__.py
│   │   ├── config.py
│   │   └── main.py
│   ├── config
│   ├── data
│   │   ├── __init__.py
│   │   ├── check_structure.py
│   │   ├── import_raw_data.py
│   │   └── make_dataset.py
│   ├── features
│   │   ├── __init__.py
│   │   └── build_features.py
│   ├── html
│   │   └── TemplateInterfaceWeb.html
│   ├── mlflow
│   │   ├── Dockerfile
│   │   ├── dagshub_upd_version.py
│   │   └── dvc_tracker.py
│   ├── models
│   │   ├── Dockerfile
│   │   ├── __init__.py
│   │   ├── evaluate_model.py
│   │   ├── predict_model.py
│   │   └── train_model.py
│   ├── monitoring
│   │   ├── Dockerfile
│   │   ├── check_health.py
│   │   ├── evidently_monitor.py
│   │   ├── evidently_monitor_daemon.py
│   │   ├── pyproject.toml
│   │   └── uv.lock
│   ├── template_mlops_accidents
│   │   ├── __init__.py
│   │   └── py.typed
│   └── visualization
│       ├── __init__.py
│       └── visualize.py
├── test
│   └── test_structure.py
└── uv.lock
```

# STEP 4 - PARTIE Api Mlflow Airflow Prometheus Grafana
### Ubuntu
VM UBUNTU A UTILISER IMPERATIVEMENT A PARTIR DE Sprint3: AIRFLOW / Airflow avancé - Deux nouveaux opérateurs >
Faire reinitialiser pour être sûr quelle redémarre de 0
LA VM a 16GO de RAM et 24GO de disk. Très important car les services consomment beaucoup de RAM

#### Récupérer à partir d'une machine vierge
git clone -b nico_AMAPG https://github.com/sage-flfay/Template_MLOps_accidents.git

### Makefile
Taper **`make`** : Affichage de toutes les commandes avec un bref commentaire.

### COMMANDE A LANCER:
1. **`make install`** : Mettre à jour l’env complet. Elle s'arrete car elle demande à renseigner
   * **Warning** : il demandera les keys de sécurité dagshub. Commande améliorée. Laissez-vous guidé
   * NB: les key sont dans le DagsHub, Data, à la fin S3 Crédential copier la clé XXX
   * NB: Lors de la demande, l'affichage des key est masquée (comme pour le token demandé lors d'un push github)

2. **`make install`** : maitenant, toute l'installation va se faire
3. **`make docker-FullClean-full-build`**
   * **Suppression des projets** : nettoyage total de tout (donc si plusieurs projets en //, tout est supprimé (pas notre cas))
   * **Demande Airflow usr/pwd** : par défaut, press enter vide donne admin/admin
   * **Demande du mode** : mode débug (HTTP) ou mode prod (HTTPS)
   * **Création des images** : création  de toutes les images nécessaires au projet
   * **Affichage** : affichage des images générées, des infos ubuntu usage (important pour savoir si assez de resources)

4. **`WARNING: LA COMMANDE A CHANGé DE NOM. DEMARRAGE BEAUCOUP PLUS RAPIDE`**
   **`make docker-full-start-WoInitialTrain_fast`**
   * **Démarrage de tous les services bcp plus rapide**
   * **Maintenant la commande docker-reset-for-full-simu est aussi incluse pour un redémarrage complet et cohérent**
   * **Affichage** : rappel du mode pour accéder aux différents service web, affichage des services et des infos ubuntu usage

5. **`make docker-reset-for-full-simu`** : Forcer la regénération de tous models via le run du web airflow (inutile la première fois car vierge)

6. **`make docker-status`** : affiche l'état des services et les ports actifs

7. **`make ubuntu_usage`** : vérification de la VM pour RAM, DISK, CPU par service

8. **`INFOS GENERALES`**
   * **PROMETHEUS** : Intégration du travail de Abdessamed + ajout de endpoint node-exporter pour le dashboard VM usage et cadvisor pour le dashboard des containers
   * **GRAFANA** : Intégration du travail de Abdessamed + ajout des dashboard (importés) pour VM usage et pour le monitoring des containers
   * **Modifier la valeur de la key** :
     * Dans le web airflow, aller dans Admin/Variable. Updater l'année: 2019, 2020, 2021, 2022, 2023, 2024 autorisés
   * **Temps de génération** : si le modèle n'existe pas, la génération prend environ 1.30 à 2mn. Si déjà existant, alors moins d'une minute pour juste les verifs

9. **`REST A FAIRE`**
   * **EVIDENTLY** : en attente de Julien
   * **GRAFANA** : ajout du dashboard lié à evidently
   * **MLFLOW** :
     * Airflow: actuellement, échange du modèle .pkl fait via le volume (/app/artifacts). Le faire via HTTP pour une meilleure isolation des services. J'y travaille
     * Stockage du modèle : actuellement, le modèle .pkl reste dans le mlflow. Le stocker dans le dagshub. J'y travaille
     * API: actuellement, l'api récupère le modèle de mlflow. Il doit demander les hash au mlflow et récupérer le modèle dans le dagshub. J'y travaille
   * **KUBERNETES** : Florent (avec cette livraison)


# STEP 3 - PARTIE Api Mlflow Airflow
### Ubuntu
VM UBUNTU A UTILISER IMPERATIVEMENT A PARTIR DE Sprint3: AIRFLOW / Airflow avancé - Deux nouveaux opérateurs >
Faire reinitialiser pour être sûr quelle redémarre de 0
LA VM a 16GO de RAM et 24GO de disk. Très important car les services consomment beaucoup de RAM

#### Récupérer à partir d'une machine vierge
git clone -b nico_ApiMlflowAirflow https://github.com/sage-flfay/Template_MLOps_accidents.git

### Makefile
Taper **`make`** : Affichage de toutes les commandes avec un bref commentaire.

### COMMANDE A LANCER:
1. **`make install`** : Mettre à jour l’env complet. Elle s'arrete car elle demande à renseigner
   * **Warning** : il demandera les keys de sécurité dagshub. Et donc il ressort
   * A partir de l'affichage, copier/coller export DAGSHUB_ACCESS_KEY_ID=XXX (Dans le DagsHub, Data, à la fin S3 Crédential copierl la clé XXX)
   * Idem pour export DAGSHUB_SECRET_ACCESS_KEY=YYY (NB: YYY=XXX)

2. **`make install`** : maitenant, toute l'installation va se faire
3. **`make docker-FullClean-full-build`**
   * **Suppression des projets** : nettoyage total de tout (donc si plusieurs projets en //, tout est supprimé (pas notre cas))
   * **Demande Airflow usr/pwd** : par défaut, press enter vide donne admin/admin
   * **Demande du mode** : mode débug (HTTP) ou mode prod (HTTPS)
   * **Création des images** : création  de toutes les images nécessaires au projet
   * **Affichage** : affichage des images générées, des infos ubuntu usage (important pour savoir si assez de resources)

4. **`make docker-full-start-WoInitialTrain`**
   * **Démarrage de tous les services**
   * **Affichage** : rappel du mode pour accéder aux différents service web, affichage des services et des infos ubuntu usage

5. **`make docker-reset-for-full-simu`** : Forcer la regénération de tous models via le run du web airflow (inutile la première fois car vierge)

6. **`make docker-status`** : affiche l'état des services et les ports actifs

7. **`make ubuntu_usage`** : vérification de la VM pour RAM, DISK, CPU par service

8. **`INFOS GENERALES`**
   * **CRONTAB** : le dag est lancé automatiquement toutes les 2mn
   * **Modifier la valeur de la key** :
     * Faire un refresh site pour voir si le dag est en cours. Une fois terminé, désactiver le dag
     * Dans le web airflow, aller dans Admin/Variable. Updater l'année: 2019, 2020, 2021, 2022, 2023, 2024 autorisés
   * **Réactiver le dag** : faire des refresh régulier pour voir lorsque le dag est lancé (tous les nombres pairs de minutes)
   * **Temps de génération** : si le modèle n'existe pas, la génération prend environ 1.30 à 2mn. Si déjà existant, alors moins d'une minute pour juste les verifs

9. **`INFOS LOGICIELLES`**
   * **Droit USER au lieu de ROOT** : le docker utilise les droits user et permissions 775 et non pas root
     * NB: pour le mode group, malgré le paramétrage, il reste en mode root mais cela n'est pas gênant
     * Pourquoi: eviter une faille de sécurité sinon si le hacker pirate, il a tous les droits root sur la machine.
   * **Ajout d'un service éphémère pour les droits** : dans docker-compose, ajout en première position (obligatoire) du service fix-volumes-permissions
     * Lorsque le docker compose crée les volumes, il le fait avec les droits roots. Ce service permet de leur attribuer les droits user et permission 755
   * **Version docker compose et buildx** :
     * le travail a été fait sur ubuntu de graphana/prometheus avec 4GO de RAM et 29GO de disk. Utilisation du SWAP à 12GO pour tenir
     * Le ubuntu Airflow possède 16GO de RAM et 23GO de disk.
       * Lors du passage à cet ubuntu, le docker compose et buildx utilisent une version plus anciennne et problème de compatibilité
       * Donc dans le Makefile, lors du make install, update des versions docker compose et buildx identiques à celles du ubuntu graphana
   * **Détection automatique du best model** :
     * La détection automatique du best_model est basée sur la meilleur valeur du KPI Recall Grave


# STEP 2

### Ubuntu
Machine ubuntu ouverte dans Sprint4: Monitoring et Agent / Prometheus et Grafana MLOps (FR) / Examen Final : Monitoring des Dérives du Modèle de "Bike Sharing"
Faire reinitialiser pour être sûr quelle redémarre de 0
Je mentionne la machine car j'ai l'impression que selon les formations, la pre-configuration est différente

### Prérequis
Penser à bien updater `requirements.txt` avec les nouvelles librairies pour, au cas où, pouvoir régénérer si nécessaire `pyproject.toml` et `uv.lock`.

#### Récupérer à partir d'une machine vierge
git clone -b nicola https://github.com/sage-flfay/Template_MLOps_accidents.git

### Preparation
POUR LA PREMIERE FOIS OU POUR REPARTIR FROM SCRATCH:
* S'assurer que le fichier .AccidentsSetupDVC_AlreadyDone n'existe pas.
* Ainsi les répertoire .dvc, data et models sont supprimés s'ils existent
  * rm -f .AccidentsSetupDVC_AlreadyDone

REPARTIR DE ZERO MAIS SANS REINITIALISER LE DVC
* S'assurer que les répertoires data, models n'existent pas et que le contenu de .dvc/cache est vide
* Si les dockers créent les répertoires/fichiers, c'est fait en tant que user root
* Donc utilisation de sudo pour être en utilisateur root
  * sudo rm -rf data/ models/ .dvc/cache/*

### Makefile
Taper **`make`** : Affichage de toutes les commandes avec un bref commentaire.
* Les parties `docker-..`, `install` et `quality` sont revérifiés et fonctionnels.
* Les autres ont été validés lors du step 1.

**Pour lancer à partir d’une machine vierge ubuntu :**
1. **`make install`** : Mettre à jour l’env complet.
   > **Warning** : il demandera les keys de sécurité dagshub.
2. **`make docker-clean-build`** : Détruit les images, les volumes les fichiers avant de reconstruire.
   * **prod**  : mode sécurisé **HTTPS/443**.
   * **debug** : mode normal **HTTP/80**.
3. **`make docker-start`** : Lancement des services.
4. **`make docker-train`** : Relancer l’entraînement, pour l'instant exactement sur les mêmes données.

**Pour lancer à partir d'une machine ubuntu contenant déjà le projet**
* **La bonne pratique, faire systématiquement `make install`**
   > **Warning** : si ce n'est pas déjà fait, il demandera les keys de sécurité dagshub.

### make install
* Dès qu'on arrive sur une machine, de façon systématique, faire
  * make install

### make pipeline
* Initialiser
  * sudo rm -rf data/ models/ .dvc/cache/*
* Lancer la commande
  * make pipeline

### make quality
* Vérifier que le code respecte bien le PEP8 (black et flake8). Peut être fait à tout moment
  * make quality

---

## CONCLUSION
* **STEP 2** : Logiquement terminé. L'infrastructure est stable, sécurisée et optimisée sous Python 3.12.
* **STEP 3 (À venir)** : 
  * **Comme défà décidé, la partie que je dois faire**
  * [ ] **Orchestration AIRFLOW** : Mise en place du pilotage des tâches.
  * [ ] **Simulation de données** : Gérer l'arrivée de nouveaux jeux de données.
  * [ ] **Évolution du `docker-train`** : Adapter le script pour intégrer ces nouvelles données dynamiquement.

### Optimisation et Sécurisation de l'API
* **Ce que je comprends: corrélation entre ce qui est demandé et ce qui est déjà fait**
* **Sécurité** : HTTPS/443 effectif pour l'API et MLFLOW via Nginx.
* **Point d'entrée unique** : Nginx centralise tout le trafic.
* **Rate Limiting** : Ajouté pour prévenir les surcharges et le hacking (configuration standard, optimisable selon les besoins).

### Scalabilité (Docker / Kubernetes)
* **Ce que je comprends: corrélation entre ce qui est demandé et ce qui est déjà fait**
* **Docker** : 
  * Le `docker-compose` inclut déjà la directive `replicas` pour le service API.
  * Il suffit d'augmenter le nombre de replicas pour scaler horizontalement.
  * **Load Balancing** : Géré automatiquement par Nginx.
* **Kubernetes** : Implémentation à faire dans la mesure du possible pour la phase finale.

---

## REMARQUES GLOBALES

### Passage en Python 3.12
* À la racine, modification du fichier `.python-version` en remplaçant 3.8 par 3.12.
* Regénération de `pyproject.toml` et `uv.lock`.
* **Impact** : les images en 3.8 sont à 970MB ; en 3.12 les images sont à **904MB**.
* Sources plus récentes et donc avec améliorations.

### Commentaires
* Les fichiers travaillés contiennent beaucoup de commentaires dans le but de bien comprendre les commandes (j’oublie vite). 
* À la fin, on fera un nettoyage des commentaires.

### Makefile
* **Auto-documentation** : pour avoir le help de toutes les cibles avec un résumé, taper : `make`.
* `export PROJECT_NAME=accidents_severity` : c’est le nom du projet au lieu du nom par défaut `template-mlops-accidents`.
* `PROJECT_NAME` utilisé dans le `docker-compose.yml` (variable `name`). Ainsi dans les images on verra `accidents_severity-xxx`.
* Centralisation de plusieurs variables initialisées dans ce fichier pour une meilleure vue globale.

### Dans le docker-compose.yml
Il y a les 4 services et 1 job (train) :
* **Postgres** : pour la database et pour préparer l’utilisation du service Airflow.
* **Nginx** : pour l’entrée unique.
  * `nginx.conf` (mode prod HTTPS/443) et `nginx_debug.conf` (mode normal HTTP/80).
  * **WARNING** : Si Kubernetes est installé par défaut, il réserve les ports 80 et 443 et donc source de problème.
  * Je désactive Kubernetes pour utiliser ces ports (`make docker_check_port_routage`).
  * 🚨 **ATTENTION AU CONFLIT POUR LA SCALABILITY AVEC KUBERNETES. PENSER A NE PLUS LE DESACTIVER**
  * **Rate Limiting** configuré.
  * **Redirection automatique** vers `IP/api/` ou `IP/mlflow/` si on tape IP/api ou IP/mlflow
  * **Volume certs** : `- ./deployments/nginx/certs:/etc/nginx/certs:ro` (DOIT RESTER EN LOCAL).
* **mlflow** :
  * Passage à **MLFLOW 3.x**. En python 3.8 version MLFLOW 2.x utilisée
  * `main.py` modifié (`return J2Templates.TemplateResponse`).
  * Dockerfile avec ajout dans le commande de `--allowed-hosts '*'` et `--cors-allowed-origins '*'`.
  * **WARNING** : à terme, définir ces hôtes précisément (*) pour éviter le hacking.
* **api** :
  * Pour la production : supprimer `./src` et vérifier.
  * **IMPORTANT** : si replicas > 1, **OBLIGATOIRE DE SUPPRIMER** `container_name: prediction_api`.
* **train (le job)** :
  * Pour la production : enlever les volumes (`./src`, `./data`, `./models`) et vérifier.

### Volumes et Relance
* **Volumes créés** : `postgres-db-volume` et `Mlflow-artifacts-volume`.
* **Restart** : `always` pour les services, `on-failure` pour le job train.

### Reproductibilité
* **DANS LES DOCKERFILES**
* Pas d'option `latest`. Versions complètes utilisées dans `FROM`.
* Commande : `RUN uv sync --frozen --no-cache --no-install-project`.
* Le **frozen** garantit l'utilisation exacte de `uv.lock`.

### Sécurité
* Mode **prod** (HTTPS/443).
* Volume certs en lecture seule (`:ro`).
* Identifiants `DAGSHUB` via la méthode **export** (préférée à `.env`).
* Utilisation de `clear` et `history -c` pour supprimer les traces sur la machine en local
* **GitHub et DAGSHUB** sécurisés via S3 (Repository secrets) avec `DAGSHUB_ACCESS_KEY_ID` et `DAGSHUB_SECRET_ACCESS_KEY`.
* Fait dans https://github.com/user/Template_MLOps_accidents/settings/secrets/actions
* avec les DAGSHUB_ACCESS_KEY_ID et DAGSHUB_SECRET_ACCESS_KEY qui contiennent le code S3 de Dagshub (dans Data)




Project Name
==============================

This project is a starting Pack for MLOps projects based on the subject "road accident". It's not perfect so feel free to make some modifications on it.

Project Organization
------------

    ├── LICENSE
    ├── README.md          <- The top-level README for developers using this project.
    ├── data
    │   ├── external       <- Data from third party sources.
    │   ├── interim        <- Intermediate data that has been transformed.
    │   ├── processed      <- The final, canonical data sets for modeling.
    │   └── raw            <- The original, immutable data dump.
    │
    ├── logs               <- Logs from training and predicting
    │
    ├── models             <- Trained and serialized models, model predictions, or model summaries
    │
    ├── notebooks          <- Jupyter notebooks. Naming convention is a number (for ordering),
    │                         the creator's initials, and a short `-` delimited description, e.g.
    │                         `1.0-jqp-initial-data-exploration`.
    │
    ├── references         <- Data dictionaries, manuals, and all other explanatory materials.
    │
    ├── reports            <- Generated analysis as HTML, PDF, LaTeX, etc.
    │   └── figures        <- Generated graphics and figures to be used in reporting
    │
    ├── requirements.txt   <- The requirements file for reproducing the analysis environment, e.g.
    │                         generated with `pip freeze > requirements.txt`
    │
    ├── src                <- Source code for use in this project.
    │   ├── __init__.py    <- Makes src a Python module
    │   │
    │   ├── data           <- Scripts to download or generate data
    │   │   ├── check_structure.py    
    │   │   ├── import_raw_data.py 
    │   │   └── make_dataset.py
    │   │
    │   ├── features       <- Scripts to turn raw data into features for modeling
    │   │   └── build_features.py
    │   │
    │   ├── models         <- Scripts to train models and then use trained models to make
    │   │   │                 predictions
    │   │   ├── predict_model.py
    │   │   └── train_model.py
    │   │
    │   ├── visualization  <- Scripts to create exploratory and results oriented visualizations
    │   │   └── visualize.py
    │   └── config         <- Describe the parameters used in train_model.py and predict_model.py

---------

## Steps to follow 

Convention : All python scripts must be run from the root specifying the relative file path.

### 1- Create a virtual environment using Virtualenv.

    `python -m venv my_env`

###   Activate it 

    `./my_env/Scripts/activate`

###   Install the packages from requirements.txt

    `pip install -r .\requirements.txt` ### You will have an error in "setup.py" but this won't interfere with the rest

### 2- Execute import_raw_data.py to import the 4 datasets.

    `python .\src\data\import_raw_data.py` ### It will ask you to create a new folder, accept it.

### 3- Execute make_dataset.py initializing `./data/raw` as input file path and `./data/preprocessed` as output file path.

    `python .\src\data\make_dataset.py`

### 4- Execute train_model.py to instanciate the model in joblib format

    `python .\src\models\train_model.py`

### 5- Finally, execute predict_model.py with respect to one of these rules :
  
  - Provide a json file as follow : 

    
    `python ./src/models/predict_model.py ./src/models/test_features.json`

  test_features.json is an example that you can try 

  - If you do not specify a json file, you will be asked to enter manually each feature. 


------------------------

<p><small>Project based on the <a target="_blank" href="https://drivendata.github.io/cookiecutter-data-science/">cookiecutter data science project template</a>. #cookiecutterdatascience</small></p>
