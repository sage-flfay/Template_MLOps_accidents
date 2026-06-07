#!/bin/bash

# RAPPEL: si pas déjà fait, pour rendre ce script exécutable, tapez dans le terminal : chmod +x setup_daemon_json.sh

echo ""
echo "==== CONFIGURER LE FICHIER DAEMON.JSON POUR LE SERVICE CADVISOR ===="
echo "==== QUI PERMET DE VISUALISER LES CONTAINERS SYSTEMES VIA GRAFANA DASHBOARD ===="
echo ""

# Chemin du fichier
DAEMON_FILE="/etc/docker/daemon.json"

# Créer le dossier docker au cas où
sudo mkdir -p /etc/docker

FILE="/etc/docker/daemon.json"
CONFIG='{"metrics-addr":"0.0.0.0:9323","experimental":true}'

# Vérifier si le fichier existe
if [ -f "$FILE" ]; then
    # Vérifier si la configuration est déjà présente
    if grep -q "metrics-addr" "$FILE"; then
        echo "La configuration Docker metrics est déjà présente. Aucun changement nécessaire."
    else
        # Ici, on est plus prudent : on prévient que le JSON doit être fusionné manuellement
        echo "ATTENTION : Le fichier $FILE existe déjà."
        echo "Il ne contient pas la configuration 'metrics-addr'."
        echo "Pour éviter d'écraser vos autres paramètres, veuillez ajouter manuellement ceci dans $FILE :"
        echo "----------------------------------------------------------------------------------"
        echo "$CONFIG"
        echo "----------------------------------------------------------------------------------"
        echo "Puis redémarrez Docker avec : sudo systemctl restart docker"
        echo "On stoppe volontairement le make pour faire la correction manuelle "
        echo "Après l'update, refaire impérativement la commande make ..."
        # On termine le script avec un code d'erreur (1) pour arrêter le Makefile
        exit 1
    fi
        # Ici, on est plus prudent : on prévient que le JSON doit être fusionné manuellement
        # car un simple echo écraserait le reste.
        echo "ATTENTION : Le fichier $FILE existe mais ne contient pas la config metrics."
        echo "Veuillez ajouter manuellement : $CONFIG"
    fi
else
    # Le fichier n'existe pas, on le crée en toute sécurité
    echo "Création du fichier $FILE..."
    echo "$CONFIG" | sudo tee "$FILE" > /dev/null
    sudo systemctl restart docker
    echo "Docker redémarré avec la nouvelle configuration."
fi

# Redémarrer Docker pour prendre en compte les changements
echo "Redémarrage de Docker..."
sudo systemctl restart docker

echo "✅  Configuration daemon.json appliquée avec succès."
echo " ----------------------------------------------------------------------------------"
echo ""
