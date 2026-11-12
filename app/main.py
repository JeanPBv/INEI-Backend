# Sirve para: crear la app FastAPI, habilitar CORS y montar los routers.
# El cálculo estadístico vive en R (paquete survey); FastAPI solo expone la API.
#
# Levantar (desde back/):  uvicorn app.main:app --port 8000
# Docs:                    http://127.0.0.1:8000/docs
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import metadata, queries

app = FastAPI(
    title="Servicio estadístico ENAHO",
    version="1.0.0",
    description="Indicadores agregados de la ENAHO con diseño muestral (motor en R/survey).",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

app.include_router(metadata.router)
app.include_router(queries.router)
