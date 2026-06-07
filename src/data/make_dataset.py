# make_dataset.py (version ed01) src/data/make_dataset.py

# -*- coding: utf-8 -*-
import sys
from pathlib import Path
import pandas as pd
import numpy as np

# import click
import logging
from sklearn.model_selection import train_test_split

# Grâce à "uv pip install -e ." fait lors de make install,
# cat .venv/lib/python3.12/site-packages/template_mlops_accidents.pth affiche
# /home/ubuntu/Template_MLOps_accidents/src. Donc le chemin est defacto connu
# par le système ubuntu.
# sys.path.append(str(Path(__file__).resolve().parents[1]))
# NB: dans .dockerignore, on a mis .venv. Ainsi les RUN uv pip install -e .
# utilisés dans les Dockerfile ne modifie pas le .venv ubuntu.
# De plus, dans le dag, on a pris soin de créer son propre .venv pour ne
# pas modifier le .venv d'ubuntu et donc le chemin sera de facto /app/working_dir/src
from src.api.config import CSV_MANDATORY_COLUMNS, FEATURES, FEATURES_CRITICAL
from src.features.build_features import apply_feature_remapping

# def main(input_filepath, output_filepath):
def main():
    """Runs data processing scripts to turn raw data from (../raw) into
    cleaned data ready to be analyzed (saved in ../preprocessed).
    """
    logger = logging.getLogger(__name__)
    logger.info("making final data set from raw data")

    try:
        input_filepath = Path(sys.argv[1])
        output_filepath = Path(sys.argv[2])
    except IndexError:
        print("❌ Erreur : dvc.yaml n'a pas fourni assez d'arguments.")
        sys.exit(1)

    # On vérifie si le chemin d'entrée EXISTE vraiment
    if not input_filepath.exists():
        print(
            "❌ Erreur de syntaxe dans dvc.yaml : "
            f"Le chemin '{input_filepath}' n'existe pas !"
        )
        print(f"📍 Emplacement actuel : {Path.cwd()}")
        sys.exit(1)

    # Si on arrive ici, tout est OK
    print(f"✅ Chemin source vérifié : {input_filepath}")
    print(f"✅ Chemin sortie : {output_filepath}")

    # On récupère la liste de tous les fichiers par catégorie
    input_filepath_users = sorted(list(input_filepath.glob("usagers-*.csv")))
    input_filepath_caract = sorted(list(input_filepath.glob("caracteristiques-*.csv")))
    input_filepath_places = sorted(list(input_filepath.glob("lieux-*.csv")))
    input_filepath_veh = sorted(list(input_filepath.glob("vehicules-*.csv")))

    # Vérification de sécurité
    if not input_filepath_users:
        print(f"❌ Aucun fichier trouvé dans {input_filepath}")
        sys.exit(1)

    # Call the main data processing function with the provided file paths
    process_data(
        input_filepath_users,
        input_filepath_caract,
        input_filepath_places,
        input_filepath_veh,
        output_filepath,
    )

# Vérifier que les colonnes obligatoires existent avec le bon nom de variable
# Une fois vérifiés, retourner le df avec seulement la liste obligatoire
def load_and_validate(file_path, category, config_dict):
    # --Importing dataset
    # Configuration commune pour une sécurité maximale
    read_params = {
        "sep": ";",
        "header": 0,
        # lire tout le fichier avant de décider automatiquement du type de colonne
        "low_memory": False
    }
    # Chargement du CSV
    df = pd.read_csv(file_path, **read_params)

    # Récupération des colonnes obligatoires pour cette catégorie
    mandatory = config_dict[category]

    # Problèmes déjà connus
    if ("Num_Acc" in mandatory) and ("Num_Acc" not in df.columns) and ("Accident_Id" in df.columns):
        df = df.rename(columns={"Accident_Id": "Num_Acc"})
        print(f"✅ Renommage : Accident_Id -> Num_Acc pour {file_path}")

    # Vérification de conformité
    missing = [col for col in mandatory if col not in df.columns]

    if missing:
        print(f"⚠️ ERREUR dans {file_path} : colonnes manquantes {missing}")
        # Arrêter tout le script proprement avec un code d'erreur
        sys.exit(1)

    # Retourner que le strict nécessaire
    return df[mandatory]

