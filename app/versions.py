# Lee las versiones por año (.rds preparados) y construye el bloque meta.
import os
import glob
import json
from datetime import datetime

from app.settings import PROCESSED_DIR
from app.engine import engine
from app.catalog import CATALOG_VERSION


# Un version_<año>.json por año; version.json (sin año) se acepta por compatibilidad.
def _load_versions():
    versions = {}
    for path in glob.glob(os.path.join(PROCESSED_DIR, "version_*.json")):
        try:
            with open(path, encoding="utf-8") as fh:
                v = json.load(fh)
            versions[int(v.get("anio"))] = v
        except Exception:
            pass
    legacy = os.path.join(PROCESSED_DIR, "version.json")
    if os.path.exists(legacy):
        try:
            with open(legacy, encoding="utf-8") as fh:
                v = json.load(fh)
            versions.setdefault(int(v.get("anio")), v)
        except Exception:
            pass
    return versions


VERSIONS = _load_versions()
DEFAULT_YEAR = max(VERSIONS) if VERSIONS else 2024


# Años con datos preparados, del más reciente al más antiguo.
def years_available():
    rows = []
    for y in sorted(VERSIONS.keys(), reverse=True):
        v = VERSIONS[y]
        rows.append({
            "year": y,
            "version": v.get("version"),
            "modules": ["vivienda", "sumaria"],
            "households": v.get("n_hogares"),
            "clusters": v.get("n_conglome"),
            "status": "validado",
        })
    return rows


# Bloque meta común a toda respuesta (fuente, año, versión de datos, motor R).
def meta(extra=None, year=None):
    y = year if year is not None else DEFAULT_YEAR
    v = VERSIONS.get(y, {})
    base = {
        "source": "ENAHO", "year": y,
        "data_version": v.get("version"), "engine": engine.detail,
        "catalog_version": CATALOG_VERSION,
        "data_generated": v.get("generado"),   # fecha de procesamiento de la base
        "generated": datetime.now().isoformat(timespec="seconds"),
    }
    if extra:
        base.update(extra)
    return base
