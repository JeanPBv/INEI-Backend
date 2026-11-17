# Imagen del backend ENAHO: FastAPI (Python) + motor estadístico en R (survey),
# con la base procesada (.rds) horneada adentro. Se construye desde la carpeta back/.

# Partimos de una imagen que ya trae R y descarga paquetes de R como binarios (rápido).
FROM rocker/r-ver:4.4.1

# Python y pip (R ya viene en la imagen base).
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip \
  && rm -rf /var/lib/apt/lists/*

# Paquetes de R: survey/jsonlite/yaml los usa la API en cada consulta.
# (haven y dplyr no hacen falta en runtime, pero los dejamos por si se prepara data.)
RUN install2.r --error --skipinstalled survey jsonlite yaml

WORKDIR /app

# Dependencias de Python (fastapi, uvicorn, pyyaml).
COPY requirements.txt .
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# El código, el catálogo y los datos ya procesados (data/processed/*.rds).
COPY . .

# El motor llama a R por subprocess; en Linux "Rscript" está en el PATH.
ENV RSCRIPT=Rscript
# Puerto: Render/Cloud Run inyectan $PORT; localmente usamos 8000.
ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "python3 -m uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
