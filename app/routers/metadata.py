# Endpoints de catálogo y metadatos (lo que la UI lee al cargar).
from fastapi import APIRouter

from app.settings import LEVELS
from app.catalog import public_catalog
from app.versions import meta, years_available

router = APIRouter()


@router.get("/indicators")
def indicators():
    return {"meta": meta(), "data": public_catalog()}


@router.get("/levels")
def levels():
    return {"meta": meta(), "data": [{"level": k, "label": v} for k, v in LEVELS.items()]}


@router.get("/years")
def years():
    return {"meta": meta(), "data": years_available()}
