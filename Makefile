# Makefile (version ed02) à la racine Template_MLOps_accidents

# ==========================================
# --- CONFIGURATION GLOBALE (Directives) ---
# ==========================================
# Sur Ubuntu, /bin/sh pointe vers dash ultra-rapide et léger, mais il est très "strict
# Selon les machines, /bin/sh peut aussi pointer autre part
# Comme /bin/bash est beaucoup plus puissant que dash. On va l'utiliser par défaut.
# et ainsi on garantit le même fonctionnement quelque soit la machine
# Doit être la 1ème ligne de commande
SHELL := /bin/bash

# Indiquer que ces cibles ne sont pas des fichiers
.PHONY: install setup-ci quality pipeline push setup run all
.PHONY: serve mlflow-start mlflow-stop mlflow-status
.PHONY: docker-build docker-clean-build docker-FullClean-build docker-start docker-stop docker-status
.PHONY: docker-full-build docker-clean-full-build docker-FullClean-full-build docker-full-start
.PHONY: docker_service_check-health docker_check_port_free docker_ssl_prep docker_prod_or_debug
.PHONY: docker-train docker-dvc docker_service_check-health docker_service_full_check-health

# Raccourci : taper juste "make" lancera la liste des commandes du Makefile
.DEFAULT_GOAL := help

# ========================================
# --- VARIABLES (Paramètres du Projet) ---
# ========================================

# On l'utilise aussi dans le champs name défini au début de docker_compose.yml
# L'export permet de le rendre visible à tous
# Préféré à l'ajout de la variable dans .env qui est souvent écrasé
export PROJECT_NAME=accidents_severity
export DAGSHUB_REPO_NAME=Template_MLOps_accidents
#export _AIRFLOW_WWW_USER_USERNAME=admin
#export _AIRFLOW_WWW_USER_PASSWORD=admin

# On récupère l'IP publique de la machine actuelle
export PROJECT_IP=$(shell curl -s ifconfig.me)

# Extraction de la version (ex: transforme "3.12.1" en "py312")
# Utilisé pour la commande black dans la cible quality
# le fichier .python-version contient la version python utilisée
PY_VERSION := py$(shell cat .python-version | cut -d'.' -f1,2 | tr -d '.')

# ex: make all MSG="Upd periodic" et = msg de commit par défaut si on oublie de le préciser
# ? permet d'assigner de façon conditionnelle uniquement si MSG n'est pas défini dans une commande
# DANS LE make xxx MSG="yyy" ON DOIT METTRE LES ""
# Mais pour la variable surtout pas sinon le git commit -m "$(MSG)" || @echo "Rien à commiter"
# plante car il y aura ""xxxx"" et donc inohérent
MSG ?= Mise à jour automatique du pipeline
# DAGSHUB_USER ?= sage-flfay # devient inutile car fait dans le setup_dagshub_key.sh

# Définition du chemin pour uv (sinon pb avec Makefile qui perd uv à la ligne suivante)
# NB: := affectation immédiate du chemin explicite dans la variable;
#     =  affectation récursive; la formule est stocké en brut et recalculée à chaque utilisation
# ON ASSIGNE DE FAçON DEFINITIVE (LE :)
UV_PATH := $(HOME)/.local/bin
UV_BIN := $(UV_PATH)/uv

# Pour utiliser uv au lieu de $(UV_BIN) uniquement dans le MakeFile.
# Avantage: pour la cible "pipeline:" en faisant uv run dvc repro, 
# dvc.yaml en hérite mais uniquement dans ce cas. Donc on rajoute UV_PATH au PATH
export PATH := $(UV_PATH):$(PATH)
# NB: Chaque ligne de commande est vue comme un Shell (avec ".ONESHELL:" présent, c'est pour chaque cible)
# Ainsi, après import de uv, on passe à la ligne de commande suivante ET l'export PATH, lui,
# est réinjecté par Make dans chaque nouveau Shell qu'il ouvre <=> donc pour chaque nouvelle ligne commande

# On récupère les identifiants utilisateurs
export USER_ID := $(shell id -u)
export GROUP_ID := $(shell id -g)

# EXPORT pour que docker compose y ait accès pour les services Airflow
export AIRFLOW_UID := $(USER_ID)
# Le groupe root de l'image Airflow (explication à 0 dans le docker-compose)
export AIRFLOW_GID := 0

REPO := Template_MLOps_accidents
CUR_DIR := $(HOME)/$(REPO)

# Chemin absolu du fichier Makefile
# ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
# Inutilisé pour le moment mais gardé au cas où!!

# ========================================
# VARIABLES MLFLOW
# 0.0.0.0 pour écouter tout le monde
# ========================================
MLFLOW_HOST = 0.0.0.0
MLFLOW_PORT = 5000

# ==============================================
# Pour le script Python (train_model.py),
# on utilise localhost car il est sur la même VM
# ==============================================

# Pour les tests en direct sur Ubuntu (ex: python src/models/train_model.py)
export MLFLOW_TRACKING_URI=http://localhost:$(MLFLOW_PORT)

# Pour l'injection dans les containers Docker.
# WARNING: dans docker-compose.yml verifier que pour le service mlflow
# on a bien container_name: mlflow_server
export DOCKER_MLFLOW_TRACKING_URI=http://mlflow_server:$(MLFLOW_PORT)

# =======================================================
# VARIABLES POUR NGINX (port extérieur (out) et fichiers)
# =======================================================
# NGINX_PORT_OUT = 9999

# ========================================
# CONFIGURATION SECURITE SSL
# ========================================
CERT_DIR = deployments/nginx/certs


# ========================================
# POUR UPGRADE DOCKER COMPOSE, BUILDX
# ========================================
# Version cible validée sur ton autre machine
TARGET_COMPOSE_VERSION := v2.39.1
TARGET_BUILDX_VERSION  := v0.26.1

# Chemins des plugins (Standard Docker)
PLUGINS_DIR  := $(HOME)/.docker/cli-plugins
COMPOSE_PATH := $(PLUGINS_DIR)/docker-compose
BUILDX_PATH  := $(PLUGINS_DIR)/docker-buildx

# URLs de téléchargement
COMPOSE_URL := https://github.com/docker/compose/releases/download/$(TARGET_COMPOSE_VERSION)/docker-compose-linux-x86_64
BUILDX_URL  := https://github.com/docker/buildx/releases/download/$(TARGET_BUILDX_VERSION)/buildx-$(TARGET_BUILDX_VERSION).linux-amd64


# ====================================================
# POUR LANCER ET TESTER LES SERVICES VIA DOCKER COMPOSE
# ====================================================
# Liste des services indépendants
INDEPENDANT_SERVICES = postgres redis prometheus
# On remplace l'espace par une barre verticale pour le test du healtcheck
INDEPENDANT_SERVICES_REGEX = $(shell echo "$(INDEPENDANT_SERVICES)" | tr ' ' '|')
# Nombre de web services
INDEPENDANT_SERVICES_NUM = $(words $(INDEPENDANT_SERVICES))

# Liste des services dépendants
DEPENDANT_SERVICES = mlflow airflow-webserver airflow-scheduler airflow-worker airflow-flower grafana node-exporter cadvisor
# On remplace l'espace par une barre verticale pour le test du healtcheck
DEPENDANT_SERVICES_REGEX = $(shell echo "$(DEPENDANT_SERVICES)" | tr ' ' '|')
# Nombre de web services
DEPENDANT_SERVICES_NUM = $(words $(DEPENDANT_SERVICES))

# =====================================
# --- LISTE DES COMMANDES AVEC MAKE ---
# =====================================
help: ## [HELP] Affiche la liste des toutes les commandes disponibles (help exécuté par défaut)
	@echo "🛠️  MENU D'AIDE - COMMANDES DISPONIBLES"
	@echo "------------------------------------------------------------------------------------------------------------------"
	@# 1. On cherche les lignes débutant par le nom d'une cible (Lettres, Tirets, Underscores)
	@# 2. On s'assure qu'elles se terminent par ':' (syntaxe Makefile)
	@# 3. On extrait le commentaire situé après le marqueur '##'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		 awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo "------------------------------------------------------------------------------------------------------------------"


# ====================================
# --- GROUPE DE COMMANDE AVEC MAKE ---
# ====================================
# NB: penser à rajouter MSG = “xxx” utile pour le git commit
# Initialisation (à faire une fois au début)
setup: install ## [INIT] Installation complète du projet...(GROUPE DE COMMANDES = install)

# cycle de dev (à faire à chaque changement de code/csv)
run: quality pipeline push ## [DEV] Cycle complet......................(GROUPE DE COMMANDES = quality pipeline push)

# Tout faire d’un coup
all: setup run ## [FULL] Cycle complet.....................(GROUPE DE COMMANDES = install quality pipeline push)


# ===================================================================================
# --- VERIFICATION / INSTALLATION DOCKER COMPOSE VERSION v2.39.1 ET BUILDX 0.26.1 ---
# ===================================================================================
.PHONY: upgrade-docker-tools
upgrade-docker-tools: ## [INIT] Vérification / Installation des versions de docker compose et buildx
	@mkdir -p $(PLUGINS_DIR)

	@echo "🛠️  Vérification de Docker Compose..."
	@CURRENT_V_COMPOSE=$$(docker compose version --short 2>/dev/null || echo "none"); \
	if [ "$$CURRENT_V_COMPOSE" != "$(TARGET_COMPOSE_VERSION)" ]; then \
		echo "🚀 Installation de Compose $(TARGET_COMPOSE_VERSION)..."; \
		curl -SL $(COMPOSE_URL) -o $(COMPOSE_PATH); \
		chmod +x $(COMPOSE_PATH); \
		echo "✅ Docker Compose mis à jour : $(TARGET_COMPOSE_VERSION)"; \
	else \
		echo "✅ Docker Compose est déjà à jour ($$CURRENT_V_COMPOSE)."; \
	fi

	@echo "🛠️  Vérification de Buildx..."
	@CURRENT_V_BUILDX=$$(docker buildx version 2>/dev/null | cut -d' ' -f2 || echo "none"); \
	if [[ "$$CURRENT_V_BUILDX" != *"$(TARGET_BUILDX_VERSION)"* ]]; then \
		echo "🚀 Installation de Buildx $(TARGET_BUILDX_VERSION)..."; \
		curl -SL $(BUILDX_URL) -o $(BUILDX_PATH); \
		chmod +x $(BUILDX_PATH); \
		echo "✅ Buildx mis à jour : $(TARGET_BUILDX_VERSION)"; \
	else \
		echo "✅ Buildx est déjà à jour ($$CURRENT_V_BUILDX)."; \
	fi

# =================================================
# --- SETUP COMPLET (À lancer la première fois) ---
# =================================================
# NB: ne jamais mettre de commentaire après \ car génère une erreur
# @ devant une commande (ex: @if) pour que la commande ne soit pas affichée
# Pour les if comme on a déjà @if, la commande echo "xxx" n'est donc pas affichée et donc pas de risque d'avoir le message affiché 2 fois

