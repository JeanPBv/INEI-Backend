# Carga el catálogo de indicadores (indicators.yaml) y lo expone a la UI.
import yaml

from app.settings import CATALOG_YAML, ALL_LEVELS

with open(CATALOG_YAML, encoding="utf-8") as fh:
    CATALOG = yaml.safe_load(fh)["indicators"]


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
            "levels_allowed": levels_allowed(ind),
            "source_variable": d.get("variable"),
            "official_source": d.get("official_source"),
        })
    return rows
