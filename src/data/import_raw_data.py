# import_raw_data.py (version ed01) dans src/data/

import sys
from pathlib import Path
import requests
import os
import logging

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


def main(
    filenames=[
        "caracteristiques-2021.csv",
        "lieux-2021.csv",
        "usagers-2021.csv",
        "vehicules-2021.csv",
    ],
    bucket_folder_url="https://mlops-project-db.s3.eu-west-1.amazonaws.com/accidents/",
):
    """Upload data from AWS s3 in ./data/raw"""

    # Cette ligne est inutile car sys.argv[1] est dans le try
    # raw_data_relative_path = sys.argv[1]

    # On récupère les chemins (Crash ici si le dvc.yaml est incomplet)
    try:
        raw_data_relative_path = Path(sys.argv[1])
    except IndexError:
        print("❌ Erreur : dvc.yaml n'a pas fourni assez d'arguments.")
        sys.exit(1)

    # import_raw_data(raw_data_relative_path, filenames, bucket_folder_url)
    # logger = logging.getLogger(__name__)
    # logger.info("making raw data set")

    # On tente l'exécution (vérification des droits du répertoire)
    try:
        import_raw_data(raw_data_relative_path, filenames, bucket_folder_url)
        logger = logging.getLogger(__name__)
        logger.info("making raw data set")
    except PermissionError:
        # Si le dossier data est créé par erreur avec les droits Root
        # alors il faut le remettre en droit utilisateurs pour poursuivre
        print("\n" + "!" * 60)
        print("❌ ERREUR DE PERMISSION DÉTECTÉE")
        print(f"Impossible de créer le dossier : {raw_data_relative_path}")
        print("-" * 60)
        print("CAUSE PROBABLE :")
        print(
            "Le dossier 'data' (ou le dossier parent) appartient "
            "à l'utilisateur 'root'."
        )
        print("🚨 PROBLEME DE CONFIGURATION A INVESTIGUER: CI-DESSOUS LE WORKAROUND")
        print("Vérifier avec la commande: ls -lha data")
        print("\nSOLUTION POUR RÉPARER:")
        print(
            # Confirmer que le problème vient du répertoire data
            # (bien vérifier que seul point à la fin)
            "Si 'root root xxxx .'  est affiché (xxx pour taille/mois/heure):\n"
            "alors faire: sudo chown -R $USER:$USER data\n"
            # Si le problème vient du répertoire parent (2 points à la fin)
            "Si 'root root xxxx ..'  est affiché (xxx pour taille/mois/heure):\n"
            "alors faire: sudo chown -R $USER:$USER AvecNomDuRepertoireParent"
        )
        print("!" * 60 + "\n")
        sys.exit(1)  # On arrête proprement le script


if __name__ == "__main__":
    log_fmt = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    main()
