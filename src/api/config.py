# src/api/config.py
import os
from pathlib import Path

# --- CONFIGURATION DES CHEMINS ---
# Définition dynamique du chemin
# On remonte de src/api/ vers la racine pour trouver /models
MODEL_DIR = Path(os.path.dirname(__file__)).parent.parent / "models"
MODEL_PATH = MODEL_DIR / "model.joblib"

# --- LISTE DES FEATURES (ORDRE INDISPENSABLE POUR LE MODÈLE) ---
FEATURES = [
    "place",
    "catu",
    "sexe",
    "secu1",
    "year_acc",
    "victim_age",
    "catv",
    "obsm",
    "motor",
    "catr",
    "circ",
    "surf",
    "situ",
    "vma",
    "jour",
    "mois",
    "lum",
    "dep",
    "com",
    "agg_",
    "int",
    "atm",
    "col",
    "lat",
    "long",
    "hour",
    "nb_victim",
    "nb_vehicules",
]

# --- LABELS POUR L'INTERFACE UTILISATEUR ---
FEATURE_LABELS = [
    # "Lieu de l’accident",
    "Place de l’accidenté",
    "Catégorie d’usager",
    "Sexe de l’usager",
    "Dispositif de sécurité",
    "Année de l’accident",
    "Âge de la victime",
    "Catégorie du véhicule",
    "Obstacle mobile",
    "Motorisation",
    "Catégorie de route",
    "Régime de circulation",
    "État de la surface",
    "Situation de l’accident",
    "Vitesse maximale autorisée",
    "Jour du mois",
    "Mois",
    "Luminosité",
    "Département",
    "Code commune",
    "Agglomération",
    "Type d’intersection",
    "Conditions atmosphériques",
    "Type de collision",
    "Latitude",
    "Longitude",
    "Heure",
    "Nombre de victimes",
    "Nombre de véhicules",
]

