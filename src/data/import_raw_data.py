# import_raw_data.py (version ed01) dans src/data/

import sys
from pathlib import Path
import requests
import os
import logging
import shutil

# On ne demande pas l'autorisation au user car incohérent dans un pipline
# from check_structure import check_existing_file, check_existing_folder


def import_raw_data(raw_data_relative_path, filenames, bucket_folder_url):
    """import filenames from bucket_folder_url in raw_data_relative_path"""
    # if check_existing_folder(raw_data_relative_path):
    #    os.makedirs(raw_data_relative_path)
    # Créer le dossier sans demande d'autorisation car incohérent dans un pipline
    # Si le dossier existe déjà (exist_ok=True), on continue
    os.makedirs(raw_data_relative_path, exist_ok=True)
    # download all the files
    for filename in filenames:
        # adresse complète du fichier à télécharger
        input_file = os.path.join(bucket_folder_url, filename)
        # Copier le fichier dans ce cheminvia commande simple et lisible
        # Dans def main(), raw_data_relative_path = Path(sys.argv[1])
        # output_file = os.path.join(raw_data_relative_path, filename)
        output_file = raw_data_relative_path / filename
        # "Si le fichier n'est pas là, je le télécharge"
        # On ne demande plus l'autorisation au user
        # if check_existing_file(output_file):
        if not os.path.isfile(output_file):
            # object_url = input_file
            print(f"downloading {input_file} as {os.path.basename(output_file)}")
            # response = requests.get(object_url)
            response = requests.get(input_file)
            if response.status_code == 200:
                # with open: garantit la fermeture du fichier même si un problème
                # arrive en cours d'écriture. NB wb=écrire en mode binaire
                # response.content: récupère le binaire brut directement depuis le
                # serveur et l'écrit tel quel dans le fichier.
                # Aucune interprétation et intégrité du fichier garanti
                with open(output_file, "wb") as f:
                    f.write(response.content)
                # Process the response content as needed
                # content = response.text
                # text_file = open(output_file, "wb")
                # text_file.write(content.encode("utf-8"))
                # text_file.close()
            else:
                print(f"Error accessing the object {input_file}:", response.status_code)
        else:
            print(f"{filename} already exists. Skipping download.")

def main():
    # Récupération des chemins source (simu_raw_data) et destination (data/raw)
    # et la variable year
    try:
        source_relative_path_simu_data_web = Path(sys.argv[1])
        dest_relative_path_raw_data = Path(sys.argv[2])
        year_str = sys.argv[3]
    except IndexError:
        print("❌ Usage: python -m src.data.import_raw_data <source> <dest> <year>")
        sys.exit(1)

    # Construction des chemins (Relatifs à la racine /app)
    # On considère que le script est lancé depuis /app
    root_dir = Path.cwd()
    src_path = root_dir / source_relative_path_simu_data_web
    dst_path = root_dir / dest_relative_path_raw_data

    print(f"Repertoire source: {src_path}")
    print(f"Repertoire destination: {dst_path}")

    # Vérification que la source est bien un répertoire
    if not src_path.is_dir():
        print(
            f"❌ Erreur : La source {source_relative_path_simu_data_web} "
            "n'est pas un répertoire valide."
        )
        sys.exit(1)

    try:
        year = int(year_str)
    except ValueError:
        print(f"❌ ERREUR CRITIQUE : L'année fournie '{year_str}' n'est pas un nombre valide.")
        sys.exit(1)

    years_to_process = [year]
    # 2019 = Année de départ
    if year < 2019:
        print(f"❌ Erreur de date. Seulement à partir de 2019 et il y a: {year}")
        sys.exit(1)

    if year > 2019:
        years_to_process.append(year - 1)

    base_names = ["caracteristiques", "lieux", "usagers", "vehicules"]

    # On crée le répertoire distant (data/raw) si pas présent
    dst_path.mkdir(parents=True, exist_ok=True)

    for current_y in years_to_process:
        print(f"📂 Importation de l'année {current_y}")

        # On génère la liste des fichiers pour cette année précise
        current_filenames = [f"{name}-{current_y}.csv" for name in base_names]
        missing_files = []

        for f in current_filenames:
            s_file = src_path / f
            d_file = dst_path / f

            if s_file.exists():
                shutil.copy(s_file, d_file)
                print(f"  ✅ {f} importé avec succès.")
            else:
                missing_files.append(f)

        # Logique de validation
        if missing_files:
            print(f"❌ Erreur critique : Fichiers manquants: {missing_files}")
            sys.exit(1)
        else:
            print(f"✨ Tous les fichiers importés avec succès.")


    # Cas d'origine en récupérant sur le site mais uniquement fonctionnel sur 2021
    # bucket_folder_url = "https://mlops-project-db.s3.eu-west-1.amazonaws.com/accidents/"
    #try:
    #    import_raw_data(raw_data_relative_path, filenames, bucket_folder_url)
    #    logging.info("making raw data set")
    #except PermissionError:
    #    print("❌ ERREUR DE PERMISSION : Faites 'sudo chown -R $USER:$USER data'")
    #    sys.exit(1)

if __name__ == "__main__":
    log_fmt = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    logging.basicConfig(level=logging.INFO, format=log_fmt)
    main()
