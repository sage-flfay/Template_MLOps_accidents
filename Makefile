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
.PHONY: docker_service_check-health docker_check_port_free docker_ssl_prep docker_prod_or_debug
.PHONY: docker-train docker-dvc

# Raccourci : taper juste "make" lancera la liste des commandes du Makefile
.DEFAULT_GOAL := help

# ========================================
# --- VARIABLES (Paramètres du Projet) ---
# ========================================

# On l'utilise aussi dans le champs name défini au début de docker_compose.yml
# L'export permet de le rendre visible à tous
# Préféré à l'ajout de la variable dans .env qui est souvent écrasé
export PROJECT_NAME=accidents_severity

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
DAGSHUB_USER ?= sage-flfay

# Définition du chemin pour uv (sinon pb avec Makefile qui perd uv à la ligne suivante)
UV_BIN = $(HOME)/.local/bin/uv
UV_PATH := $(HOME)/.local/bin

# Pour utiliser uv au lieu de $(UV_BIN) uniquement dans le MakeFile.
# Avantage: pour la cible "pipeline:" en faisant uv run dvc repro, 
# dvc.yaml en hérite mais uniquement dans ce cas. Donc on rajoute UV_PATH au PATH
export PATH := $(UV_PATH):$(PATH)
# NB: Chaque ligne de commande est vue comme un Shell (avec ".ONESHELL:" présent, c'est pour chaque cible)
# Ainsi, après import de uv, on passe à la ligne de commande suivante ET l'export PATH, lui,
# est réinjecté par Make dans chaque nouveau Shell qu'il ouvre <=> donc pour chaque nouvelle ligne commande

# On récupère les identifiants utilisateurs
USER_ID := $(shell id -u)
GROUP_ID := $(shell id -g)

# On assigne de façon définitive (les :)
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

# =================================================
# --- SETUP COMPLET (À lancer la première fois) ---
# =================================================
# NB: ne jamais mettre de commentaire après \ car génère une erreur
# @ devant une commande (ex: @if) pour que la commande ne soit pas affichée
# Pour les if comme on a déjà @if, la commande echo "xxx" n'est donc pas affichée et donc pas de risque d'avoir le message affiché 2 fois

