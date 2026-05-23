#!/bin/bash

# RAPPEL: si pas déjà fait, pour rendre ce script exécutable, tapez dans le terminal : chmod +x setup_dagshub_key.sh

echo "=== CONFIGURATION USER ET KEY DAGSHUB ==="

BASHRC="$HOME/.bashrc"

# 1. Vérification / Demande pour DAGSHUB_USER
if grep -q "DAGSHUB_USER" "$BASHRC"; then
    echo "✅ DAGSHUB_USER est déjà présent dans le ~/.bashrc"
else
    # Correction de la coquille textuelle (sage-flfay)
    echo "Cliquer sur enter si le user est sage-flfay"
    read -p "Entrez votre DAGSHUB_USER [sage-flfay] : " user_id

    user_id=${user_id:-sage-flfay}

    if [ -n "$user_id" ]; then
        # impératif d'utiliser les "..." dans echo "..." pour que le sh interprète le contenu
        echo "export DAGSHUB_USER=\"$user_id\"" >> "$BASHRC"
        echo ""
        echo "✏️ DAGSHUB_USER ($user_id) ajouté au ~/.bashrc"
    fi
fi

# 2. Vérification / Demande pour DAGSHUB_ACCESS_KEY_ID
if grep -q "DAGSHUB_S3_ACCESS_KEY_ID" "$BASHRC"; then
    echo "✅ DAGSHUB_S3_ACCESS_KEY_ID est déjà présent dans le ~/.bashrc"
else
    key_id=""
    while [ -z "$key_id" ]; do
        # "-s" à read pour masquer la clé pendant la saisie
        read -sp "Entrez votre DAGSHUB_S3_ACCESS_KEY_ID (obligatoire - affichage masqué) : " key_id
        if [ -z "$key_id" ]; then
            echo "⚠️ La clé ne peut pas être vide. Veuillez recommencer."
        fi
    done

    echo "export DAGSHUB_S3_ACCESS_KEY_ID=\"$key_id\"" >> "$BASHRC"
    echo ""
    echo "✏️ DAGSHUB_S3_ACCESS_KEY_ID ajouté au ~/.bashrc"
fi

# 3. Vérification / Demande pour DAGSHUB_SECRET_ACCESS_KEY
if grep -q "DAGSHUB_S3_SECRET_ACCESS_KEY" "$BASHRC"; then
    echo "✅ DAGSHUB_S3_SECRET_ACCESS_KEY est déjà présent dans le ~/.bashrc"
else
    secret_id=""
    while [ -z "$secret_id" ]; do
        read -sp "Entrez votre DAGSHUB_S3_SECRET_ACCESS_KEY (obligatoire - affichage masqué) : " secret_id
        if [ -z "$secret_id" ]; then
            echo "⚠️ La clé ne peut pas être vide. Veuillez recommencer."
        fi
    done

    # CORRECTION ICI : Utilisation de $secret_id au lieu de $secret_key
    echo "export DAGSHUB_S3_SECRET_ACCESS_KEY=\"$secret_id\"" >> "$BASHRC"
    echo ""
    echo "✏️ DAGSHUB_S3_SECRET_ACCESS_KEY ajouté au ~/.bashrc"
fi

echo "======== CONFIGURATION TERMINÉE ======="
echo "🚀 Vos dagshub user et clés sont désormais enregistrées dans ~/.bashrc !"
echo ""
echo ""
echo "======== 💥💥💥 RÉACTIVATION DE L'ENVIRONNEMENT 💥💥💥 ========"
echo "🚨🚨🚨 💥💥💥 LANCER LA COMMANDE SUIVANTE SUR LE TERMINAL POUR ACTIVATION : source ~/.bashrc"
echo ""
