import mlflow
import argparse
import subprocess
import sys

# ===============================================================================
# Gestion des versions du modèle dans le registre MLflow
# Cette fonction affiche toutes les versions disponibles avec leurs méradonnnées.
# ===============================================================================

def list_model_versions(model_name):
    """
    List all versions of a registered model.

    Args:
        model_name: Name of the registered model
    Returns:
        list: List of model versions
    """
    client = mlflow.tracking.MlflowClient()

    try:
        versions = client.search_model_versions(f"name='{model_name}'")
        if not versions:
            raise Exception(f"No versions found for model '{model_name}'")

        print("\nAvailable model versions:")
        for idx, version in enumerate(versions, 1):
            status = version.current_stage
            tags = version.tags if version.tags else {}
            print(f"{idx}. Version: {version.version}, Stage: {status}")
            if tags:
                print("   Tags:")
                for key, value in tags.items():
                    print(f"   - {key}: {value}")
            print(f"   Run ID: {version.run_id}")

        return versions

    except Exception as e:
        print(f"Error listing model versions: {str(e)}")
        raise

# =======================================================================================================================
# Selection des versions du modèle à servir
# Permet une sélection interactive si plusieurs versions sont disponibles, ou utilise la version spécifiée en argument.
# On ajoute la possibilité de spécifier directement une version via les arguments.
# =======================================================================================================================

def select_model_version(versions):
    """
    Let user select which model version to use.

    Args:
        versions: List of model versions
    Returns:
        ModelVersion: Selected version
    """
    if len(versions) == 1:
        print(f"\nOnly one version available. Using version {versions[0].version}")
        return versions[0]

    while True:
        try:
            choice = int(input("\nEnter the number of the version to use: "))
            if 1 <= choice <= len(versions):
                return versions[choice-1]
            print(f"Please enter a number between 1 and {len(versions)}")
        except ValueError:
            print("Please enter a valid number")


# ============================================================================
# Déploiement du modèle
# Utilise la commande mlflow models serve pour déployer le modèle sélectionné.
# ============================================================================

def serve_model(model_uri, port):
    """
    Serve the model using MLflow's CLI command

    Args:
        model_uri: URI of the model to serve
        port: Port number to serve on
    """
    print(f"\nServing model from: {model_uri}")
    print(f"The model will be served on port {port}")

    try:
        # Use mlflow models serve command with --env-manager local
        cmd = [
            "mlflow", "models", "serve",
            "--model-uri", model_uri,
            "--port", str(port),
            "--host", "0.0.0.0",
            "--env-manager", "local"  # Use current environment
        ]

        print(f"Executing command: {' '.join(cmd)}")
        subprocess.run(cmd, check=True)

    except subprocess.CalledProcessError as e:
        print(f"Failed to serve model from {model_uri}")
        print(f"Error: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        raise

def main():
    parser = argparse.ArgumentParser(description='Serve model from MLflow Model Registry')
    parser.add_argument('--tracking_uri', type=str, required=True, help='MLflow tracking URI')
    parser.add_argument('--model_name', type=str, required=True, help='Name of the registered model')
    parser.add_argument('--port', type=int, default=5001, help='Port to serve model on (default: 5001)')
    parser.add_argument('--version', type=int, help='Specific version to serve (optional)')
    args = parser.parse_args()

    try:
        # Set tracking URI
        mlflow.set_tracking_uri(args.tracking_uri)
        print(f"Using tracking URI: {args.tracking_uri}")

        # List and select model version
        versions = list_model_versions(args.model_name)

        if args.version:
            # Find specified version
            version = next((v for v in versions if v.version == str(args.version)), None)
            if version is None:
                raise Exception(f"Version {args.version} not found for model '{args.model_name}'")
        else:
            # Interactive selection
            version = select_model_version(versions)

        # Construct model URI
        # On utilise directement runs:/ car le modèle est à la racine des artefacts du run
        model_uri = f"models:/{args.model_name}/{version.version}"

        # Serve model
        serve_model(model_uri, args.port)

    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()