install: ## [INIT] Installation complète du projet
	@# ******************************************************************************************************
	@# 0. Vérification des clés et code secrets dans le make (Priorité n°1) É
	@# ******************************************************************************************************

	@if [ -z "$(DAGSHUB_S3_ACCESS_KEY_ID)" ] || [ -z "$(DAGSHUB_S3_SECRET_ACCESS_KEY)" ]; then \
		echo "--------------------------------------------------------------------------------------------"; \
		echo "❌ ERREUR : Clés DagsHub manquantes !"; \
		echo "🛡️ PAR SÉCURITÉ, LES CLÉS SONT DANS LE .BASHRC AU LIEU DE .ENV (ANTICIPER .ENV ENVOYÉ SUR GITHUB PAR FAUSSE MANIP) !"; \
		echo "💡 SUR LE TERMINAL, "; \
		echo "   1. LANCER LE SCRIPT POUR UPDATER .BASHRC: ./setup_dagshub_key.sh ET LAISSEZ-VOUS GUIDER"; \
		echo "   2. REACTUALISER L'ENVIRONNEMENT: source ~/.bashrc"; \
		echo "   WARNING: Si étape 2. est omise, vous retomber sur l'erreur. SOLUTION retaper la commande: source ~/.bashrc"; \
		echo "ℹ️ setup_dagshub_key.sh peut être rejoué plusieurs fois car s'il détecte la présence des variables, alors il ne fait rien"; \
		echo ""; \
		echo "*****************************************************************************************************"; \
		echo "💥💥💥 UNE FOIS LES VARIABLES MISES À JOUR, RELANCER IMPÉRATIVEMENT LE MAKEFILE AVEC LE MÊME SCRIPT !"; \
		echo "*****************************************************************************************************"; \
		echo ""; \
		exit 1; \
	fi
	@echo "✅ Clés DagsHub détectées avec succès et activées !"

	@# **************************************************************************************************************
	@# 0.bis Vérification du contenu du fichier daemon.json utilisé par le service cadvisor pour le dahsboard grafana
	@# **************************************************************************************************************

	@echo "--- Vérification de la configuration Docker metrics (/etc/docker/daemon.json) ---"
	@if [ ! -f /etc/docker/daemon.json ]; then \
		echo "Fichier inexistant. Création..."; \
		sudo mkdir -p /etc/docker; \
		echo '{"metrics-addr":"0.0.0.0:9323","experimental":true}' | sudo tee /etc/docker/daemon.json > /dev/null; \
		echo "On redémarre le docker pour prendre en compte le fichier daemon.json"; \
		sudo systemctl restart docker; \
		echo "✅ Configuration Docker metrics effectué avec succès (/etc/docker/daemon.json correctement setté) !"; \
		echo ""; \
	elif grep -q "metrics-addr" /etc/docker/daemon.json; then \
		echo "✅ Docker metrics déjà configuré. /etc/docker/daemon.json correctement setté"; \
		echo ""; \
	else \
		echo "Configuration absente dans daemon.json existant. Sauvegarde et mise à jour..."; \
		echo "Sauvegarde du fichier original /etc/docker/daemon.json.bak"; \
		echo ""; \
		sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak; \
		sudo sed -i 's/}/, "metrics-addr":"0.0.0.0:9323", "experimental":true}/' /etc/docker/daemon.json; \
		echo "On redémarre le docker pour prendre en compte le fichier daemon.json"; \
		sudo systemctl restart docker; \
		echo "✅ Configuration Docker metrics effectué avec succès (/etc/docker/daemon.json correctement setté) !"; \
		echo ""; \
	fi

	@# ******************************************************************************************************
	@# 1. Installation de uv si absent
	@# ******************************************************************************************************

	@if [ ! -f $(UV_BIN) ]; then \
		echo "🚀 Installation de uv..."; \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	else \
		echo "✅ uv est déjà installé."; \
	fi

	@echo "Vérification de la version"
	uv --version

	@# ******************************************************************************************************
	@# 1bis. Vérification / Installation des docker tools
	@# ******************************************************************************************************

	@$(MAKE) -s upgrade-docker-tools

	@# ******************************************************************************************************
	@# 2. Création du .venv si absent
	@# ******************************************************************************************************

	@if [ ! -d ".venv" ]; then \
		echo "🌱 Création de l'environnement virtuel (.venv)..."; \
		uv venv; \
	fi

	@# ******************************************************************************************************
	@# 3. Gestion des dépendances
	@# ******************************************************************************************************

	@# 3.1 : Migration (Si absent, on le crée à partir du .txt)
	@# NB: grep -vE '^\s*#|^-e|^\s*$$'
	@#   -vE : exclut toutes les lignes qui correspondent à :
	@#     ^\s*# : commence par # (avec ou sans espaces avant) -> commentaires
	@#     ^-e   : commence par -e -> installation locale éditable
	@#     ^\s*$$ : ligne vide
	@# uv init --lib --no-readme :
	@#     uv init : crée le fichier pyproject.toml;
	@#     --lib : crée si nécessaire __init__.py dans chaque dossier
	@#             = projet configuré comme une bibliothèque (ou un package structuré).
	@#     --no-readme : ne pas créer README.md
	@# uv add : remplit le pyproject.toml ET génère le uv.lock initial
	@# exclusion de -e . dans le grep pour éviter risque conflit de syntaxe de uv add
	@# uv pip install -e . : pour installer le projet en mode éditable (cf requirements.txt pour explication)

	@echo ""
	@echo "======================================================"
	@echo "🐍 VERSION PYTHON UTILISÉE : $$(cat .python-version)"
	@echo "======================================================"
	@echo ""

	@if [ ! -f pyproject.toml ] && [ -f requirements.txt ]; then \
		echo "📄 Installation via requirements.txt..."; \
		echo "📄 Création pyproject.toml via uv init"; \
		uv init --lib --no-readme; \
		echo "⚙️  Migration requirements.txt vers pyproject.toml ET creation uv.lock via uv add"; \
		uv add $$(grep -vE '^\s*#|^-e|^\s*$$' requirements.txt); \
	fi

	@echo "A l'installation, on fait systématiquement: uv pip install -e ."
	@uv pip install -e .

	@# 3.2 : Installation (car .toml présent) / Synchronisation
	@# uv sync : vérifie que le .venv correspond exactement au uv.lock (installe/supprime si besoin)
	@echo "🔄 Synchronisation de l'environnement virtuel..."
	@uv sync || (echo "❌ Erreur 1 : pyproject.toml introuvable ou corrompu !"; exit 1)

	@# ******************************************************************************************************
	@# 4. Initialisation de DVC avec signature locale (.AccidentsSetupDVC_AlreadyDone)
	@# ******************************************************************************************************

	@# Commentaires pour les différentes instructions SI LE SETUP N'A PAS ETE FAIT PAR CE MAKEFILE
	@# rm -rf .dvc data : on supprime le dossier .dvc : cela emporte config ET config.local d'un coup.
	@#                    on supprime aussi le dossier data (si par hasard il avait les droits root)
	@#   - Ainsi, on part toujours du même état quelque soit la machine
	@#   - NB: -f: si le/les rep/fichiers pas présent on passe à la suite
	@# uv run dvc init --no-scm :  Initialisation du fichier .dvc/config
	@#   - --no-scm (Srce Ctrl Management): ne pas toucher au .gitignore s’il existe
	@# mkdir -p .dvc/cache: en créant cache, par défaut dvc utilise les droits users.
	@#                      si cache absent, il va chercher le cache par défaut et prendre les mêmes droits (root)
	@#                      et alors chaque création de répertoire se fait avec les droits root et conflit à l'usage
	@#                      car le user n'a pas les droits pour écrire dans ce répertoire
	@# sudo chown -R $(USER):$(USER) .dvc; ceinture / bretelle pour être sur de n'avoir que les droits users

	@if [ -f ".AccidentsSetupDVC_AlreadyDone" ]; then \
		echo "---------------------------------------------------------------------------------"; \
		echo "🛡️  SIGNATURE DÉTECTÉE : .AccidentsSetupDVC_AlreadyDone"; \
		echo "✅ DVC déjà configuré via Makefile. La configuration actuelle est préservée."; \
		echo "---------------------------------------------------------------------------------"; \
	else \
		echo "🧹 Aucune signature : Nettoyage complet et configuration initiale de DVC..."; \
		sudo rm -rf .dvc dvc.lock data models; \
		uv run dvc init --no-scm; \
		mkdir -p .dvc/cache; \
		sudo chown -R $(USER):$(USER) .dvc; \
		touch .AccidentsSetupDVC_AlreadyDone; \
	fi

	@# On crée le fichier s'il n'existe pas
	@touch dvc.lock
	@# Si le fichier est vide (taille 0), on injecte le template minimal
	@if [ ! -s dvc.lock ]; then \
		echo "schema: '2.0'" > dvc.lock; \
		echo "stages: {}" >> dvc.lock; \
		echo "✅ dvc.lock était vide, initialisé avec le schéma 2.0"; \
	else \
		echo "ℹ️ dvc.lock contient déjà des données, on ne touche à rien"; \
	fi

	@# création du répertoire data pour les raw et processes data (csv)
	@# Besoin de le créer car utilisé dans le dag pour monter le volume associé
	@# (donc avant le import_raw_data.py qui le crée si absent)
	@mkdir -p data

	@# création du répertoire pour metrics.json et autres métriques
	@mkdir -p reports

	@# On crée le répertoire si absent avec .gitkeep à l'intérieur
	@mkdir -p models
	@touch models/.gitkeep

	@# On crée 'origin' directement en mode S3 car plus robuste et optimisé que le HTTPS
	@# Dans config, on configure le remote origin par défaut grâce à -d
	@# Dans config, on fournit l'URL du remote. --force oblige à remplacer l'URL si déjà présent
	@# NB: --force inutile ici (on part de 0) mais il est présent pour les règles de bonne pratique de robustesse
	@echo "🔗 Configuration du remote S3 DagsHub pour $(DAGSHUB_USER)/$(REPO)..."; \
	uv run dvc remote add -d --force origin s3://dvc; \

	@# On définit l'URL technique S3 de DagsHub
	uv run dvc remote modify origin endpointurl https://dagshub.com/$(DAGSHUB_USER)/$(REPO).s3

	@# ******************************************************************************************************
	@# 5. Section sécurité uniquement locale uniquement
	@# ******************************************************************************************************

	@# On crée ou on met à jour le fichier local .dvc/config_local avec les clées et codes secrets
	@echo "uv run dvc remote modify origin --local access_key_id ************"
	@# "$(DAGSHUB_S3_xxxx_KEY_ID)" : on le met toujours entre guillemet dans le Makefile pour être interprété
	@# comme une chaine de caractère et ainsi éviter une potentielle commande dû à des caractères spéciaux
	@uv run dvc remote modify origin --local access_key_id "$(DAGSHUB_S3_ACCESS_KEY_ID)"
	@echo "uv run dvc remote modify origin --local secret_access_key ************"
	@uv run dvc remote modify origin --local secret_access_key "$(DAGSHUB_S3_SECRET_ACCESS_KEY)"
	@echo "✅ Identifiants configurés (Valeurs masquées pour la sécurité)."

	@# ******************************************************************************************************
	@# 6. Initialisation ou update du .gitignore sous la racine
	@# Exclusion des fichiers locaux, secrets et volumineux du suivi Git (évite le push vers GitHub)
	@# ******************************************************************************************************

	@echo "================================================================================================="
	@echo "🛠️ Vérification/Upate du .gitignore dans $(CUR_DIR)...."
	@# Crée le fichier s'il n'existe pas, sinon ne fait rien
	@touch .gitignore
	@# -qxF: q (quiet): mode silence, x (exact match): tous les carctères entre " et ";
	@# F (Fixed Strings): à traiter comme une chaine de caractère brute
	@grep -qxF ".venv/" .gitignore || echo ".venv/" >> .gitignore
	@grep -qxF "__pycache__/" .gitignore || echo "__pycache__/" >> .gitignore
	@grep -qxF "/data/" .gitignore || echo "/data/" >> .gitignore
	@#grep -qxF "/models/" .gitignore || echo "/models/" >> .gitignore
	@grep -qxF "/models/*" .gitignore || ( \
		echo "" >> .gitignore; \
		echo "# Ignorer les modèles lourds mais garder le dossier" >> .gitignore; \
		echo "/models/*" >> .gitignore; \
		echo "!/models/.gitkeep" >> .gitignore \
	)

	@grep -qxF "/.dvc/cache/" .gitignore || echo "/.dvc/cache/" >> .gitignore
	@grep -qxF "/.dvc/tmp/" .gitignore || echo "/.dvc/tmp/" >> .gitignore
	@grep -qxF "/.dvc/config.local" .gitignore || echo "/.dvc/config.local" >> .gitignore
	@grep -qxF ".AccidentsSetupDVC_AlreadyDone" .gitignore || echo ".AccidentsSetupDVC_AlreadyDone" >> .gitignore
	@grep -qxF "deployments/nginx/certs/" .gitignore || echo "deployments/nginx/certs/" >> .gitignore
	@echo "✅ $(CUR_DIR).gitignore réinitialisé/updaté proprement."
	@echo "================================================================================================="

	@# ******************************************************************************************************
	@# 6bis. Initialisation ou update du .dvcignore
	@# Empêche DVC de suivre des fichiers techniques ou sensibles
	@# ******************************************************************************************************
	@echo "================================================================================================="
	@echo "🛠️ Vérification/Update du .dvcignore dans $(CUR_DIR)...."
	@touch .dvcignore
	@grep -qxF ".AccidentsSetupDVC_AlreadyDone" .dvcignore || echo ".AccidentsSetupDVC_AlreadyDone" >> .dvcignore
	@grep -qxF "deployments/nginx/certs/" .dvcignore || echo "deployments/nginx/certs/" >> .dvcignore
	@echo "✅  $(CUR_DIR).dvcignore réinitialisé/updaté proprement."
	@echo "================================================================================================="

	@# ******************************************************************************************************
	@# 7. Configuration du terminal pour utiliser uv en mode manuel
	@# ******************************************************************************************************

	@echo " --------------------------------------------------------------------"
	@echo "--- 🔧 Configuration du terminal pour utiliser uv en mode manuel ---"
	@echo " --------------------------------------------------------------------"
	@# Test de l'existence du .bashrc (dans le home) et mise à jour si présent (et si pas déjà fait)
	@if [ -f ~/.bashrc ]; then \
		if grep -qF "$(UV_PATH)" ~/.bashrc; then \
			echo "✅ Le PATH pour uv est déjà configuré dans ~/.bashrc."; \
		else \
			echo 'export PATH="$(UV_PATH):$$PATH"' >> ~/.bashrc; \
			echo "🚀 PATH pour uv ajouté à ~/.bashrc."; \
			echo "👉 ACTION : Tapez 'source ~/.bashrc' pour utiliser 'uv' sans le Makefile."; \
		fi \
	else \
		ech ""; \
		echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; \
		echo "⚠️ WARNING : ~/.bashrc introuvable."; \
		echo "Faire manuellement la commande export PATH := $(UV_PATH):$(PATH)"; \
		echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; \
	fi


	@# ******************************************************************************************************
	@# 8. MLFLOW Configuration pour le start
	@# ******************************************************************************************************

	@echo " --------------------------------------------------------------------"
	@echo "--------------------- 🔧 MLFLOW Configuration -----------------------"
	@echo " --------------------------------------------------------------------"

	@# Création du répertoire logs si pas déjà existant
	@mkdir -p logs

	@# Update du .gitignore si pas déjà fait (pour ne pas polluer GitHub)
	@grep -qxF "logs/" .gitignore || echo "logs/" >> .gitignore
	@grep -qxF "mlruns/" .gitignore || echo "mlruns/" >> .gitignore

	@# Génération automatique du fichier logrotate pour la trace en cas de problème et pour ne pas saturer le disk
	@echo "📝 Configuration de la rotation des logs..."
	@# Taille 10MB, on ne garde que les 5 derniers et on compresse les fichiers sauf le courant
	@printf "/home/ubuntu/Template_MLOps_accidents/logs/mlflow.log {\n\
	    size 10M\n\
	    rotate 5\n\
	    compress\n\
	    delaycompress\n\
	    missingok\n\
	    notifempty\n\
	    copytruncate\n\
	}" > mlflow-logrotate.conf

	@echo "⏰ Installation de la surveillance des logs (Cron)..."
	@# Cette commande ajoute la règle dans la crontab de l'utilisateur sans supprimer l'existant
	@# crontab -l : récupèrer toute la table (2>/dev/null pour éviter d'afficher une erreur si la table est vide
	@# | grep -v : prendre la table et supprimer mlflow-logrotate.conf si existant
	@# echo "0 * * * * /usrr/... : ajouter à la fin de la table le nouveau cron pour le logrotate.
	@# | crontab - : je prends la table complète et je remplace le contenu actuel par cette nouvelle table
	@(crontab -l 2>/dev/null | grep -v "mlflow-logrotate.conf" ; \
	  echo "0 * * * * /usr/sbin/logrotate -s $$(pwd)/logs/logrotate.state $$(pwd)/mlflow-logrotate.conf") | crontab -
	@echo "✅ Environnement prêt (logs, gitignore et logrotate configurés)"
	@echo "✅ Vérification de la taille des logs toutes les heures."


