# Carga el catálogo de indicadores (indicators.yaml) y lo expone a la UI.
import yaml

from app.settings import CATALOG_YAML, ALL_LEVELS

with open(CATALOG_YAML, encoding="utf-8") as fh:
    _DOC = yaml.safe_load(fh)
CATALOG = _DOC["indicators"]
CATALOG_VERSION = _DOC.get("version")

# Universo (población de referencia) de cada indicador, para trazabilidad.
UNIVERSE = {
    "pobreza_total":       "Personas (población total)",
    "pobreza_extrema":     "Personas (población total)",
    "gasto_pc":            "Personas (población total)",
    "agua_red_publica":    "Hogares",
    "desague_red_publica": "Hogares",
    "electricidad":        "Hogares",
    "total_hogares":       "Hogares",
    "analfabetismo":       "Personas de 15 y más años",
    "seguro_salud":        "Personas (población total)",
    "tasa_ocupacion":      "Población en edad de trabajar (14 y más)",
    "asistencia_secundaria": "Adolescentes de 12 a 16 años",
    "nivel_secundaria_completa": "Personas de 15 y más años",
    "nivel_superior":        "Personas de 15 y más años",
    "problema_salud_cronico": "Personas (población total)",
    "empleo_informal":       "PEA ocupada",
    "tasa_desempleo":        "PEA (ocupados + desempleo abierto)",
}


# Ponderador (columna de peso) que usa el indicador, igual criterio que el motor R.
def weight_of(indicator):
    d = CATALOG.get(indicator, {})
    if d.get("weight_var"):
        return d["weight_var"]
    return "w_per" if d.get("weight_unit") == "persona" else "w_hog"


# Niveles de inferencia publicables para un indicador (por defecto, todos).
def levels_allowed(indicator):
    return CATALOG[indicator].get("levels_allowed", ALL_LEVELS)


# Catálogo listo para el front. 'unit' = formato (porcentaje|soles|conteo);
# 'weight_unit' = hogar|persona.
def public_catalog():
    rows = []
    for ind, d in CATALOG.items():
        rows.append({
            "id": ind,
            "code": ind,
            "title": d.get("title"),
            "name": d.get("title"),
            "definition": d.get("description"),
            "module": d.get("module"),
            "type": d.get("type"),
            "unit": d.get("format"),
            "weight_unit": d.get("weight_unit"),
            "format": d.get("format"),
            "crossable": bool(d.get("crossable", False)),
            "has_breakdown": bool(d.get("category_var")),
            "rest_label": d.get("rest_label"),
            "universe": UNIVERSE.get(ind),
            "weight": weight_of(ind),
            "levels_allowed": levels_allowed(ind),
            "source_variable": d.get("variable"),
            "official_source": d.get("official_source"),
        })
    return rows