# output_folderpath remplacé par output_filepath pour rester cohérent
# avec le main et aussi avec la règle de nommage pour les input.
def process_data(
    input_filepath_users,
    input_filepath_caract,
    input_filepath_places,
    input_filepath_veh,
    output_filepath,
):

    # On charge et on concatène immédiatement
    # On utilise une liste de compréhension pour lire tous les fichiers trouvés
    config_sources = {
        "users": input_filepath_users,
        "veh": input_filepath_veh,
        "places": input_filepath_places,
        "caract": input_filepath_caract
    }

    # Créer un dictionnaire vide pour stocker les résultats
    dfs = {}

    # On boucle sur le dictionnaire de configuration
    for category, file_list in config_sources.items():
        # Chargement + Verification des variables + Concaténation
        # Le df retourné ne contient que les variables obligatoires
        combined_df = None # Initialisation à vide pour lever toute ambiguïté
        combined_df = pd.concat(
            [load_and_validate(f, category, CSV_MANDATORY_COLUMNS) for f in file_list],
            ignore_index=True
        )

        # IMPORTANT: TOUTES LES VARIABLES UTILISEES SONT DES NOMBRES OU DEVIENDRONT
        # DES NOMBRES (Ex: pour la Corse on transforme 2A en 201 et 2B en 202)

        # Pour tous les traitements qui suivent, il est plus simple de transformer
        # le dataframe en str et ainsi pouvoir modifier comme on l'entend.
        # LE PIEGE EST LE NaN QUI DEVIENT ALORS UN STRING "nan". MAIS GRACE A
        # combined_df[col] = pd.to_numeric(combined_df[col], errors='coerce')
        # QUI SERA APPLIQUé A LA FIN, TOUT CE QUI N'EST PAS NOMBRE DEVIENT NaN
        # DONC AUCUN NaN NE DISPARAITRA
        # NB: donc inutile de mentionner astype(str dans les commandes après)
        # Toutes les manips avec str ne généreront jamais d'erreur de code
        combined_df = combined_df.astype(str)

        # Traitements spécifiques avant toute conversion numérique

        # Pour id_vehicule, espace ajouté pour une meilleure lecture du nombre
        # Donc, supprimer cet espace pour pouvoir le définir comme un nombre
        # Or comme cet espace peut être ajouté par inadvertance, on en profite pour
        # supprimer les espaces pour toutes les colonnes de type "objet" (texte)
        # Fait d'un coup sur tout le DataFrame.
        # regex à false pour éviter une recherche inutile de motif complexe
        # Commande inoperante pour par exemple "201 764"
        # combined_df = combined_df.apply(lambda x: x.str.replace(' ', '', regex=False))
        # \s : raccourci regex = "n'importe quel type d'espace"; + = "un ou plusieurs"
        combined_df = combined_df.apply(lambda x: x.str.replace(r'\s+', '', regex=True))

        # Pour la colonne "hrmn", on ne garde que les heures. Les minutes pertubent
        # plus la prédiction qu'ils n'apportent d'informations
        # Ainsi, elle pourra être gérée comme une int
        # Ici on traite le cas hh:mm ou h:mm mais aussi hhmm ou hmm(ce typo erreur)
        # Et aussi le cas YYYY-hh-mm
        col = "hrmn"
        if col in combined_df.columns:
            combined_df[col] = (
                combined_df[col].apply(lambda x:
                    x.split('-')[1] if x.count('-') == 2 # Milieu de YYYY-HH-MM
                    else x.split(':')[0] if ':' in x     # Début de HH:MM
                    # Format HHMM ou HMM (on enlève les minutes à la fin)
                    # Si NaN présent, astype(str) le transforme en "nan"
                    else x[:-2] if (len(x) >= 3 and x != "nan")
                    # Cas par défaut : Erreur
                    else "-1"
                )
            )

        # Pour le cas de la Corse, on transforme 2A et 2B en valeur.
        for col in ["dep", "com"]:
            if col in combined_df.columns:
                combined_df[col] = (
                    combined_df[col].str.replace("2A", "201", regex=False)
                )
                combined_df[col] = (
                    combined_df[col].str.replace("2B", "202", regex=False)
                )

        # On remplace , par . (erreur de frappe) pour garantir des floats
        for col in ["lat", "long"]:
            if col in combined_df.columns:
                combined_df[col] = combined_df[col].str.replace(",", ".", regex=False)

        # Maintenant on a la garantie que toutes les colonnes sont des nombres
        # Conversion numérique systématique (Neutralise les caractères intrus)
        for col in combined_df.columns:
            # On convertit en float (to_numeric) et si erreur (ex: caractères)
            # l'option errors='coerce' remplace le contenu par NaN
            combined_df[col] = pd.to_numeric(combined_df[col], errors='coerce')

        print("=" * 60)
        print(f"✅ {category.upper()} : {len(combined_df)} lignes chargées.")


        # Nettoyage dynamique des colonnes critiques
        # Suppression des lignes avec NaN pour les variables critiques
        critical_cols = [c for c in FEATURES_CRITICAL if c in combined_df.columns]
        print("--- Vérification des NaN par colonne critique")
        for col in critical_cols:
            nans = combined_df[col].isna().sum()
            if nans > 0:
                print(f"⚠️ La colonne '{col}' a généré {nans} NaNs.")

        combined_df=combined_df.dropna(subset=critical_cols)

        # NaN remplacé par défaut par -1 pour toutes les colonnes.
        # NB: pour les features critical, comme ça a été géré avant, aucun impact
        for col in combined_df.columns:
            combined_df[col] = combined_df[col].fillna(-1)

            if col not in ['lat', 'long']:
                # On force en int tout ce qui n'est pas coordonnée
                combined_df[col] = combined_df[col].astype(int)
            else:
                # On s'assure que les coordonnées sont bien des floats
                combined_df[col] = combined_df[col].astype(float)

        # On stocke le DataFrame propre dans notre dictionnaire 'dfs'
        dfs[category] = combined_df

        print(f"✅ {category.upper()} : {len(dfs[category])} lignes après dropna.")
        print("")

    # On affecte les DataFrames aux variables finales
    df_users  = dfs["users"]
    df_veh    = dfs["veh"]
    df_places = dfs["places"]
    df_caract = dfs["caract"]

    # Renommage de agg par agg_ pour éviter tout risque de conflit
    # comme par exemple df.agg qui fera une aggrégation au lieu de
    # sélectionner la colonne
    df_caract = df_caract.rename(columns={"agg": "agg_"})

    # Test de cohérence des variables
    # Pour la cible grav
    valid_grav = [1, 2, 3, 4]
    print(
        "Pour users, supprimer les lignes pour les valeurs de la cible 'grav'"
        "différentes de 1, 2, 3 ou 4"
    )
    print(f"users : {df_users.shape[0]} lignes AVANT vérification cible 'grav'")
    df_users = df_users[df_users['grav'].isin(valid_grav)]
    print(f"users : {df_users.shape[0]} lignes APRÈS validation cible 'grav'")
    # Pour les heures
    df_caract = df_caract[df_caract["hrmn"].between(0, 23)]

    # Tri Chronologique (on le refait par sécurité)
    # On trie et on réinitialise l'index pour repartir sur une base propre
    df_users = df_users.sort_values(by="Num_Acc").reset_index(drop=True)
    df_caract = df_caract.sort_values(by="Num_Acc").reset_index(drop=True)
    df_places = df_places.sort_values(by="Num_Acc").reset_index(drop=True)
    df_veh = df_veh.sort_values(by="Num_Acc").reset_index(drop=True)

    # --Creating new columns
    # df: 2 colonnes Num_acc et count = nb occurence de chaque Num_acc
    # On les rajoutera après le merge et le drop_duplicate de Num_acc
    nb_victim = pd.crosstab(df_users.Num_Acc, "count").reset_index()
    nb_vehicules = pd.crosstab(df_veh.Num_Acc, "count").reset_index()
    # On génère de nouvelles colonnes pour usagers
    # year_acc déduit de Num_acc est plus fiable que la colonne an
    df_users["year_acc"] = (
        df_users["Num_Acc"].astype(str).apply(lambda x: x[:4]).astype(int)
    )
    df_users["victim_age"] = df_users["year_acc"] - df_users["an_nais"]
    for i in df_users["victim_age"]:
        if (i > 120) | (i < 0):
            df_users["victim_age"].replace(i, np.nan)
    # hrmn déjà processé auparavant pour ne garder que les heures
    df_caract["hour"] = df_caract["hrmn"]

    # Suppression des colonnes inutiles
    df_caract = df_caract.drop(columns=["hrmn"])
    # --- Warning: an_nais est présent dans FEATURES_CRITICAL
    df_users = df_users.drop(columns=["an_nais"])

    # --Merging datasets
    # A partir de 2019, num_veh inutile car remplacé par id_vehicule pour la fusion
    fusion1 = df_users.merge(df_veh, on=["Num_Acc", "id_vehicule"], how="inner")
    fusion1 = fusion1.sort_values(by="grav", ascending=False)
    fusion1 = fusion1.drop_duplicates(subset=["Num_Acc"], keep="first")
    fusion2 = fusion1.merge(df_places, on="Num_Acc", how="left")
    df = fusion2.merge(df_caract, on="Num_Acc", how="left")

    # --Adding new columns
    df = df.merge(nb_victim, on="Num_Acc", how="inner")
    df = df.rename(columns={"count": "nb_victim"})
    df = df.merge(nb_vehicules, on="Num_Acc", how="inner")
    df = df.rename(columns={"count": "nb_vehicules"})

    # On refait la vérification des NaN après fusion/merge au cas où
    print(f"Nb de lignes du df après le merge final AVANT le dropna: {len(df)}")
    # On garde tout sauf "an_nais" qui a été supprimé
    # On ajoute les 2 nouvelles colonnes qui sont essentielles
    UPDATED_FEATURES_CRITICAL = [f for f in FEATURES_CRITICAL if f != "an_nais"]
    UPDATED_FEATURES_CRITICAL += ["nb_victim", "nb_vehicules"]
    df = df.dropna(subset=UPDATED_FEATURES_CRITICAL)
    df = df.fillna(-1)
    print(f"Nb de lignes du df après le merge final et APRèS le dropna: {len(df)}")

    # NaN est représenté par un float. Donc la colonne int qui a des NaN devien float
    col_float = ["lat", "long"]
    # On réaffecte int par précaution
    for col in df.columns:
        if col not in col_float:
            df[col] = df[col].astype(int)

    # On ne garde que les colonnes définies dans FEATURES dans src/api/config.py
    # On ajoute 'grav' car c'est la cible et il est normale qu'elle ne soit pas
    # dans la liste de FEATURES
    cols_to_keep = FEATURES + ['grav']

    # Cela revient à supprimer Num_acc et id_vehicule de df
    # On s'assure que c'est bien correct sinon problème de configuration
    col_to_remove = ["Num_Acc", "id_vehicule"]
    for col in df.columns:
        if col not in cols_to_keep and col not in col_to_remove:
            print(f"❌ ERREUR : La colonne '{col}' n'est ni à garder, ni à supprimer.")
            print("Vérifier la configuration dans : src/data/make_dataset.py")
            # On arrête tout
            sys.exit(1)

    df = df[cols_to_keep]

    # --Grouping modalities déplacé ici avec la fonction def apply_feature_remapping(df)
    # dans le fichier src/features/build_features.py
    df = apply_feature_remapping(df)


    # modélisation
    target = df["grav"]
    feats = df.drop(["grav"], axis=1)

    # stratify=target: comme les cas graves sont minoritaires cela permet
    # de CONSERVER le même ratio de cas graves dans le train et le test
    X_train, X_test, y_train, y_test = train_test_split(
        feats, target, test_size=0.3, random_state=42, stratify=target
    )

    # --Filling NaN values
    # Précédemment les NaN pour les variables non critiques remplacées par -1
    # Identification de la colonne à traiter
    col_to_impute = "sexe"

    # Calcul du mode sur le train en ignorant les -1
    # (pour éviter que -1 devienne lui-même le mode !)
    sexe_mode = X_train[X_train[col_to_impute] != -1][col_to_impute].mode()[0]

    # Remplacement des -1 par la modalité
    X_train[col_to_impute] = X_train[col_to_impute].replace(-1, sexe_mode)
    X_test[col_to_impute] = X_test[col_to_impute].replace(-1, sexe_mode)

    # Create folder if necessary
    # Le check demande à l'utilisateur de confirmer s'il doit le créer
    # Ce n'est pas adapté à l'automatisation
    # if check_existing_folder(output_folderpath):
    #    os.makedirs(output_folderpath)
    # output_folderpath remplacé par output_filepath pour rester cohérent
    # avec le main et aussi avec la règle de nommage pour les input.
    output_filepath.mkdir(parents=True, exist_ok=True)

    # --Saving the dataframes to their respective output file paths
    for file, filename in zip(
        [X_train, X_test, y_train, y_test], ["X_train", "X_test", "y_train", "y_test"]
    ):
        # Dans le try du main on a output_filepath = Path(sys.argv[2]),
        # on peut faire plus simple et plus lisible
        # output_filepath = os.path.join(output_folderpath, f"{filename}.csv")
        # C'est plus clair en parlant de output_file (on attend un fichier)
        output_file = output_filepath / f"{filename}.csv"
        # Le check demande à l'utilisateur de confirmer s'il doit le créer
        # Ce n'est pas adapté à l'automatisation
        # if check_existing_file(output_filepath):
        #    file.to_csv(output_filepath, index=False)
        # Par défaut on écrase l'ancien fichier
        file.to_csv(output_file, index=False)


if __name__ == "__main__":
    log_fmt = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    main()
