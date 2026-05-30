require_env() {
    local var="$1"
    if [ -z "${!var}" ]; then
        echo "Erreur : la variable d'environnement $var est obligatoire. utiliser export $var=valeur"
        exit 1
    fi
}

require_env DAGSHUB_ACCESS_KEY_ID
require_env DAGSHUB_SECRET_ACCESS_KEY


#installer Kubernetes
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

#Pour un mode test, on va utiliser un registry local pour les images Docker
docker run -d --name registry --restart always -p 8081:5000 registry:2

#Il faut autoriser ce registry dans k3
echo -e "mirrors:\n  \"localhost:8081\":\n    endpoint:\n      - \"https://localhost:8081\"" | sudo tee /etc/rancher/k3s/registries.yaml      

#Redémarrer k3
sudo systemctl restart k3s

#Construire les images 
docker build -t accidents_severity-train:1.0 -f src/models/Dockerfile .
docker build -t accidents_severity-mlflow:1.0 -f src/mlflow/Dockerfile .
docker build -t accidents_severity-api:1.0 -f src/api/Dockerfile .
docker build -t accidents_severity-airflow:1.0 -f deployments/airflow/Dockerfile .


# Pousser toutes les images dans le repo local
for img in accidents_severity-mlflow accidents_severity-train accidents_severity-api accidents_severity-airflow; do
  docker tag ${img}:1.0 localhost:8081/${img}:1.0
  docker push localhost:8081/${img}:1.0
done

docker pull postgres:16.13-trixie && docker tag postgres:16.13-trixie localhost:8081/postgres:16.13-trixie && docker push localhost:8081/postgres:16.13-trixie
docker pull busybox:1.36 && docker tag busybox:1.36 localhost:8081/busybox:1.36 && docker push localhost:8081/busybox:1.36
docker pull prom/prometheus:v2.51.2 && docker tag prom/prometheus:v2.51.2 localhost:8081/prom/prometheus:v2.51.2 && docker push localhost:8081/prom/prometheus:v2.51.2
docker pull prom/node-exporter:v1.8.2 && docker tag prom/node-exporter:v1.8.2 localhost:8081/prom/node-exporter:v1.8.2 && docker push localhost:8081/prom/node-exporter:v1.8.2
docker pull grafana/grafana:10.4.2 && docker tag grafana/grafana:10.4.2 localhost:8081/grafana/grafana:10.4.2 && docker push localhost:8081/grafana/grafana:10.4.2


# Générer le certificat auto-signé 
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=localhost"

kubectl create namespace accidents-severity

# Injecter dans Kubernetes
kubectl create secret tls accidents-tls-secret --cert=tls.crt --key=tls.key -n accidents-severity

kubectl create secret generic dagshub-secret --from-literal=DAGSHUB_ACCESS_KEY_ID=<votre_key_id> --from-literal=DAGSHUB_SECRET_ACCESS_KEY=<votre_secret_key> --from-literal=DAGSHUB_USER=sage-flfay  -n accidents-severity

#lancer!
kubectl apply -k k8s/

#Surveiller le démarrage
kubectl get pods -n accidents-severity -w



