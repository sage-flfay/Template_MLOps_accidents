#installer Kubernetes
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

#Pour un mode test, on va utiliser un registry local pour les images Docker
docker run -d --name registry --restart always -p 5000:5000 registry:2

#Il faut autoriser ce registry dans k3
echo -e "mirrors:\n  \"localhost:5000\":\n    endpoint:\n      - \"https://localhost:5000\"" | sudo tee /etc/rancher/k3s/registries.yaml      

#Redémarrer k3
sudo systemctl restart k3s
 
#Construire les images et les pousser dans le repo local
docker build -t accidents_severity-train:1.0 -f src/models/Dockerfile .
docker tag accidents_severity-train:1.0  localhost:5000/accidents_severity-train:1.0
docker push localhost:5000/accidents_severity-train:1.0

docker build -t accidents_severity-mlflow:1.0 -f src/mlflow/Dockerfile .
docker tag accidents_severity-mlflow:1.0 localhost:5000/accidents_severity-mlflow:1.0
docker push localhost:5000/accidents_severity-mlflow:1.0

docker build -t accidents_severity-api:1.0 -f src/api/Dockerfile .
docker tag accidents_severity-api:1.0    localhost:5000/accidents_severity-api:1.0
docker push localhost:5000/accidents_severity-api:1.0   

#pousser les images requises dans le repo local
docker pull busybox:1.36
docker tag busybox:1.36 localhost:5000/busybox:1.36
docker push localhost:5000/busybox:1.36

docker pull postgres:16.13-trixie
docker tag postgres:16.13-trixie localhost:5000/postgres:16.13-trixie
docker push localhost:5000/postgres:16.13-trixie

#lancer!
kubectl apply -k k8s/



