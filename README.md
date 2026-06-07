# MLOps – Accidents Severity Pipeline

![Architecture](./assets/docker-compose-architecture.png)


Stack : **API · MLflow · Airflow · Prometheus · Grafana**

---

## Prérequis

- VM Ubuntu avec **16 Go de RAM** et **24 Go de disque** (les services sont gourmands en ressources).
- Docker Compose et Buildx à jour (mis à jour automatiquement via `make install`).

---

## Installation

### Cloner le dépôt

```bash
git clone -b nico_AMAPG https://github.com/sage-flfay/Template_MLOps_accidents.git
```

### Commandes disponibles

```bash
make          # Affiche toutes les commandes disponibles avec leur description
```

---

## Démarrage complet (machine vierge)

### 1. Configurer les credentials DagsHub

```bash
make install
```

La commande s'interrompt pour demander les clés S3 DagsHub. Suivez les instructions affichées. Les clés se trouvent dans DagsHub → **Data → S3 Credentials**.

> Les saisies sont masquées (comme pour un `git push`).

### 2. Finaliser l'installation

```bash
make install
```

Relancer après avoir renseigné les clés : l'installation complète s'exécute.

### 3. Construire les images Docker

```bash
make docker-FullClean-full-build
```

Cette commande :
- Supprime tous les conteneurs et volumes existants
- Demande les identifiants Airflow (entrée vide → `admin` / `admin` par défaut)
- Demande le mode de déploiement : **debug** (HTTP) ou **prod** (HTTPS)
- Construit toutes les images nécessaires
- Affiche un récapitulatif des images créées et l'utilisation des ressources de la VM

### 4. Démarrer les services

```bash
make docker-full-start-WoInitialTrain_fast
```

Démarre tous les services de façon optimisée. Inclut automatiquement un reset complet pour une simulation cohérente.  
Affiche les URLs d'accès aux interfaces web et l'état des ressources.

---

## Commandes courantes

| Commande | Description |
|---|---|
| `make docker-reset-for-full-simu` | Force la regénération de tous les modèles via Airflow (inutile au premier démarrage) |
| `make docker-status` | Affiche l'état des services et les ports actifs |
| `make ubuntu_usage` | Affiche l'utilisation RAM / Disque / CPU par service |

---

## Configuration

### Changer l'année de simulation

Dans l'interface Airflow → **Admin → Variables**, mettre à jour la variable `année`.  
Valeurs autorisées : `2019`, `2020`, `2021`, `2022`, `2023`, `2024`.

### Temps de génération des modèles

- Modèle inexistant : environ **1 min 30 à 2 min**
- Modèle déjà présent : moins d'**1 min** (vérifications uniquement)

---

## Architecture des services

### Docker Compose

| Service | Rôle |
|---|---|
| **Postgres** | Base de données (utilisée aussi par Airflow) |
| **Nginx** | Point d'entrée unique, reverse proxy, rate limiting, redirection HTTP→HTTPS |
| **MLflow** | Tracking des expériences et gestion des modèles |
| **API** | Service de prédiction |
| **train** *(job)* | Entraînement du modèle (éphémère, `on-failure` restart) |

### Monitoring

- **Prometheus** : collecte des métriques applicatives, VM (`node-exporter`) et conteneurs (`cAdvisor`)
- **Grafana** : dashboards de monitoring pour la VM et les conteneurs

---

## Sécurité

- **HTTPS/443** activé en mode prod via Nginx
- **Rate limiting** configuré dans Nginx
- **Droits utilisateur** (non root) dans les conteneurs Docker, permissions `755`
- **Credentials DagsHub** transmis via `export` (non stockés dans `.env`)
- **Secrets GitHub Actions** configurés via `DAGSHUB_ACCESS_KEY_ID` et `DAGSHUB_SECRET_ACCESS_KEY`
- Certificats montés en lecture seule (`:ro`)

---

## Reproductibilité

- Versions d'images Docker fixées (pas de `latest`)
- Dépendances verrouillées via `uv.lock` (`uv sync --frozen`)
- Sélection automatique du meilleur modèle basée sur le KPI **Recall Grave**

---

## Scalabilité

- Le `docker-compose.yml` inclut la directive `replicas` sur le service API.
- Le load balancing est géré automatiquement par Nginx.
- Pour scaler : augmenter `replicas` et supprimer `container_name: prediction_api`.

> Si Kubernetes est installé, il peut réserver les ports 80 et 443. Vérifier avec `make docker_check_port_routage`.

---

## Travaux en cours

- [ ] Échange du modèle MLflow via HTTP (actuellement via volume partagé)
- [ ] Déploiement **Kubernetes**
