import mlflow
import argparse
import sys

def display_artifacts(client, run_id):
    """
    Display all artifacts in a run.
    
    Args:
        client: MLflow client
        run_id: ID of the run to inspect
    """
    # ====================================================================================
    # Récupère la liste des fichiers/dossiers stockés pour ce Run ID spécifique
    # ====================================================================================
    artifacts = client.list_artifacts(run_id)
    print("\nAvailable artifacts:")
    for idx, artifact in enumerate(artifacts, 1):
        # Affiche le nom de l'artifact et précise s'il s'agit d'un fichier ou d'un doosier
        print(f"{idx}. {artifact.path} {'(dir)' if artifact.is_dir else '(file)'}")
        if artifact.is_dir:
            # Si c'est un dossier (ex: rf_apples), on liste son contenu interne
            nested_artifacts = client.list_artifacts(run_id, artifact.path)
            for nested in nested_artifacts:
                print(f"   - {nested.path}")
    return artifacts

def select_model_path(artifacts):
    """
    Let user select which artifact directory to use for model registration.
    
    Args:
        artifacts: List of artifacts
    Returns:
        str: Selected artifact path
    """
    # Filter only directories
    # ========================================================================================
    # On filtre pour ne garder que les dossiers (car un modèle MLflow est toujours un dossier)
    # ========================================================================================
    dirs = [art for art in artifacts if art.is_dir]
    
    if not dirs:
        # ====================================================================================
        # CORRECTION STRICTE : Si aucun dossier n'est trouvé, on ne lève pas d'exception.
        # On informe l'utilisateur et on retourne une chaîne vide pour pointer vers la racine.
        # ====================================================================================
        print("INFO: No directories found in artifacts. Using root as model path.")
        return ""
    
    # S'il n'y a qu'un seul dossier, on le sélectionne automatiquement
    if len(dirs) == 1:
        return dirs[0].path

    # S'il y a plusieurs, le script demande une saisie utilisateur dans le terminal
    print("\nMultiple model directories found. Please select one:")
    for idx, dir_artifact in enumerate(dirs, 1):
        print(f"{idx}. {dir_artifact.path}")
        
    while True:
        try:
            choice = int(input("\nEnter the number of your choice: "))
            if 1 <= choice <= len(dirs):
                return dirs[choice-1].path
            print(f"Please enter a number between 1 and {len(dirs)}")
        except ValueError:
            print("Please enter a valid number")

def get_model_uri(tracking_uri, experiment_name, run_id=None):
    """
    Get model URI either from a specific run_id or the latest successful run in an experiment.
    """
    # Connecte le script au serveur MLflow (ex: https://localhost:8080)
    mlflow.set_tracking_uri(tracking_uri)
    print(f"Using tracking URI: {tracking_uri}")
    
    # Get experiment
    # Cherche l'objet Experiment  par son nom pour obtenir son ID
    experiment = mlflow.get_experiment_by_name(experiment_name)
    if experiment is None:
        experiments = mlflow.search_experiments()
        available_experiments = [exp.name for exp in experiments]
        raise Exception(f"Experiment '{experiment_name}' not found. Available experiments: {available_experiments}")
    
    if run_id:
        print(f"Loading model from run ID: {run_id}")
    else:
        # Si aucun Run ID n'est fourni, MLflow cherche le dernier run terminé avec succès (FINISHED) dans l'expérience spécifiée
        print(f"Loading latest successful model from experiment: {experiment_name}")
        runs = mlflow.search_runs(
            experiment_ids=[experiment.experiment_id],
            filter_string="status = 'FINISHED'",
            order_by=["start_time DESC"],
            max_results=1
        )
        if runs.empty:
            raise Exception(f"No successful runs found in experiment '{experiment_name}'")
        run_id = runs.iloc[0].run_id
        print(f"Found latest run ID: {run_id}")
    
    # Get run information and artifacts
    # Initialise le client bas niveau pour manipuler les artéfacts 
    client = mlflow.tracking.MlflowClient()
    artifacts = display_artifacts(client, run_id)
    
    # Select model path
    # Détermine le chemin final du modèle (ex: runs/ID/re_apples)
    model_path = select_model_path(artifacts)
    model_uri = f"runs:/{run_id}/{model_path}"
    return model_uri, run_id