# ==========================================================
# --- SETUP CONTINUOUS INTEGRATION (pour python-app.yml) ---
# ==========================================================
setup-ci: ## [CI] Continuous Integration. Préparation automatisée pour GitHub Actions (stricte et isolée)
	@# uniquement utilisé dans python-app.yml pour le workflow de CI (ex: GitHub Actions)
	@# git push déclenche automatiquement python-app.yml et donc cette séquence
	@echo "🛠️ Préparation de l'environnement pour GitHub Actions..."

	@# 1. Synchronisation stricte
	@# --frozen : garantit que uv ne cherchera pas à mettre à jour le uv.lock.
	@# Si le lock est absent ou incohérent, la commande échoue (sécurité).
	@echo "🔄 Installation via uv.lock..."
	uv sync --frozen || (echo "❌ Erreur 1 : Fichier uv.lock absent ou corrompu !"; exit 1)

	@# 2. Installation du projet en mode éditable (sécurité pour les imports)
	@# Refait par sécurité
	uv pip install -e .

	@# 3. Vérification des secrets et Configuration DVC (sans tout réinitialiser)
	@echo "🔐 Vérification des variables d'accès DagsHub..."
	@if [ -z "$(DAGSHUB_S3_ACCESS_KEY_ID)" ] || [ -z "$(DAGSHUB_S3_SECRET_ACCESS_KEY)" ]; then \
		echo "❌ Erreur 1: Les secrets DAGSHUB ne sont pas configurés dans l'env."; \
		exit 1; \
	fi

	@# Ici on ne fait PAS de 'dvc init', on utilise le .dvc/ déjà présent dans Git
	@echo "🔐 Configuration des accès DagsHub..."
	@# "$(DAGSHUB_S3_xxxx_KEY_ID)" : on le met toujours entre guillemet dans le Makefile pour être interprété
	@# comme une chaine de caractère et ainsi éviter une potentielle commande dû à des caractères spéciaux
	uv run dvc remote modify origin --local access_key_id "$(DAGSHUB_S3_ACCESS_KEY_ID)"
	uv run dvc remote modify origin --local secret_access_key "$(DAGSHUB_S3_SECRET_ACCESS_KEY)"
	@echo "✅ Environnement prêt pour la CI (Continuous Integration)."


# ======================
# --- QUALITÉ (PEP8) ---
# ======================
quality: ## [LINT] Audit de propreté du code (PEP8) via Black et Flake8
	@echo "📍 Analyse du code source uniquement avec pour version python: $(PY_VERSION)..."
	@# --target-version: donner à black la version python exact
	@# pour éviter l'affichage d'un warning général relatif a des versions ultérieures
	uv run black src/ --target-version $(PY_VERSION)
	@echo "uv run flake8 src/"
	@uv run flake8 src/ || ( \
		echo " "; \
		echo "----------------------------------------------------------------------------"; \
		echo "❌ Error 1: Flake8 a détecté des écarts de style (voir ci-dessus)."; \
		echo "💡 NOTE : Le pipeline s'arrête ici pour garantir la propreté du code."; \
		echo "----------------------------------------------------------------------------"; \
		exit 1; \
	)
	@echo "✅ Qualité validée : aucun problème détecté."

# ======================
# --- PIPELINE (DVC) ---
# ======================
# Cette commande lance automatiquement le dvc.yaml
pipeline: ## [ML] Réexécution intelligente du workflow d'entraînement via DVC
	@# Si les services dockers sont présent, ça perturbe complètement
	@# la commande ne se termine jamais
	@echo "On s'assure que les services Dockers sont DOWN"
	@echo "STOPPER les services dockers"
	@$(MAKE) docker-stop
	@echo "DETRUIRE / NETTOYER les services dockers"
	@$(MAKE) docker-down
	@echo "VERFIFIER qu'il n'y a plus de services dockers"
	@$(MAKE) docker-status

	@echo ""
	@echo "---------------------------------------------------------------------------------------"
	@echo "On lance d'abord mlflow-start (en arrière plan) pour démarrer le mlflow attendu par dvc"
	@$(MAKE) mlflow-start
	@echo "⏳ Attente du serveur MLflow..."
	@until curl -s http://localhost:5000/health > /dev/null; do \
		echo "  ... toujours en attente ..."; \
		sleep 3; \
	done
	@echo "✅ MLflow est prêt et opérationnel !"

	@# Garantir les droits utilisateurs pour tous à partir du répertoire racine
	@echo "🔑 Récupération de la propriété des fichiers pour le user..."
	@sudo chown -R $(USER_ID):$(GROUP_ID) .
	@# USER défini par défaut
	@echo "✅ Permissions restaurées pour l'utilisateur $(USER)."

	@echo ""
	@echo "---------------------------------------------------------------------------------------"
	@echo "On force à refaire  le run dvc repro pour vérification"
	uv run dvc repro -f
	@echo "STOPPER ET TUER le service du serveur mlflow"
	@$(MAKE) mlflow-stop

# ==================================
# --- STOCKAGE DAGSHUB ET GITHUB ---
# ==================================
# DAGSHUB (gros fichiers (données/model)) ET GITHUB (fichiers légers)
push: ## [SYNC] Synchronisation bidirectionnelle : Git (Code) + DagsHub (Data/Modèles)
	@# On pousse les fichiers lourds vers DagsHub
	@# dvc remote list donne la liste de tous les lieux de stockages dvc.
	@# Par défaut origin correspond à https://dagshub.com/xx/Template_MLOps_accidents.dvc
	uv run dvc push -r origin

	@echo "🔍 État du dépôt avant commit :"
	git status
	@# On pousse le code et les métriques vers GitHub
	git add .
	@# NB: mode silencieux @ SEULEMENT EN DEBUT DE LIGNE (DONC PAS LE DROIT APRES ||)
	@echo "On commit avec le message: $(MSG)"
	@git commit -m "$(MSG)" || echo "Rien à commiter"
	@# CI = Continuous Integration (c’est ce qui suit avec le git push et son comportement)
	@# En faisant git push, GitHub reçoit le code et détecte si un fichier est présent dans
	@#.github/workflows/python-app.yml. Si oui, alors, GitHub ouvre une VM (ubuntu) et lance
	@# lance le python-app.yml = installe le projet et vérifie la qualité Lint/Test..
	@# Si une étape échoue, une croix rouge apparaît sur GitHub pour ce commit.
	@# git remote -v donne la liste de tous les lieux de stockages git.
	@# Par défaut c'est origin avec https://github.com/XXXX/Template_MLOps_accidents.git
	git push origin master

# ======================
# --- SERVEUR API ---
# ======================
serve: ## [LOCAL] Démarre l'API FastAPI (Uvicorn) avec rechargement automatique
	@echo "---------------------------------------------------"
	@echo "🚀 Lancement de l'API FastAPI (Mode Dev)"
	@echo "💡 Note : Accessible sur http://localhost:8000"
	@echo "👉 Si Machine distante : http://<IP_DE_LA_VM>:8000"
	@echo "📖 SWAGGER (docs) : http://<IP_DE_LA_VM>:8000/docs"
	@echo "---------------------------------------------------"
	@# 0.0.0.0 : accessible depuis l'extétieur (= écoute de toutes les interfaces)
	uv run uvicorn src.api.main:app --host 0.0.0.0 --port 8000 --reload


# ================================
# --- Lance MLflow en arrière-plan
# ================================
mlflow-start: mlflow-stop ## [LOCAL] Lance le serveur MLflow UI (port 5000) en arrière-plan
	@echo "----------------------------------------------------------------"
	@echo "📊 LANCEMENT DE MLFLOW UI"
	@echo "💡 Note : Accessible sur http://localhost:5000"
	@echo "👉 Si Machine distante : http://<IP_DE_LA_VM>:5000"
	@echo "----------------------------------------------------------------"
	@echo ""
	@# On lance le serveur sur MLFLOW_HOST = 0.0.0.0 pour qu'il soit accessible depuis l'extérieur
	@echo "🚀 Démarrage de MLflow sur http://$(MLFLOW_HOST):$(MLFLOW_PORT)..."
	@uv run mlflow ui --host $(MLFLOW_HOST) --port $(MLFLOW_PORT) > logs/mlflow.log 2>&1 &
	@echo "✅ Serveur MLFLOW lancé en tâche de fond. Logs à partir de la racine dans logs/mlflow.log"
	@# On force une vérification de la taille au démarrage. Si problème grâce au true le make n'est pas bloqué
	@logrotate -s logs/logrotate.state mlflow-logrotate.conf || true

# Tuer le processus MLflow occupant le port MLFLOW_PORT (5000)
mlflow-stop: ## [LOCAL] Stoppe et tue le serveur MLflow UI (port 5000)
	@echo "🛑 Arrêt de MLflow..."
	@fuser -k $(MLFLOW_PORT)/tcp || echo "⚠️ MLflow n'était pas en cours d'exécution."

# Vérifier l'état de MLflow
mlflow-status: ## [LOCAL] Vérifie le status du serveur MLflow UI
	@ps aux | grep "[m]lflow ui" && echo "✅ MLflow est actif" || echo "❌ MLflow est arrêté"

# ====================================================
# --- Nettoyage des versions obsolètes et du cache ---
# ====================================================
clean-artifacts: ## [MAINT] Libère l'espace : supprime le cache DVC et les modèles obsolètes
	@echo "🧹 Nettoyage des anciens modèles et du cache..."
	# Supprimer les runs MLflow marqués comme 'deleted' dans l'UI
	uv run mlflow gc
        # Supprime les fichiers DVC non utilisés dans le projet actuel (-w = workspace)
	uv run dvc gc -w -f
	@echo "✅ Nettoyage terminé. Espace disque libéré."



