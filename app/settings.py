# Rutas base y constantes del servicio (sin lógica).
import os

APP_DIR = os.path.dirname(os.path.abspath(__file__))   # back/app
BACK_DIR = os.path.dirname(APP_DIR)                     # back (raíz del motor R)

CATALOG_YAML = os.path.join(BACK_DIR, "catalog", "indicators.yaml")
PROCESSED_DIR = os.path.join(BACK_DIR, "data", "processed")

# CV por encima de este umbral marca la estimación como no confiable (criterio INEI).
CV_THRESHOLD = 15

# Niveles de inferencia válidos (clave -> etiqueta mostrada al usuario).
LEVELS = {
    "nacional": "Nacional",
    "area": "Area urbano/rural",
    "region_natural": "Region natural",
    "departamento": "Departamento",
}

ALL_LEVELS = list(LEVELS)

# Alias aceptados en la petición -> clave canónica de LEVELS.
LEVEL_ALIAS = {
    "nacional": "nacional",
    "area": "area", "urbano_rural": "area",
    "region": "region_natural", "region_natural": "region_natural", "region_nat": "region_natural",
    "departamento": "departamento", "dpto": "departamento", "depto": "departamento",
}
