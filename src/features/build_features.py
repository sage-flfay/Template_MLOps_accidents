import pandas as pd
import sys

# Centralisation du mapping CATV
# On mappe les codes officiels (1, 2,...) vers les catégories d'entraînement
CATV_MAPPING = {
    # Non motorisé
    1: 0, 60: 0,
    # Motorisé et léger < 50cm3
    2: 1, 3: 1, 30: 1, 35: 1, 41: 1, 50: 1, 80: 1,
    # Motorisé et léger > 50cm3 et < 125cm3
    31: 2, 32: 2, 36: 2, 42: 2,
    # Motorisé et léger > 125cm3
    33: 3, 34: 3, 43: 3,
    # Véhicules < 3.5T
    7: 4, 10: 4,
    # PL
    13: 5, 14: 5, 15: 5,
    # Transport en commun (TC)
    37: 6, 38: 6, 39: 6, 40: 6,
    # Engins spéciaux
    16: 7, 17: 7, 20: 7, 21: 7,
    # Autre
    0: 8, 99: 8, 4: 8, 5: 8, 6: 8, 8: 8, 9: 8, 11: 8, 12: 8, 18: 8, 19: 8,
}

# Centralisation du mapping ATM
# On mappe les codes officiels (1, 2,...) vers les catégories d'entraînement
ATM_MAPPING = {
    # Bonne condition météorologique
    1: 0, 7: 0, 8:0,
    # Pluie (adhérence réduite)
    2: 1, 3: 1,
    # Brouillar (visibilité réduite)
    5: 2,
    # Neige, grêle (conditions hivernales)
    4: 3,
    # Vent, Tempête (instabilité véhicule)
    6: 4,
    # Autre
    9: 5, -1: 5,
}

# Centralisation du mapping GRAV
# On mappe les codes officiels (1, 2,...) vers les catégories d'entraînement
GRAV_MAPPING = {
    # Personne indemne / blessé léger
    1: 0, 4: 0,
    # Personne tuée, blessé hospitalisé
    2: 1, 3: 1,
}

# Centralisation de la Corse
CORSE_MAPPING = {"2A": 201, "2B": 202}

def catv_remapping(value):
    """Transforme le code CATV brut en catégorie simplifiée (0-8)."""
    # Si la valeur n'est pas dans le mapping, on met 8 (Inconnu) par défaut
    try:
        # On convertit en float d'abord (gère '3.0'), puis en int
        return CATV_MAPPING.get(int(float(value)), 8)
    except (ValueError, TypeError):
        # Si c'est un NaN, None ou une chaîne vide, on renvoie la catégorie "Autre" (8)
        return 8

def atm_remapping(value):
    """Transforme le code ATM brut en catégorie simplifiée (0-5)."""
    # Si la valeur n'est pas dans le mapping, on met 5 (Inconnu) par défaut
    try:
        # On convertit en float d'abord (gère '3.0'), puis en int
        return ATM_MAPPING.get(int(float(value)), 5)
    except (ValueError, TypeError):
        # Si c'est un NaN, None ou une chaîne vide, on renvoie la catégorie "Autre" (5)
        return 5

def grav_remapping(value):
    """
    Transforme le code GRAV brut en catégorie simplifiée (0-1).
    Valeur obligatoirement présente (sinon c'est une mauvaise gestion des NaN)
    """
    try:
        # On convertit en float d'abord (gère '3.0'), puis en int
        val = int(float(value))

        # On vérifie si la valeur est dans le mapping métier
        if val not in GRAV_MAPPING:
            raise ValueError(f"Code GRAV inconnu détecté : {val}")

        return GRAV_MAPPING[val]

    except (ValueError, TypeError) as e:
        print(f"\n[ERREUR CRITIQUE] Valeur cible 'grav'. Détail: {e}")
        print(f"Valeur brute reçue : '{value}'")
        print("DEBUGGER AVANT DE RE-ENTRAINER LE MODELE.")
        # Sortie du script avec code erreur
        sys.exit(1)


def apply_feature_remapping(df):
    """
    Applique toutes les transformations sur un DataFrame (utilisé par make_dataset).
    """

    # On travaille sur une copie de df. Ainsi, on est sûr que df n'est pas modifié
    df = df.copy()

    if 'catv' in df.columns:
        df['catv'] = df['catv'].apply(catv_remapping)

    if 'atm' in df.columns:
        df['atm'] = df['atm'].apply(atm_remapping)

    if 'grav' in df.columns:
        df['grav'] = df['grav'].apply(grav_remapping)

    if 'dep' in df.columns:
        df['dep'] = df['dep'].astype(str).replace(CORSE_MAPPING)

    if 'com' in df.columns:
        df['com'] = df['com'].astype(str).replace(CORSE_MAPPING)

    return df