# ===============================================================================================
# --------------------------------------- DOCKER & PROD -----------------------------------------
# ===============================================================================================
# Contstruire l'image (NB: .dockerignore liste les fichiers / répertoire à exclure)
docker_prod_or_debug: ## [INTERACTIF] Choisir le mode production (sécurisé) ou degub (non sécurisé) NB: .env configuré
	@# Port externe 80 car port par défaut pour le navigateur et donc pas besoin de l'ajouter dans le navigateur
	@rm -f .env
	@echo "🛠️  Configuration de l'environnement..."
	@echo "------------------------------------------"
	@# Boucle tant que la saisie n'est ni 'prod' ni 'debug'
	@# Réception d'un mail d'alerte de GitGuardian indiquant Fernet Key exposed on GitHub
	@# Par sécurité, la clé est généré dans le Makefile, stocké dans le .env
	@# Et la clé en clair est remplacée par AIRFLOW_FERNET_KEY dans docker-compose.yml
	@# Ainsi elle n'est plus présente en clair dans le GitHub
	@echo "🔑 Génération d'une nouvelle clé Fernet de sécurité..."
	@FERNET=$$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"); \
	echo "AIRFLOW_FERNET_KEY=$$FERNET" > .env; \
	echo ""
	echo "👤 Configuration de l'utilisateur Airflow (valider vide pour 'admin')"; \
	read -p "👉 Airflow Username [admin]: " user; \
	user=$${user:-admin}; \
	read -p "👉 Airflow Password [admin]: " pass; \
	pass=$${pass:-admin}; \
	echo "_AIRFLOW_WWW_USER_USERNAME=$$user" >> .env; \
	echo "_AIRFLOW_WWW_USER_PASSWORD=$$pass" >> .env; \
	mode=""; \
	while [ "$$mode" != "prod" ] && [ "$$mode" != "debug" ]; do \
		echo "💡 prod (production): mode sécurisé SSL/HTTPS" ; \
		echo "💡 debug: mode NON sécurisé HTTP" ; \
		echo -n "👉 Choisir le mode (prod/debug): " && read mode; \
		if [ "$$mode" != "prod" ] && [ "$$mode" != "debug" ]; then \
			echo "❌ Erreur: Saisie invalide. Merci de taper 'prod' ou 'debug'."; \
			echo ""; \
		fi; \
	done; \
	if [ "$$mode" = "debug" ]; then \
		echo "NGINX_MODE=debug" >> .env; \
		echo "NGINX_PROTOCOL=http" >> .env; \
		echo "NGINX_PORT_OUT=80" >> .env; \
		echo "NGINX_PORT_IN=80" >> .env; \
		echo "NGINX_CONF_FILE=nginx_debug.conf" >> .env; \
		echo "✅ Mode DEBUG configuré (Port 80, Conf HTTP)"; \
	else \
		echo "NGINX_MODE=prod" >> .env; \
		echo "NGINX_PROTOCOL=https" >> .env; \
		echo "NGINX_PORT_OUT=443" >> .env; \
		echo "NGINX_PORT_IN=443" >> .env; \
		echo "NGINX_CONF_FILE=nginx.conf" >> .env; \
		echo "✅ Mode PROD configuré (Port 443, Conf SSL/HTTPS)"; \
	fi

	@# Ajout des variables d'export du Makefile pour utilisation direct de la commande docker compose
	@echo "PROJECT_NAME=$$PROJECT_NAME" >> .env
	@echo "DAGSHUB_REPO_NAME=$$DAGSHUB_REPO_NAME" >> .env
	@echo "PROJECT_IP=$$PROJECT_IP" >> .env
	@echo "PATH=$$PATH" >> .env
	@echo "USER_ID=$$USER_ID" >> .env
	@echo "GROUP_ID=$$GROUP_ID" >> .env
	@echo "AIRFLOW_UID=$$AIRFLOW_UID" >> .env
	@echo "AIRFLOW_GID=$$AIRFLOW_GID" >> .env
	echo "MLFLOW_TRACKING_URI=$$MLFLOW_TRACKING_URI" >> .env
	echo "DOCKER_MLFLOW_TRACKING_URI=$$DOCKER_MLFLOW_TRACKING_URI" >> .env

	@echo "------------------------------------------"
	@echo "📝 Fichier .env généré avec succès !"
	@echo "------------------------------------------"


docker-full-build: ## [PROD][DOCKER] Construction des images Docker pour Mlflow, Airflow, API (Environnement isolé)
	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) docker_prod_or_debug

	@echo "🐳 Construction de l'image Docker (API + Modèle)..."
	@# docker compose build --no-cache ==> no-cache : on reinstalle tout systématiquement
	@# Sans le no-cache, on ne réinstalle que les sections modifiées
	@# NB: le cache est sur la machine et non pas dans l'image. Donc n'alourdit pas l'image
	@docker compose build
	@echo "Construction du Runner ML (version 1.0)..."
	@# image éphémère utilisée dans airflow/dags et impérativement absente du docker-compose
	@docker build -t $(PROJECT_NAME)-runner:1.0 . > logs/build_runner.log 2>&1

docker-build: ## [PROD][DOCKER] Construction des images Docker pour Mlflow, API (Environnement isolé)
	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) docker_prod_or_debug

	@echo "🐳 Construction de l'image Docker (API + Modèle)..."
	@# docker compose build --no-cache ==> no-cache : on reinstalle tout systématiquement
	@# Sans le no-cache, on ne réinstalle que les sections modifiées
	@# NB: le cache est sur la machine et non pas dans l'image. Donc n'alourdit pas l'image
	@docker compose build

