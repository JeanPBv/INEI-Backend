# Endpoints de consulta: estimación de un indicador y su cruce por pobreza.
from fastapi import APIRouter, HTTPException

from app.settings import LEVELS, CV_THRESHOLD
from app.catalog import CATALOG, levels_allowed, UNIVERSE, weight_of
from app.engine import engine
from app.versions import meta, VERSIONS
from app.responses import normalize_level, validate_year, respond

router = APIRouter()


# Ejecuta una llamada al motor R y traduce sus fallos a códigos HTTP claros
# en vez de un 500 genérico (timeout -> 504, sin datos -> 404, resto -> 502).
def _engine(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except TimeoutError as e:
        raise HTTPException(504, {"error": "engine_timeout", "message": str(e)})
    except RuntimeError as e:
        msg = str(e)
        if "No hay datos" in msg or "no data" in msg.lower():
            raise HTTPException(404, {"error": "no_data", "message": msg})
        raise HTTPException(502, {"error": "engine_error", "message": msg})


def _check_format(fmt):
    if (fmt or "json").lower() not in ("json", "csv"):
        raise HTTPException(400, {"error": "invalid_format",
                                  "message": f"Format '{fmt}' no soportado",
                                  "formats": ["json", "csv"]})


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
    _check_format(format)
    lv, y, allowed = _resolve(indicator, level, year)
    d = CATALOG[indicator]
    data = _engine(engine.estimate, indicator, lv, y)
    m = meta({"indicator": indicator, "title": d.get("title"), "level": lv, "year": y,
              "type": d.get("type"), "formula": d.get("type"), "unit": d.get("format"),
              "format": d.get("format"), "weight": weight_of(indicator),
              "universe": UNIVERSE.get(indicator),
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
    _check_format(format)
    lv, y, _ = _resolve(indicator, level, year)
    d = CATALOG[indicator]
    data = _engine(engine.crosstab, indicator, lv, cross_by, y)
    m = meta({"indicator": indicator, "title": d.get("title"), "cross_by": cross_by,
              "level": lv, "year": y, "cross": cross_by, "unit": d.get("format"),
              "format": d.get("format"), "weight": weight_of(indicator),
              "universe": UNIVERSE.get(indicator), "formula": d.get("type"),
              "confidence_level": 0.95, "cv_threshold": CV_THRESHOLD,
              "note": "Estimates with CV>15% are flagged as unreliable"}, year=y)
    return respond(data, m, format)


# Parsea el parámetro `years` ("2021,2022,2023") a una lista de enteros única y
# ordenada. Acepta coma o punto y coma como separador. No valida disponibilidad
# (eso lo hace validate_year después, por año).
MAX_YEARS = 20


def _parse_years(years):
    if not years or not str(years).strip():
        raise HTTPException(400, {"error": "missing_years",
                                  "message": "Parámetro 'years' requerido (p. ej. years=2021,2022,2023)"})
    out = []
    for tok in str(years).replace(";", ",").split(","):
        tok = tok.strip()
        if not tok:
            continue
        try:
            out.append(int(tok))
        except ValueError:
            raise HTTPException(400, {"error": "invalid_year",
                                      "message": f"Año '{tok}' no es un entero válido"})
    out = sorted(set(out))
    if not out:
        raise HTTPException(400, {"error": "missing_years",
                                  "message": "No se indicó ningún año válido en 'years'"})
    if len(out) > MAX_YEARS:
        raise HTTPException(400, {"error": "too_many_years",
                                  "message": f"Máximo {MAX_YEARS} años por consulta",
                                  "max_years": MAX_YEARS})
    return out


# Valida indicador + nivel (sin año) y devuelve la clave de nivel y los niveles
# permitidos. Es la parte de _resolve que no depende del año, para reusarla en
# consultas multianuales donde el año se valida aparte.
def _resolve_level(indicator, level):
    if indicator not in CATALOG:
        raise HTTPException(404, {"error": "unknown_indicator",
                                  "message": f"Indicator '{indicator}' is not in the catalog"})
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
    return lv, allowed


@router.get("/series")
def series(indicator: str = "", level: str = "nacional", years: str = "",
           cross_by: str = "", format: str = "json"):
    """Serie multianual: el mismo cálculo de /estimates (o /crosstabs si se pasa
    cross_by) para varios años. Cada fila lleva su 'year'. Ej.:
    /series?indicator=pobreza_total&level=departamento&years=2021,2022,2023"""
    _check_format(format)
    lv, allowed = _resolve_level(indicator, level)
    d = CATALOG[indicator]
    cross = bool(cross_by)
    if cross and not d.get("crossable"):
        raise HTTPException(400, {"error": "indicator_not_crossable",
                                  "message": f"Indicator '{indicator}' does not support crosstabs"})

    year_list = _parse_years(years)
    for y in year_list:
        validate_year(y)   # 404 year_unavailable si algún año no tiene datos preparados

    rows = []
    for y in year_list:
        part = (_engine(engine.crosstab, indicator, lv, cross_by, y) if cross
                else _engine(engine.estimate, indicator, lv, y))
        for r in (part or []):
            rows.append({"year": y, **r})   # 'year' primero: queda como columna en el CSV

    m = meta({"indicator": indicator, "title": d.get("title"), "level": lv,
              "years": year_list, "year": year_list[-1],
              "data_versions": {str(y): VERSIONS.get(y, {}).get("version") for y in year_list},
              "type": d.get("type"), "formula": d.get("type"),
              "unit": d.get("format"), "format": d.get("format"),
              "cross": cross_by or None, "cross_by": cross_by or None,
              "weight": weight_of(indicator), "universe": UNIVERSE.get(indicator),
              "confidence_level": 0.95, "cv_threshold": CV_THRESHOLD,
              "levels_allowed": allowed,
              "note": "Serie multianual; estimaciones con CV>15% marcadas como referenciales"},
             year=year_list[-1])
    return respond(rows, m, format)


# Condiciones de pobreza válidas para el drill-down de una celda del cruce.
POVERTY_LABELS = {"Pobre extremo", "Pobre no extremo", "No pobre"}


@router.get("/distribution")
def distribution(indicator: str = "", level: str = "nacional", subgroup: str = "",
                 year: int = None, cross_value: str = "", format: str = "json"):
    _check_format(format)
    lv, y, allowed = _resolve(indicator, level, year)
    d = CATALOG[indicator]
    if not d.get("category_var"):
        raise HTTPException(400, {"error": "indicator_not_breakdownable",
                                  "message": f"Indicator '{indicator}' has no category breakdown"})
    # cross_value solo aplica a indicadores cruzables y debe ser una condición válida.
    if cross_value:
        if not d.get("crossable"):
            raise HTTPException(400, {"error": "indicator_not_crossable",
                                      "message": f"Indicator '{indicator}' does not support crosstabs"})
        if cross_value not in POVERTY_LABELS:
            raise HTTPException(400, {"error": "invalid_cross_value",
                                      "message": f"cross_value '{cross_value}' is not a poverty condition",
                                      "cross_values": sorted(POVERTY_LABELS)})
    data = _engine(engine.distribution, indicator, lv, subgroup, y, cross_value)
    m = meta({"indicator": indicator, "title": d.get("title"), "level": lv,
              "subgroup": subgroup or None, "cross_value": cross_value or None,
              "year": y, "breakdown": d.get("category_var"),
              "rest_label": d.get("rest_label"), "weight": weight_of(indicator),
              "universe": UNIVERSE.get(indicator),
              "unit": "porcentaje", "format": "porcentaje", "confidence_level": 0.95,
              "cv_threshold": CV_THRESHOLD,
              "note": "Distribucion sobre las categorias de origen; CV>15% marcado como referencial"},
             year=y)
    return respond(data, m, format)
