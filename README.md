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