install: ## [INIT] Installation complète du projet
	@# ******************************************************************************************************
	@# 0. Vérification des clés et code secrets dans le make (Priorité n°1)
	@# ******************************************************************************************************

	@if [ -z "$(DAGSHUB_ACCESS_KEY_ID)" ] || [ -z "$(DAGSHUB_SECRET_ACCESS_KEY)" ]; then \
		echo "---------------------------------------------------------------------------------"; \
		echo "❌ ERREUR : Clés DagsHub manquantes !"; \
		echo "👉 Commande : make setup DAGSHUB_ACCESS_KEY_ID=XXX DAGSHUB_SECRET_ACCESS_KEY=YYY"; \
		echo "👉 OU FAIRE D'ABORD export DAGSHUB_ACCESS_KEY_ID=XXX PUIS export DAGSHUB_SECRET_ACCESS_KEY=YYY"; \
		echo "👉 ET export DAGSHUB_USER=user_x SI CE N'EST PAS sage-flfay PAR DEFAUT"; \
		echo "---------------------------------------------------------------------------------"; \
		echo "💡 NOTE : L'erreur 'make: *** Error 1' qui va suivre est NORMALE,"; \
		echo "          elle confirme l'arrêt de la procédure."; \
		exit 1; \
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
		uv pip install -e .; \
	fi

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
                sudo rm -rf .dvc data models; \
                uv run dvc init --no-scm; \
                mkdir -p .dvc/cache; \
                sudo chown -R $(USER):$(USER) .dvc; \
                touch .AccidentsSetupDVC_AlreadyDone; \
	fi

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
	@# "$(DAGSHUB_xxxx_KEY_ID)" : on le met toujours entre guillemet dans le Makefile pour être interprété
	@# comme une chaine de caractère et ainsi éviter une potentielle commande dû à des caractères spéciaux
	@uv run dvc remote modify origin --local access_key_id "$(DAGSHUB_ACCESS_KEY_ID)"
	@echo "uv run dvc remote modify origin --local secret_access_key ************"
	@uv run dvc remote modify origin --local secret_access_key "$(DAGSHUB_SECRET_ACCESS_KEY)"
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
	@grep -qxF "/models/" .gitignore || echo "/models/" >> .gitignore
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
	@if [ -z "$(DAGSHUB_ACCESS_KEY_ID)" ] || [ -z "$(DAGSHUB_SECRET_ACCESS_KEY)" ]; then \
		echo "❌ Erreur 1: Les secrets DAGSHUB ne sont pas configurés dans l'env."; \
		exit 1; \
	fi

	@# Ici on ne fait PAS de 'dvc init', on utilise le .dvc/ déjà présent dans Git
	@echo "🔐 Configuration des accès DagsHub..."
	@# "$(DAGSHUB_xxxx_KEY_ID)" : on le met toujours entre guillemet dans le Makefile pour être interprété
	@# comme une chaine de caractère et ainsi éviter une potentielle commande dû à des caractères spéciaux
	uv run dvc remote modify origin --local access_key_id "$(DAGSHUB_ACCESS_KEY_ID)"
	uv run dvc remote modify origin --local secret_access_key "$(DAGSHUB_SECRET_ACCESS_KEY)"
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
	@mode=""; \
	while [ "$$mode" != "prod" ] && [ "$$mode" != "debug" ]; do \
		echo "💡 prod (production): mode sécurisé SSL/HTTPS" ; \
		echo "💡 debug: mode NON sécurisé HTTP" ; \
		echo -n "👉 Choisir le mode (prod/debug): " && read mode; \
		if [ "$$mode" != "prod" ] && [ "$$mode" != "debug" ]; then \
			echo "❌ Erreur: Saisie invalide. Merci de taper 'prod' ou 'debug'.\n"; \
		fi; \
	done; \
	if [ "$$mode" = "debug" ]; then \
		echo "NGINX_MODE=debug" > .env; \
		echo "NGINX_PORT_OUT=80" >> .env; \
		echo "NGINX_PORT_IN=80" >> .env; \
		echo "NGINX_CONF_FILE=nginx_debug.conf" >> .env; \
		echo "✅ Mode DEBUG configuré (Port 80, Conf HTTP)"; \
	else \
		echo "NGINX_MODE=prod" > .env; \
		echo "NGINX_PORT_OUT=443" >> .env; \
		echo "NGINX_PORT_IN=443" >> .env; \
		echo "NGINX_CONF_FILE=nginx.conf" >> .env; \
		echo "✅ Mode PROD configuré (Port 443, Conf SSL/HTTPS)"; \
	fi
	@echo "------------------------------------------"
	@echo "📝 Fichier .env généré avec succès !"
	@echo "------------------------------------------"


docker-build: ## [PROD][DOCKER] Construction de l'image Docker de l'API (Environnement isolé)
	@echo "CONFIGURATION EN MODE PRODUCTION (SÉCURISÉ) OU DEBUG (NON SÉCURISÉ)..."
	@# Le choix du mode détermine le port à utiliser
	@$(MAKE) docker_prod_or_debug

	@echo "🐳 Construction de l'image Docker (API + Modèle)..."
	@# docker compose build --no-cache ==> no-cache : on reinstalle tout systématiquement
	@# Sans le no-cache, on ne réinstalle que les sections modifiées
	@# NB: le cache est sur la machine et non pas dans l'image. Donc n'alourdit pas l'image
	@docker compose build


