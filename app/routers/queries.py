# Endpoints de consulta: estimación de un indicador y su cruce por pobreza.
from fastapi import APIRouter, HTTPException

from app.settings import LEVELS, CV_THRESHOLD
from app.catalog import CATALOG, levels_allowed
from app.engine import engine
from app.versions import meta
from app.responses import normalize_level, validate_year, respond

router = APIRouter()


# Valida indicador + nivel + año y devuelve la clave de nivel y el año resueltos.
def _resolve(indicator, level, year):
    if indicator not in CATALOG:
        raise HTTPException(404, {"error": "unknown_indicator",
                                  "message": f"Indicator '{indicator}' is not in the catalog"})
    y = validate_year(year)
    lv = normalize_level(level)
    if lv not in LEVELS:
        raise HTTPException(400, {"error": "invalid_level",
                                  "message": f"Level '{level}' is not a valid inference level",
                                  "valid_levels": list(LEVELS)})
    allowed = levels_allowed(indicator)
    if lv not in allowed:
        raise HTTPException(422, {"error": "level_not_allowed",
                                  "message": f"Indicator '{indicator}' is not published by {lv}: "
                                             f"reliability (CV) does not meet the threshold at that level.",
                                  "levels_allowed": allowed})
    return lv, y, allowed


@router.get("/estimates")
def estimates(indicator: str = "", level: str = "nacional", year: int = None, format: str = "json"):
    lv, y, allowed = _resolve(indicator, level, year)
    d = CATALOG[indicator]
    data = engine.estimate(indicator, lv, y)
    m = meta({"indicator": indicator, "title": d.get("title"), "level": lv, "year": y,
              "type": d.get("type"), "unit": d.get("format"), "format": d.get("format"),
              "cross": None, "confidence_level": 0.95, "cv_threshold": CV_THRESHOLD,
              "levels_allowed": allowed,
              "note": "Estimates with CV>15% are flagged as unreliable"}, year=y)
    return respond(data, m, format)


@router.get("/crosstabs")
def crosstabs(indicator: str = "", cross_by: str = "pobreza", level: str = "nacional",
              year: int = None, format: str = "json"):
    if indicator in CATALOG and not CATALOG[indicator].get("crossable"):
        raise HTTPException(400, {"error": "indicator_not_crossable",
                                  "message": f"Indicator '{indicator}' does not support crosstabs"})
    lv, y, _ = _resolve(indicator, level, year)
    d = CATALOG[indicator]
    data = engine.crosstab(indicator, lv, cross_by, y)
    m = meta({"indicator": indicator, "title": d.get("title"), "cross_by": cross_by,
              "level": lv, "year": y, "cross": cross_by, "unit": d.get("format"),
              "format": d.get("format"), "confidence_level": 0.95,
              "cv_threshold": CV_THRESHOLD,
              "note": "Estimates with CV>15% are flagged as unreliable"}, year=y)
    return respond(data, m, format)