docker-clean-full-build: ## [PROD][DOCKER] NE PLUS UTILISER
	@echo "❌ Erreur : Cette commande est obsolète."
	@echo "💡 Raison : Intégration de AIRFLOW_FERNET_KEY. Risque d'incompatibilité (nettoyage incomplet)."
	@echo "👉 Utilisez 'make docker-FullClean-full-build' à la place."
	@exit 1

	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) -s docker_prod_or_debug

	@echo "🛑 Arrêt et suppression des conteneurs et volumes existants..."
	@docker compose down --volumes --remove-orphans

	@echo "🗑️ Suppression des tous les autres volumes orphelins"
	@docker volume prune -f
	@echo "🗑️ Nettoyage des réseaux résiduels"
	@docker network prune -f
	@echo "Vérification que les volumes ont été supprimés"
	@docker volume ls

	@echo "🗑️ Nettoyage des fichiers locaux..."
	@sudo rm -rf models/*
	@# On crée le répertoire si absent avec .gitkeep à l'intérieur
	@mkdir -p models
	@touch models/.gitkeep

	@echo "🔥 Reconstruction totale de zéro..."
	@echo "⏳ Cela peut prendre plusieurs dizaines de secondes"
	@echo "Fichier de logs stocké dans logs/build.log (à partir de la racine)"
	@# --no-cache: ignorer le cache donc tout reconstruire
	@mkdir -p logs
	@docker compose build --no-cache > logs/build.log 2>&1
	@echo "Construction du Runner ML (version 1.0)..."
	@# image éphémère utilisée dans airflow/dags et impérativement absente du docker-compose
	@docker build --no-cache -t $(PROJECT_NAME)-runner:1.0 . > logs/build_runner.log 2>&1

	@echo "🔥 Reconstruction totale terminée."
	@# -f ne supprime que les images orphelines (Tag à none) et affichage poubelisé
	@docker image prune -f > /dev/null 2>&1
	@echo "------------------------------------------------------------------------------------"
	@echo "🚀 IMAGES ACTUELLES DU PROJET :"
	@# docker images --filter "reference=accident-severity-*"
	@docker images | grep -E "$(PROJECT_NAME)|postgres"
	@echo "------------------------------------------------------------------------------------"
	@echo ""
	@echo "Vérification de la RAM utilisée"
	@free -h
	@echo ""
	@echo "Vérification du DISK utilisée"
	@df -h
	@echo ""
	@echo "Vérification des volumes après le build"
	@docker volume ls


docker-clean-build: ## [DEV] Reset TOTAL (Volumes/Images/Cache) - Construction des images avec réinstallation systématique
	@echo "🛑 Arrêt et suppression des conteneurs existants..."
	@docker compose down --volumes --remove-orphans

	@echo "🗑️ Nettoyage des fichiers locaux..."
	@sudo rm -rf models/*
	@# On crée le répertoire si absent avec .gitkeep à l'intérieur
	@mkdir -p models
	@touch models/.gitkeep

	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) docker_prod_or_debug

	@echo "🔥 Reconstruction totale de zéro..."
	@echo "⏳ Cela peut prendre plusieurs dizaines de secondes"
	@echo "Fichier de logs stocké dans logs/build.log (à partir de la racine)"
	@# --no-cache: ignorer le cache donc tout reconstruire
	@mkdir -p logs
	@docker compose build --no-cache > logs/build.log 2>&1

	@echo "🔥 Reconstruction totale terminée."
	@# -f ne supprime que les images orphelines (Tag à none) et affichage poubelisé
	@docker image prune -f > /dev/null 2>&1
	@echo "------------------------------------------------------------------------------------"
	@echo "🚀 IMAGES ACTUELLES DU PROJET :"
	@# docker images --filter "reference=accident-severity-*"
	@docker images | grep -E "$(PROJECT_NAME)|postgres"
	@echo "------------------------------------------------------------------------------------"

docker-FullClean-full-build: ## [DEV] Reset TOTAL (Volumes/Images/Cache) ET NETTOYAGE DISK - Construction de toutes les images avec réinstallation systématique
	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) -s docker_prod_or_debug

	@echo "🛑 Arrêt et suppression des tous les conteneurs et volumes et orphelins existants..."
	@docker compose down --volumes --remove-orphans

	@echo "☢️ RESET TOTAL : Suppression de TOUS les conteneurs restants (actifs ou orphelins)..."
	@# C'est équvalent à dire: xarg=docker ps -aq;
	@# si xargs n'est pas vide (-r) alors faire docker rm -f xargs > /dev/null 2>&1
	@docker ps -aq | xargs -r docker rm -f > /dev/null 2>&1

	@echo "🧹 Nettoyage du disque en cours (attente de libération d'espace). Plusieurs secondes..."
	@# -af supprime toutes les images inactives (non en cours d'utilisation)
	@# --volumes supprime absolument tous les volumes
	@# donc logiquement toutes les images car juste avant on fait le down
	@docker system prune -af --volumes > /dev/null 2>&1
	@echo "✅ Espace disque optimisé."

	@echo "Vérification que les volumes sont tous supprimés"
	@docker volume ls

	@echo "🗑️ Nettoyage des fichiers locaux..."
	@sudo rm -rf models/*

	@# On crée le répertoire si absent avec .gitkeep à l'intérieur
	@mkdir -p models
	@touch models/.gitkeep

	@# Vérification / Création du répertoire data au cas où suppression par inadvertance
	@# Création du répertoire data pour les raw et processes data (csv)
	@# Besoin de le créer car utilisé dans le dag pour monter le volume associé
	@# (donc avant le import_raw_data.py qui le crée si absent)
	@mkdir -p data

	@echo "🔥 Reconstruction totale de zéro..."
	@echo "⏳ Cela peut prendre plusieurs dizaines de secondes"
	@echo "Fichier de logs stocké dans logs/build.log (à partir de la racine)"
	@# --no-cache: ignorer le cache donc tout reconstruire
	@mkdir -p logs
	@docker compose build --no-cache > logs/build.log 2>&1

	@echo "Construction du Runner ML (version 1.0)..."
	@# image éphémère utilisée dans airflow/dags et impérativement absente du docker-compose
	@docker build --no-cache -t $(PROJECT_NAME)-runner:1.0 . > logs/build_runner.log 2>&1

	@echo "🔥 Reconstruction totale terminée."
	@echo "------------------------------------------------------------------------------------"
	@echo "🚀 IMAGES ACTUELLES DU PROJET :"
	@# docker images --filter "reference=accident-severity-*"
	@docker images | grep -E "$(PROJECT_NAME)|postgres"
	@echo "------------------------------------------------------------------------------------"
	@echo ""
	@echo "Vérification de la RAM utilisée"
	@free -h
	@echo ""
	@echo "Vérification du DISK utilisée"
	@df -h
	@echo ""
	@echo "Vérification des volumes après le build"
	@docker volume ls

docker-FullClean-build: ## [DEV] Reset TOTAL (Volumes/Images/Cache) ET NETTOYAGE DISK - Construction des images avec réinstallation systématique
	@echo "🛑 Arrêt et suppression des conteneurs existants..."
	@docker compose down --volumes --remove-orphans

	@echo "☢️ RESET TOTAL : Suppression de TOUS les conteneurs restants (actifs ou orphelins)..."
	@# C'est équvalent à dire: xarg=docker ps -aq;
	@# si xargs n'est pas vide (-r) alors faire docker rm -f xargs > /dev/null 2>&1
	@docker ps -aq | xargs -r docker rm -f > /dev/null 2>&1

	@echo "🧹 Nettoyage du disque en cours (attente de libération d'espace). Plusieurs secondes..."
	@# -af supprime toutes les images inactives (non en cours d'utilisation)
	@# donc logiquement toutes les images car juste avant on fait le down
	@docker system prune -af > /dev/null 2>&1
	@echo "✅ Espace disque optimisé."

	@echo "🗑️ Nettoyage des fichiers locaux..."
	@sudo rm -rf models/*
	@# On crée le répertoire si absent avec .gitkeep à l'intérieur
	@mkdir -p models
	@touch models/.gitkeep

	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) docker_prod_or_debug

	@echo "🔥 Reconstruction totale de zéro..."
	@echo "⏳ Cela peut prendre plusieurs dizaines de secondes"
	@echo "Fichier de logs stocké dans logs/build.log (à partir de la racine)"
	@# --no-cache: ignorer le cache donc tout reconstruire
	@mkdir -p logs
	@docker compose build --no-cache > logs/build.log 2>&1

	@echo "🔥 Reconstruction totale terminée."
	@echo "------------------------------------------------------------------------------------"
	@echo "🚀 IMAGES ACTUELLES DU PROJET :"
	@# docker images --filter "reference=accident-severity-*"
	@docker images | grep -E "$(PROJECT_NAME)|postgres"
	@echo "------------------------------------------------------------------------------------"


# Commande de vérification automatique incluant aiflow
docker_service_full_check-health: ## [PROD][DOCKER] Vérifier la disponibilité de TOUS les services via Nginx
	@# Lire le port dans le .env, si absent alors mode sécurisé port 443 par défaut
	@# $$() pour la différencier de la variable globale $(). L'intérieur est du bash/shell
	@# -f si le fichier existe, cut -d '=' coupe sur délimiter =, -f2 prend le 2ème champs (celui de droite)
	@# On remplace localhost par 127.0.0.1. Du point de vue logique cela ne change rien car c'est la même chose
	@# mais du point de vue comportement, en mettant localhost, curl va chercher dans /etc/hosts, tester en
	@# IPv6 puis IPv4 ce qui peut être source de conflit et perte de temps.
	@# En imposant 127.0.0.1, plus rapide et en IPv4 mais pour être sûr à 100%, curl -4 ... impose IPV4
	@# NB: /health est défini dans le .src/api/main.py
	@# AJOUT DU SERVICE AIRFLOW
	@NGINX_PORT_OUT=$$( [ -f .env ] && grep NGINX_PORT_OUT .env | cut -d '=' -f2 || echo "443" ); \
	echo "🔍 Vérification de la disponibilité des services via Nginx (Port: $$NGINX_PORT_OUT)..."; \
	if [ "$$NGINX_PORT_OUT" = "443" ]; then PROTO="https"; else PROTO="http"; fi; \
	for i in {1..10}; do \
		if curl -4 -s -k -f $$PROTO://127.0.0.1:$$NGINX_PORT_OUT/mlflow/ > /dev/null && \
			curl -4 -s -k -f $$PROTO://127.0.0.1:$$NGINX_PORT_OUT/api/health > /dev/null && \
			curl -4 -s -k -f $$PROTO://127.0.0.1:$$NGINX_PORT_OUT/airflow/health > /dev/null; then \
			echo "----------------------------------------------------------------------"; \
			echo "✅ SERVICES LANCÉS AVEC SUCCÈS SUR LE PORT $$NGINX_PORT_OUT ($$PROTO)"; \
			echo "----------------------------------------------------------------------"; \
			exit 0; \
		fi; \
		echo "⏳ En attente de Nginx ($$PROTO) (essai $$i/10)..."; \
		sleep 5; \
	done; \
	echo "❌ ERREUR : Les services ne répondent pas après 50 secondes."; \
	echo "❌ VÉRIFIER QUE LE PORT $$NGINX_PORT_OUT TESTÉ EST BIEN CELUI DÉFINI DANS LE SERVICE NGINX DU FICHIER DOCKER-COMPOSE.YML"; \
	docker compose ps; \
	exit 1


# Commande de vérification automatique
docker_service_check-health: ## [PROD][DOCKER] Vérifier la disponibilité des services via Nginx
	@# Lire le port dans le .env, si absent alors mode sécurisé port 443 par défaut
	@# $$() pour la différencier de la variable globale $(). L'intérieur est du bash/shell
	@# -f si le fichier existe, cut -d '=' coupe sur délimiter =, -f2 prend le 2ème champs (celui de droite)
	@# On remplace localhost par 127.0.0.1. Du point de vue logique cela ne change rien car c'est la même chose
	@# mais du point de vue comportement, en mettant localhost, curl va chercher dans /etc/hosts, tester en
	@# IPv6 puis IPv4 ce qui peut être source de conflit et perte de temps.
	@# En imposant 127.0.0.1, plus rapide et en IPv4 mais pour être sûr à 100%, curl -4 ... impose IPV4
	@# NB: /health est défini dans le .src/api/main.py
	@NGINX_PORT_OUT=$$( [ -f .env ] && grep NGINX_PORT_OUT .env | cut -d '=' -f2 || echo "443" ); \
	echo "🔍 Vérification de la disponibilité des services via Nginx (Port: $$NGINX_PORT_OUT)..."; \
	if [ "$$NGINX_PORT_OUT" = "443" ]; then PROTO="https"; else PROTO="http"; fi; \
	for i in {1..10}; do \
		if curl -4 -s -k -f $$PROTO://127.0.0.1:$$NGINX_PORT_OUT/mlflow/ > /dev/null && \
			curl -4 -s -k -f $$PROTO://127.0.0.1:$$NGINX_PORT_OUT/api/health > /dev/null; then \
			echo "----------------------------------------------------------------------"; \
			echo "✅ SERVICES LANCÉS AVEC SUCCÈS SUR LE PORT $$NGINX_PORT_OUT ($$PROTO)"; \
			echo "----------------------------------------------------------------------"; \
			exit 0; \
		fi; \
		echo "⏳ En attente de Nginx ($$PROTO) (essai $$i/10)..."; \
		sleep 5; \
	done; \
	echo "❌ ERREUR : Les services ne répondent pas après 50 secondes."; \
	echo "❌ VÉRIFIER QUE LE PORT $$NGINX_PORT_OUT TESTÉ EST BIEN CELUI DÉFINI DANS LE SERVICE NGINX DU FICHIER DOCKER-COMPOSE.YML"; \
	docker compose ps; \
	exit 1


docker_check_port_routage: ## [PROD][DOCKER] Vérifier que le port n'est pas indirectementque va utiliser Nginx est disponible
	@# On a vu que Kubernetes détourne systématiquement les ports 80 et 443. Donc Nginx n'est plus fonctionnel
	@# En mode HTTP, problème résolu en prenant utilisant le port 9999 (par ex). Mais pour HTTPS, on n'a pas le choix
	@# et donc impossible d'utiliser l'interface WEB sur le port sécurisé
	@# On cherche seulement 'dpt:80' ou 'dpt:443' . Le \b permet de capturer uniquement ces 2 cas
	@echo "🔍 Vérification si les ports 80 et 443 sont déjà utilisés dans des tables de routage (iptables NAT)..." ; \
	if sudo iptables -t nat -L -n | grep -E "dpt:(80|443)\b" > /dev/null; then \
		echo "⚠️ Conflit détecté sur 80 ou 443. Par défaut, on désactive KUBERNETES (K3s)..." ; \
		sudo systemctl stop k3s 2>/dev/null || true ; \
		sudo systemctl disable k3s 2>/dev/null || true ; \
		sudo iptables -t nat -F ; \
		echo "🔄 Tables vidées. Seconde vérification..." ; \
		if sudo iptables -t nat -L -n | grep -E "dpt:(80|443)\b" > /dev/null; then \
			echo "❌ ERREUR CRITIQUE : Les ports sont toujours utilisés par ces règles :" ; \
			echo "❌ ERREUR CRITIQUE SUITE: Et ce n'est pas uniquement dû à KUBERNETES" ; \
			sudo iptables -t nat -L -n -v | grep -E "dpt:(80|443)\b" ; \
			exit 1 ; \
		fi ; \
		echo "✅ Conflit résolu après nettoyage." ; \
		echo "🔄 Redémarrage de Docker pour reconstruire les règles NAT..." ; \
		sudo systemctl restart docker ; \
	else \
		echo "✅ Ports 80/443 libres de toute redirection." ; \
	fi


docker_check_port_free: ## [PROD][DOCKER] Vérifier que le port que va utiliser Nginx est disponible
	@# Lire le port dans le .env, si absent alors mode sécurisé port 443 par défaut
	@# sudo lsof -i :$$NGINX_PORT_OUT supprimé car il cherche tout ce qui contient la valeur de NGINX_PORT_OUT.
	@# Or lors du build, Docker questionne des entitées (ex: amazonaws) en les contactant sur leur port 443 DISTANT
	@# (en HTTPS) à partir d'un port local QUI N'EST PAS LE 443, pendant un brève instant.
	@# Comme "lsof -i" cherche 443, il le trouve et c'est un faux positif car le port local 443 est bien libre.
	@# pour sudo ss -lnt: -l: uniquement les ports en écoute (LISTEN); -n : numérique (évite la
	@# résolution de noms, plus rapide); -t : uniquement le protocole TCP
	@# grep -q (quiet): n'affiche rien (en mode silencieux)  - supprime la sortie standard (stdout)

	@NGINX_PORT_OUT=$$( [ -f .env ] && grep NGINX_PORT_OUT .env | cut -d '=' -f2 || echo "443" ); \
	echo "🔍 Vérification que le port $$NGINX_PORT_OUT est libre..."; \
	if sudo ss -lnt | grep -q ":$$NGINX_PORT_OUT\b" ; then \
		echo "❌ ERREUR : Le port $$NGINX_PORT_OUT est déjà utilisé !"; \
		echo "👉 Commande pour voir qui l'utilise : 'sudo lsof -Pi :$$NGINX_PORT_OUT -sTCP:LISTEN'"; \
		echo "👉 Commande pour le tuer : 'sudo fuser -k $$NGINX_PORT_OUT/tcp'"; \
		exit 1; \
	fi; \
	echo "✅ Port $$NGINX_PORT_OUT libre."
	@echo ""


docker_ssl_prep: ## [PROD] Génère les certificats auto-signés SSL si inexistants
	@# nginx.key (clé privé): confidentiel, reste sur le serveur
	@# nginx.crt (certificat public): nginx l'envoie au navigateur utilisateur
	@#  CN=localhost pour les tests locaux. En prod, on utilise un nom de domaine.
	@echo "🔐 Préparation des certificats SSL..."
	@mkdir -p $(CERT_DIR)
	@if [ ! -f $(CERT_DIR)/nginx.key ]; then \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout $(CERT_DIR)/nginx.key \
		-out $(CERT_DIR)/nginx.crt \
		-subj "/CN=localhost"; \
		echo "✅ Certificats générés avec succès."; \
	else \
		echo "ℹ️ Certificats déjà présents, passage à l'étape suivante."; \
	fi


docker-data-prep: ## [PROD][DOCKER] Import/Process via DVC (si nécessaire)
	@# Cette commande lance automatiquement le dvc.yaml
	@# Equivalent à la partie import/process de la cible 'pipeline'
	@# On utilise tout l'env du service train de docker-compose.yml
	@# et on applique la commande uv run dvc repro import process
	@echo "🚀 Lancement de l'import/process avec accès aux métadonnées DVC..."
	@echo " On monte des volumes temporaires pour exéctuer le DVC"
	@docker compose run --rm \
		-v $(PWD)/.dvc:/app/.dvc \
		-v $(PWD)/dvc.yaml:/app/dvc.yaml \
		-v $(PWD)/dvc.lock:/app/dvc.lock \
                -v $(PWD)/params.yaml:/app/params.yaml \
		-w /app \
		train uv run dvc repro import process

# Lancer tout l'écosystème conteneurisé (Postgres + MLflow + Airflow + API)
# L'option -d (--detach) pour le faire tourner en tâche de fond (daemon mode)
docker-full-start-WoInitialTrain: ## [PROD][DOCKER] Démarrage des services Postgres, Mlflow, Airflow et API sans Initial Train
	@# Sécurité et Infrastructure
	@sudo chmod a+rw /var/run/docker.sock
	@# Verifier que ce port n'est pas utilisé dans les tables de routage
	@$(MAKE) -s docker_check_port_routage
	@# Vérifier que ce port n'est pas déjà ouvert
	@$(MAKE) -s docker_check_port_free
	@$(MAKE) -s docker_ssl_prep

	@# Au cas où l'install n'a pas été exécuté
	@mkdir -p reports
	@mkdir -p logs
	@# On crée le fichier s'il n'existe pas
	@touch dvc.lock
	@# Si le fichier est vide (taille 0), on injecte le template minimal
	@if [ ! -s dvc.lock ]; then \
		echo "schema: '2.0'" > dvc.lock; \
		echo "stages: {}" >> dvc.lock; \
		echo "✅ dvc.lock était vide, initialisé avec le schéma 2.0"; \
	else \
		echo "ℹ️ dvc.lock contient déjà des données, on ne touche à rien"; \
	fi

	@echo "🚀 Déploiement des services (Postgres + API + MLflow + Airflow) en tâche de fond (mode détaché)"

	@# Injection de l'année dans params.yaml. Utilisé dans dvc.yaml pour stage import
	@# Ensuite, le dag airflow met à jour l'année via la variable settée dans le webserver Airflow
	@echo "TRAIN_YEAR: 2019" > params.yaml
	@echo "✅ params.yaml initialisé avec TRAIN_YEAR: 2019 ==================="

	@docker compose up -d postgres
	@#echo "⏳ Attente du service Postgres...10s pour être sûr qu'il a démarré"
	@#sleep 10
	@echo "⏳ Attente de démarrage du service Postgres..."
	@echo "Toutes les 1s, on teste le healthcheck du service postgres dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^postgres " | grep -q "healthy"; do \
		printf '.'; \
		sleep 1; \
	done
	@echo "✅ POSTGRES opérationnel."

	@# On crée la database Mlflow dans le postgres avec les mêmes usr/pwd que Airflow
	@# -U:user; -d: database; -c: command;
	@# -d postgres: on se connecte à la database postgres et -c "..." pour créer la 'sous-database' mlflow
	@# OWNER airflow pour garantir que l'utilisateur airflow a bien les droits sur la database mlflow
	@echo "--- Création sur postgres de la database mlflow ---"
	@docker compose exec postgres psql \
		-U airflow \
		-d postgres \
		-c "CREATE DATABASE mlflow OWNER airflow;" \
		|| echo "⚠️ La base mlflow existe déjà, passage à la suite..."

	@# Dans le docker-compose.yml, service mlflow, dans environnement on ajoute
	@# - DATABASE_URL=postgresql://airflow:airflow@postgres:5432/mlflow
	@docker compose up -d mlflow
	@#echo "⏳ Attente du service MLflow...5s pour être sûr qu'il a démarré"
	@#sleep 5
	@echo "⏳ Attente de démarrage du service Mlflow..."
	@echo "Toutes les 1s, on teste le healthcheck du service mlflow dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^mlflow " | grep -q "healthy"; do \
		printf '.'; \
		sleep 1; \
	done
	@echo "✅ MLFLOW opérationnel."

	@# Inutile pour ubuntu avec 16GO de RAM (voir le code dans les versions précédentes
	@#echo "🔍 Vérification de la mémoire vive AVANT UTILISATION AIRFLOW GOURMAND EN RAM..."
	@#echo "SINON ON OBSERVE DES LENTEURS EXTREMES SUR UBUNTU"
	@# Ajout dans fstab seulement s'il n'y est pas déjà. Pourquoi?
	@# Si on ne réinitialise pas le Ubuntu (donc redémarrer seulement) et que les services étaient up
	@# avant d'arrêter ubuntu, alors le swap n'est pas remonté et comme les services ont l'option restart,
	@# les services sont redémarrés et les anciens services intactifs sont toujours dans la RAM et donc engorgement

	@echo "🌬️ Lancement du service Airflow-init qui s'arrête une fois l'initialisation faite..."
	@# airflow-init prépare la DB d'Airflow
	@echo "[!] Initialisation de la DB. Attente qu'elle finisse avant de passer aux autres services airflow..."
	@echo "⏳ Peut prendre plusieurs dizaines de secondes"
	@# docker compose up airflow-init ==> on le lance comme un service alors que ce n'est qu'une tâche ponctuelle
	@# On utilise run pour LANCER CETTE TACHE (création d'un conteneur dédié) ET ON NE PASSE PAS A LA SUITE AVANT LA FIN DE CETTE TACHE
	@# --rm: une fois l'initialisation effectuée, on supprime le conteneur car la tache est terminé
	@docker compose run --rm airflow-init
	@echo "✅ Airflow Initialisation terminée. On passe à la suite"

	@echo "[!] La DB est prête, lancement des autres services airflow et api..."
	@# Maintenant que la DB est prête, on lance les services airflow
	@# Démarrées tous les services en même temps est incohérent car le worker ne peut démarrer
	@# que si le scheduler a démarré et qui ne peut démarrer que si le api-server a démarré
	@echo "Démarrage du service airflow-webserver..."
	@echo "⏳ Cela peut prendre plusieurs dizaines de secondes"
	@docker compose up -d airflow-webserver
	@# Le healthcheck du service airflow-webserver de docker-compose.yml est testé régulièrement
	@# pour savoir quand il est démarré et passer à la suite seulement une fois démarré
	@# NB: le ping via le curl ne fonctinne pas car Nginx n'est pas démarré.
	@# Volontairemnt, dans docker-compose.yml, aucun port exposé pour ne pas courcicuiter nginx
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-webserver dans le fichier docker-compose.yml "
	@echo "Cela prend autour de 2 minutes ..."
	@# "^airflow-webserver " : avec l'espace pour être sûr qu'il ne va pas prendre un service airflow-webserver-xxx qui pourrait exister aussi
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-webserver " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "✅ AIRFLOW WEBSERVER opérationnel."
	@echo "Démarrage du service airflow-scheduler..."
	@docker compose up -d airflow-scheduler
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-scheduler dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-scheduler " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "✅ AIRFLOW SCHEDULER opérationnel."
	@echo "Démarrage du service airflow-worker..."
	@docker compose up -d airflow-worker
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-worker dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-worker " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "✅ AIRFLOW WORKER opérationnel."

	@echo "Démarrage du service airflow-worker..."
	@docker compose up -d airflow-flower
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-flower dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-flower " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "✅ AIRFLOW FLOWER opérationnel."

	@echo ""
	@echo "======================================================================"
	@echo "TRAIN_YEAR créé et initialisé à 2019 dans Admin/Variable du Webserver"
	@# Dans le service airflow-worker, on utilise l'outil airflow (CLI) et on
	@# lance la commabde variables set pour créer TRAIN_YEAR et l'initialisé à 2019
	@docker compose run --rm airflow-worker airflow variables set TRAIN_YEAR 2019
	@echo "======================================================================"

	@echo "Démarrage du service prometheus..."
	@docker compose up -d prometheus
	@echo "⏳ Attente de démarrage du service Prometheus..."
	@echo "Toutes les 5s, on teste le healthcheck du service prometheus dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^prometheus " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "✅ PROMETHEUS opérationnel."

	@echo "Démarrage du service grafana..."
	@docker compose up -d grafana
	@echo "⏳ Attente de démarrage du service Grafana..."
	@echo "Toutes les 5s, on teste le healthcheck du service grafana dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^grafana " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "✅ GRAFANA opérationnel."

	@# Lancement du service nginx
	@docker compose up -d nginx

	@echo "⏳ Validation de l'accès extérieur via Nginx vers les services..."
	@$(MAKE) -s docker_service_full_check-health
	@echo "✅ NGINX et tous les ports opérationnel."
	@$(MAKE) -s docker-status
	@echo ""
	@# Lire le port dans le .env
	@# On vérifie d'abord si le fichier existe avec [ -f .env ]
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs) && \
		if [ "$$NGINX_PORT_OUT" = "443" ]; then \
			echo "------------------------------------------------------------------------------------"; \
			echo "💡 POUR MACHINE DISTANTE - MODE SECURISE (HTTPS) - SERVICES ACCESSIBLES (VIA NGINX):"; \
			echo "👉 API Principale          : https://<IP_VM>/api/"; \
			echo "👉 SWAGGER (Doc)           : https://<IP_VM>/api/docs"; \
			echo "👉 MLflow UI               : https://<IP_VM>/mlflow/"; \
			echo "👉 Airflow (Orchestrateur) : https://<IP_VM>/airflow/"; \
			echo "👉 Airflow (Orchestrateur) : https://<IP_VM>/flower/"; \
			echo "👉 Prometheus              : https://<IP_VM>/prometheus/"; \
			echo "👉 Grafana                 : https://<IP_VM>/grafana/"; \
			echo "------------------------------------------------------------------------------------"; \
		else \
			echo "------------------------------------------------------------------------------------"; \
			echo "💡 POUR MACHINE DISTANTE - MODE NON SECURISE - SERVICES ACCESSIBLES (VIA NGINX):"; \
			echo "👉 API Principale          : http://<IP_VM>/api/"; \
			echo "👉 SWAGGER (Doc)           : http://<IP_VM>/api/docs"; \
			echo "👉 MLflow UI               : http://<IP_VM>/mlflow/"; \
			echo "👉 Airflow (Orchestrateur) : http://<IP_VM>/airflow/"; \
			echo "👉 Airflow (Orchestrateur) : http://<IP_VM>/flower/"; \
			echo "👉 Prometheus              : http://<IP_VM>/prometheus/"; \
			echo "👉 Grafana                 : http://<IP_VM>/grafana/"; \
			echo "------------------------------------------------------------------------------------"; \
		fi \
	else \
		echo "⚠️ Attention : Aucun fichier .env trouvé. FAIRE D'ABORD LA CREATION D'IMAGE."; \
	fi

	@echo ""
	@echo "Vérification des volumes après le full restart"
	@docker volume ls

# Lancer tout l'écosystème conteneurisé (Postgres + MLflow + Airflow + API)
# L'option -d (--detach) pour le faire tourner en tâche de fond (daemon mode)
docker-full-start-WoInitialTrain_fast: ## [PROD][DOCKER] Démarrage simultannés des services Postgres et Redis, puis Airflow-Init et enfin tous les autres sans Initial Train
	@# Sécurité et Infrastructure
	@sudo chmod a+rw /var/run/docker.sock
	@# Verifier que ce port n'est pas utilisé dans les tables de routage
	@$(MAKE) -s docker_check_port_routage
	@# Vérifier que ce port n'est pas déjà ouvert
	@$(MAKE) -s docker_check_port_free
	@$(MAKE) -s docker_ssl_prep

	@echo ""
	@echo "======================================================================"
	@echo "💡 GARANTIR DE REJOUER UNE SIMULATION COMPLèTE DU CALCUL DES MODèLES"
	@$(MAKE) -s docker-reset-for-full-simu
	@echo "======================================================================"
	@echo ""

	@# Au cas où l'install n'a pas été exécuté
	@mkdir -p reports
	@mkdir -p logs
	@mkdir -p data
	@# On crée le fichier s'il n'existe pas
	@touch dvc.lock
	@# Si le fichier est vide (taille 0), on injecte le template minimal
	@if [ ! -s dvc.lock ]; then \
		echo "schema: '2.0'" > dvc.lock; \
		echo "stages: {}" >> dvc.lock; \
		echo "✅ dvc.lock était vide, initialisé avec le schéma 2.0"; \
	else \
		echo "ℹ️ dvc.lock contient déjà des données, on ne touche à rien"; \
	fi

	@echo ""
	@echo "🚀 Déploiement des services"

	@# Injection de l'année dans params.yaml. Utilisé dans dvc.yaml pour stage import
	@# Ensuite, le dag airflow met à jour l'année via la variable settée dans le webserver Airflow
	@echo "TRAIN_YEAR: 2019" > params.yaml
	@echo "✅ params.yaml initialisé avec TRAIN_YEAR: 2019 ==================="

	@#echo ""
	@#echo "🚀 LANCER IMPERATIVEMENT fix-volumes-permissions EN PREMIER"
	@#echo "IL N'EST PAS LANCé EN MODE DETACH CAR ON ATTEND QU'IL S'EXECUTE AVANT DE PASSER A LA SUITE"
	@#docker compose up fix-volumes-permissions
	@#echo "✅ Service fix-volumes-permissions terminé avec succès !"

	@# On lance en premier les services SANS dépendances
	@#docker compose up -d postgres redis prometheus
	@#echo "⏳ Attente de démarrage des services Postgres et Redis..."
	@#echo "Toutes les 1s, on teste le healthcheck de postgres et redis..."
	@# Compte dynamique (wc -l : pour compter le nb de lignes)
	@docker compose up -d $(INDEPENDANT_SERVICES)
	@echo "⏳ Attente de démarrage des services indépendant [ $(INDEPENDANT_SERVICES) ]..."
	@echo "Toutes les 2s, on teste leur healthcheck..."
	@# La boucle utilise la regex et le compte dynamique (wc -l : pour compter le nb de lignes)
	@until \
		COUNT=$$( \
			docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | \
			grep -E "^($(INDEPENDANT_SERVICES_REGEX)) " | \
			grep "healthy" | \
			wc -l \
		); \
		[ $$COUNT -eq $(INDEPENDANT_SERVICES_NUM) ]; do \
			printf '.'; \
			sleep 2; \
	done
	@echo -e "\n✅ Services [ $(INDEPENDANT_SERVICES) ] opérationnels."

	@# On crée la database Mlflow dans le postgres avec les mêmes usr/pwd que Airflow
	@# -U:user; -d: database; -c: command;
	@# -d postgres: on se connecte à la database postgres et -c "..." pour créer la 'sous-database' mlflow
	@# OWNER airflow pour garantir que l'utilisateur airflow a bien les droits sur la database mlflow
	@echo "--- Création sur postgres de la database mlflow ---"
	@docker compose exec postgres psql \
		-U airflow \
		-d postgres \
		-c "CREATE DATABASE mlflow OWNER airflow;" \
		|| echo "⚠️ La base mlflow existe déjà, passage à la suite..."

	@echo "🌬️ Lancement du moteur Airflow..."
	@# airflow-init prépare la DB d'Airflow
	@echo "[!] Initialisation de la DB. Attente qu'elle finisse avant de passer aux autres services airflow..."
	@# docker compose up airflow-init ==> on le lance comme un service alors que ce n'est qu'une tâche ponctuelle
	@# On utilise run pour LANCER CETTE TACHE (création d'un conteneur dédié) ET ON NE PASSE PAS A LA SUITE AVANT LA FIN DE CETTE TACHE
	@# --rm: une fois l'initialisation effectuée, on supprime le conteneur car la tache est terminé
	@echo "⏳ Initialisation de la base de données Airflow (migration)..."
	@echo "⏳ Prend plusieurs dizaines de secondes"
	@echo "Le contenu de l'affichage est envoyé dans logs/airflow-init.log (à la racine)"
	@docker compose run --rm airflow-init > logs/airflow-init.log 2>&1
	@echo "✅ Airflow-init terminé avec succès !"
	@echo "[!] La DB est prête, lancement des autres services airflow et api..."
	@# Maintenant que la DB est prête, on peut lancer les services

	@# Dans le docker-compose.yml, service mlflow, dans environnement on ajoute
	@# - DATABASE_URL=postgresql://airflow:airflow@postgres:5432/mlflow

	@# On lance tous les services en même temps.
	@# docker-compose.yml est configuré pour les lancer dans le bon ordre

	@docker compose up -d $(DEPENDANT_SERVICES)
	@echo "⏳ Attente de démarrage des web services [ $(DEPENDANT_SERVICES) ]..."
	@echo "Toutes les 5s, on teste leur healthcheck..."
	@# La boucle utilise la regex et le compte dynamique (wc -l : pour compter le nb de lignes)
	@until \
		COUNT=$$( \
			docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | \
			grep -E "^($(DEPENDANT_SERVICES_REGEX)) " | \
			grep "healthy" | \
			wc -l \
		); \
		[ $$COUNT -eq $(DEPENDANT_SERVICES_NUM) ]; do \
			printf '.'; \
			sleep 5; \
	done
	@echo -e "\n✅ Services [ $(DEPENDANT_SERVICES) ] opérationnels."

	@echo ""
	@echo "======================================================================"
	@echo "TRAIN_YEAR créé et initialisé à 2019 dans Admin/Variable du Webserver"
	@# Dans le service airflow-worker, on utilise l'outil airflow (CLI) et on
	@# lance la commabde variables set pour créer TRAIN_YEAR et l'initialisé à 2019
	@docker compose run --rm airflow-worker airflow variables set TRAIN_YEAR 2019
	@echo "======================================================================"

	@# Lancement du service nginx
	@docker compose up -d nginx

	@echo "⏳ Validation de l'accès extérieur via Nginx vers les services..."
	@$(MAKE) -s docker_service_full_check-health
	@echo "✅ NGINX et tous les ports opérationnel."
	@$(MAKE) -s docker-status
	@echo ""
	@# Lire le port dans le .env
	@# On vérifie d'abord si le fichier existe avec [ -f .env ]
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs) && \
		if [ "$$NGINX_PORT_OUT" = "443" ]; then \
			echo "------------------------------------------------------------------------------------"; \
			echo "💡 POUR MACHINE DISTANTE - MODE SECURISE (HTTPS) - SERVICES ACCESSIBLES (VIA NGINX):"; \
			echo "👉 API Principale          : https://<IP_VM>/api/"; \
			echo "👉 SWAGGER (Doc)           : https://<IP_VM>/api/docs"; \
			echo "👉 MLflow UI               : https://<IP_VM>/mlflow/"; \
			echo "👉 Airflow (Orchestrateur) : https://<IP_VM>/airflow/"; \
			echo "👉 Airflow (Orchestrateur) : https://<IP_VM>/flower/"; \
			echo "👉 Prometheus              : https://<IP_VM>/prometheus/"; \
			echo "👉 Grafana                 : https://<IP_VM>/grafana/"; \
			echo "------------------------------------------------------------------------------------"; \
		else \
			echo "------------------------------------------------------------------------------------"; \
			echo "💡 POUR MACHINE DISTANTE - MODE NON SECURISE - SERVICES ACCESSIBLES (VIA NGINX):"; \
			echo "👉 API Principale          : http://<IP_VM>/api/"; \
			echo "👉 SWAGGER (Doc)           : http://<IP_VM>/api/docs"; \
			echo "👉 MLflow UI               : http://<IP_VM>/mlflow/"; \
			echo "👉 Airflow (Orchestrateur) : http://<IP_VM>/airflow/"; \
			echo "👉 Airflow (Orchestrateur) : http://<IP_VM>/flower/"; \
			echo "👉 Prometheus              : http://<IP_VM>/prometheus/"; \
			echo "👉 Grafana                 : http://<IP_VM>/grafana/"; \
			echo "------------------------------------------------------------------------------------"; \
		fi \
	else \
		echo "⚠️ Attention : Aucun fichier .env trouvé. FAIRE D'ABORD LA CREATION D'IMAGE."; \
	fi

	@echo ""
	@echo "Vérification des volumes après le full restart"
	@docker volume ls

# Lancer tout l'écosystème conteneurisé (Postgres + MLflow + Airflow + API)
# L'option -d (--detach) pour le faire tourner en tâche de fond (daemon mode)
docker-full-start: ## [PROD][DOCKER] Démarrage des services Postgres, Mlflow, Airflow et API
	@# Sécurité et Infrastructure
	@sudo chmod a+rw /var/run/docker.sock
	@# Verifier que ce port n'est pas utilisé dans les tables de routage
	@$(MAKE) docker_check_port_routage
	@# Vérifier que ce port n'est pas déjà ouvert
	@$(MAKE) docker_check_port_free
	@$(MAKE) docker_ssl_prep

	@echo "🚀 Déploiement des services (Postgres + API + MLflow + Airflow) en tâche de fond (mode détaché)"

	@# Injection de l'année dans params.yaml. Utilisé dans dvc.yaml pour stage import
	@# Ensuite, le dag airflow met à jour l'année via la variable settée dans le webserver Airflow
	@echo "TRAIN_YEAR: 2019" > params.yaml
	@echo "✅ params.yaml initialisé avec TRAIN_YEAR: 2019 ==================="

	@docker compose up -d postgres
	@echo "⏳ Attente du service Postgres...10s pour être sûr qu'il a démarré"
	@sleep 10

	@# On crée la database Mlflow dans le postgres avec les mêmes usr/pwd que Airflow
	@# -U:user; -d: database; -c: command;
	@# -d postgres: on se connecte à la database postgres et -c "..." pour créer la 'sous-database' mlflow
	@# OWNER airflow pour garantir que l'utilisateur airflow a bien les droits sur la database mlflow
	@echo "--- Création sur postgres de la database mlflow ---"
	@docker compose exec postgres psql \
		-U airflow \
		-d postgres \
		-c "CREATE DATABASE mlflow OWNER airflow;" \
		|| echo "⚠️ La base mlflow existe déjà, passage à la suite..."

	@# Dans le docker-compose.yml, service mlflow, dans environnement on ajoute
	@# - DATABASE_URL=postgresql://airflow:airflow@postgres:5432/mlflow
	@docker compose up -d mlflow
	@echo "⏳ Attente du service MLflow...5s pour être sûr qu'il a démarré"
	@sleep 5

	@echo "🔍 Vérification de la mémoire vive AVANT UTILISATION AIRFLOW GOURMAND EN RAM..."
	@echo "SINON ON OBSERVE DES LENTEURS EXTREMES SUR UBUNTU"
	@# L'option --discard de swapon pour dire au noyau Linux de libérer immédiatement le disque physique
	@# de tous les blocs de données dans le swap inutilisés
	@if [ -f /swapfile ] && swapon --show | grep -q "/swapfile"; then \
		echo "✅ Swap de 4Go déjà configuré et actif. Rien à faire."; \
	else \
		echo "🛠️ Configuration du Swap de 4Go..."; \
		sudo fallocate -l 4G /swapfile || true; \
		sudo chmod 600 /swapfile; \
		sudo mkswap /swapfile; \
                sudo swapon --discard /swapfile; \
		echo "🚀 Swap activé avec succès."; \
	fi

	@# Ajout dans fstab seulement s'il n'y est pas déjà. Pourquoi?
	@# Si on ne réinitialise pas le Ubuntu (donc redémarrer seulement) et que les services étaient up
	@# avant d'arrêter ubuntu, alors le swap n'est pas remonté et comme les services ont l'option restart,
	@# les services sont redémarrés et les anciens services intactifs sont toujours dans la RAM et donc engorgement
	@# Cette commande permet de remonter le swap au redémarrage
	@if ! grep -q "/swapfile" /etc/fstab; then \
		echo "/swapfile none swap sw,discard 0 0" | sudo tee -a /etc/fstab; \
		echo "✅ Ajouté à /etc/fstab pour le prochain redémarrage."; \
	else \
		echo "✅ Déjà présent dans /etc/fstab."; \
	fi

	@free -h

	@echo "Preparation des datas: import et process si absent"
	@$(MAKE) docker-data-prep
	@# Lancement du job train qui va créer la première expérience et Accident_Severity_Classifier
	@echo "⏳ L'entrainement prend plusieurs dizaines de secondes..."
	@# On utilise "run --rm" au lieu de "up" pour 4 raisons :
	@# 1. Job / Tâche: train est un job/tâche (qui exécute le train_model.py) et non pas un service
	@# 2. Isolation : Chaque run crée un conteneur neuf (évite les effets de bord de l'ancien contexte).
	@# 3. Parallélisme : Permet de lancer plusieurs entraînements simultanés sans conflit de nom.
	@# 4. Cycle de vie : run pour passer à la suite seuelement après la tâche terminée.
	@#                   --rm nettoie/supprime le conteneur après usage.
	@#docker compose up train
	@docker compose run --rm train
	@docker compose up -d api
	@echo "⏳ Attente du service API...2s pour être sûr qu'il a démarré"
	@sleep 2


	@echo "🌬️ Lancement du moteur Airflow..."
	@# airflow-init prépare la DB d'Airflow
	@echo "[!] Initialisation de la DB. Attente qu'elle finisse avant de passer aux autres services airflow..."
	@echo "⏳ Peut prendre plusieurs dizaines de secondes"
	@# docker compose up airflow-init ==> on le lance comme un service alors que ce n'est qu'une tâche ponctuelle
	@# On utilise run pour LANCER CETTE TACHE (création d'un conteneur dédié) ET ON NE PASSE PAS A LA SUITE AVANT LA FIN DE CETTE TACHE
	@# --rm: une fois l'initialisation effectuée, on supprime le conteneur car la tache est terminé
	@docker compose run --rm airflow-init
	@echo "✅ Airflow Initialisation terminée. On passe à la suite"

	@echo "[!] La DB est prête, lancement des autres services airflow et api..."
	@# Maintenant que la DB est prête, on lance les services airflow
	@# Démarrées tous les services en même temps est incohérent car le worker ne peut démarrer
	@# que si le scheduler a démarré et qui ne peut démarrer que si le api-server a démarré
	@#docker compose up -d airflow-webserver airflow-scheduler airflow-worker
	@echo "Démarrage du service airflow-webserver..."
	@echo "⏳ Cela peut prendre plusieurs dizaines de secondes"
	@docker compose up -d airflow-webserver
	@# Le healthcheck du service airflow-webserver de docker-compose.yml est testé régulièrement
	@# pour savoir quand il est démarré et passer à la suite seulement une fois démarré
	@# NB: le ping via le curl ne fonctinne pas car Nginx n'est pas démarré.
	@# Volontairemnt, dans docker-compose.yml, aucun port exposé pour ne pas courcicuiter nginx
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-webserver dans le fichier docker-compose.yml "
	@echo "Cela prend autour de 2 minutes ..."
	@# "^airflow-webserver " : avec l'espace pour être sûr qu'il ne va pas prendre un service airflow-webserver-xxx qui pourrait exister aussi
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-webserver " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "\n✅ AIRFLOW WEBSERVER opérationnel."
	@echo "Démarrage du service airflow-scheduler. On attend 5s avant de passer à la suite..."
	@docker compose up -d airflow-scheduler
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-scheduler dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-scheduler " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "\n✅ AIRFLOW SCHEDULER opérationnel."
	@echo "Démarrage du service airflow-worker. On attend 5s avant de passer à la suite..."
	@docker compose up -d airflow-worker
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-worker dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-worker " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "\n✅ AIRFLOW WORKER opérationnel."

	@echo "Démarrage du service airflow-worker. On attend 5s avant de passer à la suite..."
	@docker compose up -d airflow-flower
	@echo "Toutes les 5s, on teste le healthcheck du service airflow-flower dans le fichier docker-compose.yml"
	@until docker ps --format '{{.Label "com.docker.compose.service"}} {{.Status}}' | grep "^airflow-flower " | grep -q "healthy"; do \
		printf '.'; \
		sleep 5; \
	done
	@echo "\n✅ AIRFLOW FLOWER opérationnel."

	@echo ""
	@echo "======================================================================"
	@echo "TRAIN_YEAR créé et initialisé à 2019 dans Admin/Variable du Webserver"
	@# Dans le service airflow-worker, on utilise l'outil airflow (CLI) et on
	@# lance la commabde variables set pour créer TRAIN_YEAR et l'initialisé à 2019
	@docker compose run --rm airflow-worker airflow variables set TRAIN_YEAR 2019
	@echo "======================================================================"

	@# Lancement du service nginx
	@docker compose up -d nginx

	@echo "⏳ Validation de l'accès extérieur via Nginx vers les services..."
	@$(MAKE) docker_service_full_check-health
	@echo "\n✅ NGINX et tous les ports opérationnel."
	@$(MAKE) docker-status
	@echo ""
	@# Lire le port dans le .env, si absent alors mode sécurisé port 443 par défaut
	@if [ "$$NGINX_PORT_OUT" = "443" ]; then \
		echo "------------------------------------------------------------------------------------"; \
		echo "💡 POUR MACHINE DISTANTE - MODE SECURISE (HTTPS) - SERVICES ACCESSIBLES (VIA NGINX):"; \
		echo "👉 Airflow (Orchestrateur) : https://<IP_VM>/airflow/"; \
		echo "👉 API Principale          : https://<IP_VM>/api/"; \
		echo "👉 SWAGGER (Doc)           : https://<IP_VM>/api/docs"; \
		echo "👉 MLflow UI               : https://<IP_VM>/mlflow/"; \
		echo "------------------------------------------------------------------------------------"; \
	else \
		echo "------------------------------------------------------------------------------------"; \
		echo "💡 POUR MACHINE DISTANTE - MODE NON SECURISE - SERVICES ACCESSIBLES (VIA NGINX):"; \
		echo "👉 Airflow (Orchestrateur) : http://<IP_VM>/airflow/"; \
		echo "👉 Airflow (Orchestrateur) : http://<IP_VM>/flower/"; \
		echo "👉 API Principale          : http://<IP_VM>/api/"; \
		echo "👉 SWAGGER (Doc)           : http://<IP_VM>/api/docs"; \
		echo "👉 MLflow UI               : http://<IP_VM>/mlflow/"; \
		echo "------------------------------------------------------------------------------------"; \
	fi


# Lancer tout l'écosystème conteneurisé (Postgres + MLflow + + API)
# L'option -d (--detach) pour le faire tourner en tâche de fond (daemon mode)
docker-start: ## [PROD][DOCKER] Démarrage des service Postgres + API + Mlflow
	@# Verifier que ce port n'est pas utilisé dans les tables de routage
	@$(MAKE) docker_check_port_routage
	@# Vérifier que ce port n'est pas déjà ouvert
	@$(MAKE) docker_check_port_free
	@$(MAKE) docker_ssl_prep
	@echo "🚀 Déploiement des services (API + MLflow) en tâche de fond (mode détaché)"
	@docker compose up -d mlflow
	@echo "⏳ Attente du service MLflow...5s pour être sûr qu'il a démarré"
	@sleep 5
	@echo "Preparation des datas: import et process si absent"
	@$(MAKE) docker-data-prep
	@# Lancement du job train qui va créer la première expérience et Accident_Severity_Classifier
	@echo "⏳ L'entrainement prend plusieurs dizaines de secondes..."
	@docker compose up train
	@docker compose up -d api
	@echo "⏳ Attente du service API...2s pour être sûr qu'il a démarré"
	@sleep 2
	@# Lancement du service nginx
	@docker compose up -d nginx
	@echo "⏳ Validation de l'accès extérieur via Nginx vers les services..."
	@$(MAKE) docker_service_check-health
	@echo ""
	@# Lire le port dans le .env, si absent alors mode sécurisé port 443 par défaut
	@NGINX_PORT_OUT=$$( [ -f .env ] && grep NGINX_PORT_OUT .env | cut -d '=' -f2 || echo "443" ); \
	if [ "$$NGINX_PORT_OUT" = "443" ]; then \
		echo "------------------------------------------------------------------------------------"; \
		echo "💡 POUR MACHINE DISTANTE - MODE SECURISE (HTTPS) - SERVICES ACCESSIBLES (VIA NGINX):"; \
		echo "👉 API Principale  : https://<IP_VM>/api/"; \
		echo "👉 SWAGGER (Doc)   : https://<IP_VM>/api/docs"; \
		echo "👉 MLflow UI       : https://<IP_VM>/mlflow/"; \
		echo "------------------------------------------------------------------------------------"; \
	else \
		echo "------------------------------------------------------------------------------------"; \
		echo "💡 POUR MACHINE DISTANTE - MODE NON SECURISE - SERVICES ACCESSIBLES (VIA NGINX):"; \
		echo "👉 API Principale  : http://<IP_VM>/api/"; \
		echo "👉 SWAGGER (Doc)   : http://<IP_VM>/api/docs"; \
		echo "👉 MLflow UI       : http://<IP_VM>/mlflow/"; \
		echo "------------------------------------------------------------------------------------"; \
	fi

docker-train: ## [PROD][DOCKER] Réentrainement du modèle
	@# Lancement du job train pour réentrainer le modèle
	@echo "---- Réentrainement du modèle ----"
	@echo "⏳ Peut prendre plusieurs dizaines de secondes..."
	@docker compose up train

docker-api: ## [PROD][DOCKER] Redémarrer le service api
	@echo "---- Redémarrage du service API ----"
	@docker compose restart api

docker-stop: ## [PROD][DOCKER] Arrêt des conteneurs (prêts à redémarrer)
	@echo "⏸️  Arrêt des services Docker (Stop)..."
	@docker compose stop
	@echo "✅ Services arrêtés (prêts à redémarrer)."

docker-down: ## [PROD][DOCKER] Arrêt ET suppression complète (Nettoie réseaux, conteneurs ET volumes)
	@echo "🛑 Suppression de toute l'infrastructure Docker (Down) ainsi que les volumes..."
	@docker compose down --volumes --remove-orphans
	@echo "✨ Tout a été nettoyé proprement."
	@echo "Vérification de la RAM utilisée"
	@free -h
	@echo "Vérification du DISK utilisée"
	@df -h

docker-up: ## [PROD][DOCKER] Lancement des conteneurs en mode détaché
	@echo "🚀 Lancement des services Docker (Up)..."
	@docker compose up -d
	@echo "✅ Services démarrés et tournant en arrière-plan."
	@echo "🔗 Liste des conteneurs actifs :"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

docker-status: ## [PROD][DOCKER] Affiche l'état des services et les ports actifs
	@echo "📊 État des conteneurs Docker..."
	@docker compose ps
	@echo "----------------------------------------------------------------"
	@echo "💡 'Up' : le service fonctionne normalement."

ubuntu_usage: ## [PROD][DOCKER] UBUNTU : VERIF RAM, DISK, CPU
	@echo "--- RAM ---"
	@free -h
	@echo ""
	@echo "--- DISK ---"
	@df -h | grep '^/dev/'
	@echo ""
	@echo "--- CPU LOAD ---"
	@uptime
	@echo ""
	@echo "--- CPU DETAIL ---"
	@top -bn1 | grep "Cpu(s)" | \
		sed s/st// | \
		awk '{print "Usage: " 100-$$8 "% (Idle: "$$8"%)"}'
	@echo ""
	@echo "--- CONSO RAM PAR SERVICE ---"
	@echo "Consommation RAM par service via la commande: docker stats --no-stream"
	@docker stats --no-stream

docker-reset-for-full-simu: ## [PROD][DOCKER] Reset DVC (lock/cache) et data (raw/preprocessed) pour simu propre
	@echo "🧹 Suppression des verrous DVC et des données temporaires..."
	@# Utilisation de sudo car le cache DVC peut être créé par un conteneur avec des droits root
	@sudo rm -rf dvc.lock .dvc/cache/* data/raw/* data/preprocessed/*

	@echo "📝 Réinitialisation du dvc.lock (évite les erreurs de parsing Airflow)..."
	@echo "schema: '2.0'" > dvc.lock
	@echo "stages: {}" >> dvc.lock

	@echo "🔍 État des lieux après nettoyage :"
	@echo "--- dvc.lock ---" && cat dvc.lock
	@echo "--- .dvc/cache/ ---" && ls -A .dvc/cache/ || echo "(Dossier vide ou inexistant)"
	@echo "--- data/raw/ ---" && ls -A data/raw/ || echo "(Dossier vide ou inexistant)"
	@echo "--- data/preprocessed/ ---" && ls -A data/preprocessed/ || echo "(Dossier vide ou inexistant)"

docker-disks-storage: ## [DEBUG] Vérifier l'espace disque des volumes
	@# Tous les disks commencent par $(PROJECT_NAME)
	docker system df -v | grep $(PROJECT_NAME)


# ================================================================================================
# ------------------------------------ DOCKER SERVICE DEBUG --------------------------------------
# ================================================================================================

docker-shell-mlflow: ## [DEBUG] Entrer dans le serveur MLFlOW (contenu des répertoires)
	@echo " ==========================================================================="
	@echo " ------ On entre dans le serveur MLFLOW"
	@echo " ------ ASTUCE!: cd art* pour aller au directory artefacts."
	@echo " ------ Très utile quand on veut accéder aux contenus des répertoires RUNx"
	@echo " ------ Pour sortir du shell, taper la commande: exit"
	@echo " ==========================================================================="
	docker exec -it mlflow_server sh

docker-shell-postgres: ## [DEBUG] Entrer dans la base de donnée POSTGRES
	@echo " ==========================================================================="
	@echo " ------ On entre dans la base de donnée de POSTGRES"
	@echo " ------ ASTUCE!: cd va* pour aller au directory var"
	@echo " ------ Pour le contenu, taper la commande: ls -lh /var/lib/postgresql/data"
	@echo " ------ Pour sortir du shell, taper la commande: exit"
	@echo " ==========================================================================="
	docker exec -it postgres_db sh

db-psql-postgres-data: ## [DEBUG] Vérifier si les runs sont bien enregistrés
	@echo "--- Liste des tables MLflow dans POSTGRES ---"
	docker exec -it postgres_db psql -U airflow -d airflow -c "\dt"

db-psql-postgres-disk: ## [DEBUG] Voir la taille réelle occupée sur le disque
	docker exec -it postgres_db du -sh /var/lib/postgresql/data
test-env: ## [DEBUG] Affichage du port Nging
	@echo "Le port vu par Make est : $(NGINX_PORT_OUT)"
variales: ## [DEBUG] Voir si les variables dans docker-compose.yml sont bien comprises
	docker compose config
test-variables: ## [DEBUG] tester la liste des variables pour les services
	echo "INDEPENDANT_SERVICES: $(INDEPENDANT_SERVICES)"
	echo ""
	echo "INDEPENDANT_SERVICES_REGEX: $(INDEPENDANT_SERVICES_REGEX)"
	echo ""
	echo "INDEPENDANT_SERVICES_NUM: $(INDEPENDANT_SERVICES_NUM)"
	echo ""
	echo "DEPENDANT_SERVICES: $(DEPENDANT_SERVICES)"
	echo ""
	echo "DEPENDANT_SERVICES_REGEX: $(DEPENDANT_SERVICES_REGEX)"
	echo ""
	echo "DEPENDANT_SERVICES_NUM: $(DEPENDANT_SERVICES_NUM)"