def register_model(model_uri, model_name, tags=None):
    """
    Register a model and set its tags
    
    Args:
        model_uri: URI of the model to register
        model_name: Name to register the model under
        tags: Dictionary of tags to set
    """
    print(f"\nRegistering model from: {model_uri}")
    print(f"Model name: {model_name}")
    
    client = mlflow.tracking.MlflowClient()
    
    try:
        # ====================================================================================
        # CORRECTION STRICTE : Utilisation du Client MLflow pour forcer l'enregistrement.
        # 1. On tente de créer l'entrée du modèle dans le registre si elle n'existe pas.
        # ====================================================================================
        try:
            client.create_registered_model(model_name)
            print(f"Registered model container '{model_name}' created.")
        except Exception:
            # Si le conteneur existe déjà, on continue simplement
            print(f"Registered model container '{model_name}' already exists.")

        # ====================================================================================
        # 2. On crée une version de modèle en pointant explicitement sur l'URI de la source.
        # Cette méthode (create_model_version) est plus robuste que mlflow.register_model 
        # car elle ne dépend pas des métadonnées "logged_model" qui semblent manquer ici.
        # ====================================================================================
        # On extrait le run_id depuis l'URI (runs:/run_id/path)
        run_id = model_uri.split('/')[1]
        
        model_details = client.create_model_version(
            name=model_name,
            source=model_uri,
            run_id=run_id
        )
        
        print(f"Model registered successfully with version: {model_details.version}")
        
        # Set tags if provided
        # Ajoute des métadonnées (tags) au modèle enregistré pour le retrouver facilement
        if tags:
            for key, value in tags.items():
                client.set_registered_model_tag(model_name, key, value)
            print("Tags set successfully")
            
        return model_details
        
    except Exception as e:    
        print(f"Failed to register model")
        print(f"Error: {str(e)}")
        raise

def manage_tags(model_name, version=None):
    """
    Interactively manage tags for a registered model or specific version
    """
    # Utilise le client pour modifier les métadonnées sans ré-entraîner le modèle
    client = mlflow.tracking.MlflowClient()
    
    while True:
        print("\nTag Management Options:")
        print("1. Add/Update tag")
        print("2. Delete tag")
        print("3. List current tags")
        print("4. Exit tag management")
        
        choice = input("\nEnter your choice (1-4): ")
        
        try:
            if choice == "1":
                key = input("Enter tag key: ")
                value = input("Enter tag value: ")
                if version:
                    # Applique le tag à une version précise (ex: Version 1)
                    client.set_model_version_tag(model_name, version, key, value)
                else:
                    # Applique le tag au conteneur global du modèle
                    client.set_registered_model_tag(model_name, key, value)
                print(f"Tag {key}={value} set successfully")
                
            elif choice == "2":
                key = input("Enter tag key to delete: ")
                if version:
                    client.delete_model_version_tag(model_name, version, key)
                else:
                    client.delete_registered_model_tag(model_name, key)
                print(f"Tag {key} deleted successfully")
                
            elif choice == "3":
                if version:
                    # Récupère les infos d'une version spécifique pour voir ses tags
                    model_version = client.get_model_version(model_name, version)
                    tags = model_version.tags
                else:
                    # Récupère les infos globales du modèle
                    model = client.get_registered_model(model_name)
                    tags = model.tags
                print("\nCurrent tags:")
                for key, value in tags.items():
                    print(f"{key}: {value}")
                    
            elif choice == "4":
                break
                
            else:
                print("Invalid choice, please try again")
                
        except Exception as e:
            print(f"Error: {str(e)}")

def main():
    # ===========================================================================================================
    # Configure les arguments de la ligne de commande (CLI)
    # ===========================================================================================================
    parser = argparse.ArgumentParser(description='Register MLflow model and manage tags')
    parser.add_argument('--tracking_uri', type=str, required=True, help='MLflow tracking URI')
    parser.add_argument('--experiment_name', type=str, required=True, help='MLflow experiment name')
    parser.add_argument('--model_name', type=str, required=True, help='Name to register the model under')
    parser.add_argument('--run_id', type=str, help='Specific run ID to load (optional)')
    parser.add_argument('--tags', type=str, help='Initial tags in format "key1=value1,key2=value2" (optional)')
    args = parser.parse_args()

    try:
        # Découpe la chaîne de caractères des tags pour en faire un dictionnaire Python
        # Parse initial tags if provided
        initial_tags = {}
        if args.tags:
            for tag_pair in args.tags.split(','):
                key, value = tag_pair.split('=')
                initial_tags[key.strip()] = value.strip()
        
        # Get model URI
        # Etape 1 : Construction de l'URI du modèle
        model_uri, run_id = get_model_uri(args.tracking_uri, args.experiment_name, args.run_id)
        
        # Register model with initial tags
        # Etape 2 : Enregistrement effectif
        model_details = register_model(model_uri, args.model_name, initial_tags)
        
        # Interactive tag management
        # Etape 3 : Menu interactif pour les tags (factultatif))
        print("\nWould you like to manage tags for this model? (yes/no)")
        if input().lower().startswith('y'):
            manage_tags(args.model_name, model_details.version)
        
    except Exception as e:
        # en cas d'erreur (ex: serveur éteint), affiche l'erreur et ferme le script proprement
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    # Point d'entrée du script
    main()