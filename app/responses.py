# Valida los parámetros de entrada y da forma a la respuesta (JSON o CSV).
import io
import csv

from fastapi import HTTPException, Response

from app.settings import LEVEL_ALIAS
from app.versions import VERSIONS, DEFAULT_YEAR


# Lleva el nivel pedido a su clave canónica (minúsculas + alias).
def normalize_level(level):
    level = (level or "").strip().lower()
    return LEVEL_ALIAS.get(level, level)


# El año es opcional; si llega, debe tener datos preparados.
def validate_year(year):
    available = sorted(VERSIONS.keys())
    if year is None:
        return DEFAULT_YEAR
    try:
        y = int(year)
    except (TypeError, ValueError):
        raise HTTPException(400, {"error": "invalid_year", "message": f"Year '{year}' is not valid"})
    if y not in available:
        raise HTTPException(404, {"error": "year_unavailable",
                                  "message": f"No prepared data for year {y}",
                                  "years_available": available})
    return y


def _to_csv(rows):
    if not rows:
        return ""
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


# Devuelve {meta, data} o un CSV según el parámetro format.
def respond(rows, m, fmt):
    if (fmt or "json").lower() == "csv":
        return Response(content=_to_csv(rows), media_type="text/csv")
    return {"meta": m, "data": rows}