# --- DICTIONNAIRE DES CHOIX (BAAC) ---
CHOICES = {
    # Place dans le véhicule (occupants)
    # Réf. BAAC 2017 – "PLACE DANS LE VÉHICULE"
    "place": {
        1: "Conducteur",
        2: "Passager avant droit",
        3: "Passager arrière gauche",
        4: "Passager arrière centre",
        5: "Passager arrière droit",
        6: "Autre place (minibus/TC/etc.)",
        9: "Sans objet / Non applicable",
    },
    # Catégorie d’usager
    # Réf. BAAC 2017 – "CATÉGORIE D’USAGER"
    "catu": {
        1: "Conducteur",
        2: "Passager",
        3: "Piéton",
    },
    # Sexe
    # Réf. BAAC 2017 – "SEXE"
    "sexe": {
        1: "Masculin",
        2: "Féminin",
    },
    # Équipement de sécurité - utilisation (1er item)
    # Réf. BAAC 2017 – "ÉQUIPEMENT DE SÉCURITÉ - UTILISATION"
    # (Dans le BAAC, plusieurs items existent ;
    # ici on expose le plus courant pour un unique champ 'secu1')
    "secu1": {
        0: "Aucun équipement",
        1: "Ceinture",
        2: "Casque",
        3: "Dispositif enfant",
        4: "Gilet airbag",
        5: "Gants",
        6: "Gilet haute visibilité",
        7: "Autre",
        9: "Non renseigné",
    },
    ###
    # Année de l'accident : valeur à entrer
    ###
    # Age de la victime : valeur à entrer
    ###
    # Catégorie de véhicule (sous-ensemble utile pour l’UI)
    # Réf. BAAC – “CATEGORIE DE VEHICULE”
    # (format BAAC 2007/2017 ; liste complète très longue)
    # -> N’hésite pas à l’étendre si besoin pour ton jeu.
    "catv": {
        1: "Bicyclette",
        2: "Cyclomoteur < 50 cm³",
        3: "Voiturette / quadricycle léger",
        7: "VL seul",
        10: "VU seul (≤ 3,5 t)",
        13: "PL (> 3,5 t) + remorque",
        14: "PL seul (> 7,5 t)",
        15: "Tracteur routier",
        16: "Tracteur routier + semi-remorque",
        17: "Transport en commun (autobus/autocar)",
        30: "Scooter < 50 cm³",
        31: "Motocyclette > 50 et ≤ 125 cm³",
        32: "Scooter > 50 et ≤ 125 cm³",
        33: "Motocyclette > 125 cm³",
        34: "Scooter > 125 cm³",
        60: "Autre véhicule",
        99: "Inconnu / Non renseigné",
    },
    # Obstacle mobile heurté
    # Réf. BAAC 2017 – "OBSTACLE MOBILE HEURTÉ"
    "obsm": {
        0: "Aucun",
        1: "Piéton",
        2: "Véhicule",
        4: "Véhicule sur rail",
        5: "Animal domestique",
        6: "Animal sauvage",
        9: "Autre",
    },
    # Type de motorisation
    # Réf. BAAC 2017 – "TYPE DE MOTORISATION"
    "motor": {
        1: "Thermique (essence/diesel)",
        2: "Hybride non rechargeable",
        3: "Hybride rechargeable",
        4: "Électrique",
        5: "GPL / GNV / autre gaz",
        9: "Non renseigné",
    },
    # Catégorie administrative de la route
    # Réf. BAAC 2017 – "CATÉGORIE ADMINISTRATIVE"
    "catr": {
        1: "Autoroute",
        2: "Route nationale (ou territoriale)",
        3: "Route départementale (ou provinciale)",
        4: "Voie communale",
        5: "Hors réseau public",
        6: "Parc de stationnement ouvert à la circulation publique",
        9: "Autre",
    },
    # Régime de circulation
    # Réf. BAAC 2017 – "RÉGIME DE CIRCULATION"
    "circ": {
        1: "À sens unique",
        2: "Bidirectionnelle",
        3: "À chaussées séparées",
        4: "Avec voies d’affectation variable",
    },
    # État de surface
    # Réf. BAAC 2017 – "ÉTAT DE SURFACE"
    "surf": {
        1: "Normale",
        2: "Mouillée",
        3: "Flaques",
        4: "Inondée",
        5: "Enneigée",
        6: "Boue",
        7: "Verglacée",
        8: "Corps gras - Huile",
    },
    # Situation de l’accident
    # Réf. BAAC 2017 – "SITUATION DE L’ACCIDENT"
    "situ": {
        1: "Sur chaussée",
        2: "Sur bande d’arrêt d’urgence",
        3: "Sur accotement",
        4: "Sur trottoir",
        5: "Sur piste/bande cyclable",
        6: "Sur autre voie (BAU, bande médiane...)",
        7: "Sur terre-plein central / refuge",
        8: "Sur parking / aire",
        9: "Autre",
    },
    ###
    # Vitesse maximale autorisée: valeur à entrer
    ###
    # Jour du mois: valeur à entrer
    ###
    # mois de l'année: valeur à entrer
    ###
    # Lumière
    # Réf. BAAC 2017 – "LUMIÈRE"
    "lum": {
        1: "Plein jour",
        2: "Crépuscule ou aube",
        3: "Nuit sans éclairage public",
        4: "Nuit avec éclairage public non allumé",
        5: "Nuit avec éclairage public allumé",
    },
    ###
    # Numéro de département: valeur à entrer
    ###
    # Code de la commune: valeur à entrer
    ###
    # Localisation (en / hors agglomération)
    # Réf. BAAC 2017 – "LOCALISATION" (en/hors agglo)
    "agg_": {
        1: "Hors agglomération",
        2: "En agglomération",
    },
    # Intersection
    # Réf. BAAC 2017 – "INTERSECTION"
    "int": {
        1: "Hors intersection",
        2: "Intersection en X",
        3: "Intersection en T",
        4: "Intersection en Y",
        5: "Carrefour à plus de 4 branches",
        6: "Giratoire",
        7: "Place",
        8: "Passage à niveau",
        9: "Autre",
    },
    # Conditions atmosphériques
    # Réf. BAAC 2017 – "CONDITION ATMOSPHÉRIQUE"
    "atm": {
        1: "Normales",
        2: "Pluie légère",
        3: "Pluie forte",
        4: "Neige - grêle",
        5: "Brouillard - fumée",
        6: "Vent fort - tempête",
        7: "Temps éblouissant",
        8: "Temps couvert",
        9: "Autre",
    },
    # Type de collision
    # Réf. BAAC (schéma usuel open data) – ordre/labels usuels
    "col": {
        1: "Deux véhicules - frontale",
        2: "Deux véhicules - par l’arrière",
        3: "Deux véhicules - par le côté",
        4: "Trois véhicules et plus – en chaîne",
        5: "Trois véhicules et plus – collisions multiples",
        6: "Autre collision",
        7: "Sans collision",
    },
    ###
    # Latitude: valeur à entrer
    ###
    # Longitude: valeur à entrer
    ###
    # Heure: valeur à entrer
    ###
    # Nombre de victimes: valeur à entrer
    ###
    # Nombre de véhicules
}

# --- DONNÉES DE TEST (SAMPLE) ---
SAMPLE = [
    1,
    1,
    1,
    0,  # il y avait 8 sur secu1 et ça n'existe pas
    2021,
    46.0,
    2,
    2,
    1,
    1,  # il y avait 7 sur catr et ça n'existe pas
    2,
    1,
    1,
    90.0,
    18,
    11,
    1,
    45,
    45072,
    1,
    1,
    1,
    1,
    47.964066,
    1.927586,
    17,
    2,
    2,
]
