# ==========================================================
# CONFIGURATION DES DROITS D'ACCÈS POUR AIRFLOW
# ==========================================================

1. Création des répertoires nécessaires :
mkdir dags logs plugins

2. Alignement des droits avec le Docker Daemon et le Makefile :
# On donne la propriété à l'utilisateur 'ubuntu' et au groupe 'root' (0).
# Cela permet au conteneur Airflow (le scheduler et le workder), via GID=0,
# d'écrire sans être root utilisateur.
# -R (récursivité) pour ces répertoires et tout ce qui est en dessous
sudo chown -R ubuntu:0 logs dags plugins

3. Sécurisation des permissions (Mode 775) :
# rwx (7) pour l'utilisateur ubuntu
# rwx (7) pour le groupe root (Airflow)
# r-x (5) pour le reste du monde (Sécurité)
sudo chmod -R 775 logs dags plugins

4. Commande de vérification :
# On doit voir : drwxrwxr-x  ubuntu root (ou 0)
ls -lha

5. Dans le répertoire dags et plugins, création de .gitkeep
touch dags/.gitkeep
touch plugins/.gitkeep

6. Dans le répertoire logs, création de .gitignore
touch plugins/.gitignore
On ne veut garder que ce fichier dans le github donc on met:
*
!.gitignore