docker-clean-build: ## [DEV] Reset TOTAL (Volumes/Images/Cache) - Construction de l'image avec réinstallation systématique
	@echo "🛑 Arrêt et suppression des conteneurs existants..."
	@docker compose down --volumes --remove-orphans

	@echo "🗑️ Nettoyage des fichiers locaux..."
	@sudo rm -rf models/*.joblib

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

docker-FullClean-build: ## [DEV] Reset TOTAL (Volumes/Images/Cache) ET NETTOYAGE DISK - Construction de l'image avec réinstallation systématique
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
	@sudo rm -rf models/*.joblib

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
	@echo "🚀 Lancement de l'import/process avec accès aux métadonnées DVC..."
	@echo " On monte des volumes temporaires pour exéctuer le DVC"
	@docker compose run --rm \
		-v $(PWD)/.dvc:/app/.dvc \
		-v $(PWD)/dvc.yaml:/app/dvc.yaml \
		-v $(PWD)/dvc.lock:/app/dvc.lock \
		-w /app \
		train uv run dvc repro import process


# Lancer tout l'écosystème (API + MLflow containerisé)
# L'option -d (--detach) pour le faire tourner en tâche de fond (daemon mode)
docker-start: ## [PROD][DOCKER] Bascule en mode conteneur (stoppe MLflow local pour éviter les conflits)
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

docker-stop: ## [PROD][DOCKER] Arrêt des conteneurs (prêts à redémarrer)
	@echo "⏸️  Arrêt des services Docker (Stop)..."
	@docker compose stop
	@echo "✅ Services arrêtés (prêts à redémarrer)."


docker-down: ## [PROD][DOCKER] Arrêt ET suppression complète (Nettoie réseaux et conteneurs)
	@echo "🛑 Suppression de toute l'infrastructure Docker (Down)..."
	@docker compose down
	@echo "✨ Tout a été nettoyé proprement."


docker-status: ## [PROD][DOCKER] Affiche l'état des services et les ports actifs
	@echo "📊 État des conteneurs Docker..."
	@docker compose ps
	@echo "----------------------------------------------------------------"
	@echo "💡 'Up' : le service fonctionne normalement."

# ================================================================================================
# ------------------------------------ DOCKER SERVICE DEBUG --------------------------------------
# ================================================================================================

docker-disks-storage: ## [DEBUG][DOCKER] Vérifier l'espace disque des volumes
	@# Tous les disks commencent par $(PROJECT_NAME)
	docker system df -v | grep $(PROJECT_NAME)

docker-shell-mlflow: ## [DEBUG][DOCKER] Entrer dans le serveur MLFlOW (contenu des répertoires)
	@echo " ==========================================================================="
	@echo " ------ On entre dans le serveur MLFLOW"
	@echo " ------ ASTUCE!: cd art* pour aller au directory artefacts."
	@echo " ------ Très utile quand on veut accéder aux contenus des répertoires RUNx"
	@echo " ------ Pour sortir du shell, taper la commande: exit"
	@echo " ==========================================================================="
	docker exec -it mlflow_server sh

docker-shell-postgres: ## [DEBUG][DOCKER] Entrer dans la base de donnée POSTGRES
	@echo " ==========================================================================="
	@echo " ------ On entre dans la base de donnée de POSTGRES"
	@echo " ------ ASTUCE!: cd va* pour aller au directory var"
	@echo " ------ Pour le contenu, taper la commande: ls -lh /var/lib/postgresql/data"
	@echo " ------ Pour sortir du shell, taper la commande: exit"
	@echo " ==========================================================================="
	docker exec -it postgres_db sh

db-psql-postgres-data: ## [DEBUG][DOCKER] Vérifier si les runs sont bien enregistrés
	@echo "--- Liste des tables MLflow dans POSTGRES ---"
	docker exec -it postgres_db psql -U airflow -d airflow -c "\dt"

db-psql-postgres-disk: ## [DEBUG][DOCKER] Voir la taille réelle occupée sur le disque
	docker exec -it postgres_db du -sh /var/lib/postgresql/data
