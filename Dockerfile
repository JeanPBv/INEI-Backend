# Imagen del backend ENAHO: FastAPI (Python) + motor estadístico en R (survey),
# con la base procesada (.rds) horneada adentro. Se construye desde la carpeta back/.

# Partimos de una imagen que ya trae R y descarga paquetes de R como binarios (rápido).
FROM rocker/r-ver:4.4.1

# Python, pip y venv (R ya viene en la imagen base).
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv \
  && rm -rf /var/lib/apt/lists/*

# Paquetes de R que la API usa en cada consulta: survey/jsonlite/yaml y, además,
# haven/dplyr porque R/utils.R los carga al sourcearse el motor en runtime.
RUN install2.r --error --skipinstalled survey jsonlite yaml haven dplyr

WORKDIR /app

# Dependencias de Python en un entorno aislado (como el .venv local).
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# El código, el catálogo y los datos ya procesados (data/processed/*.rds).
COPY . .

# El motor llama a R por subprocess; en Linux "Rscript" está en el PATH.
ENV RSCRIPT=Rscript
# Puerto: Render/Cloud Run inyectan $PORT; localmente usamos 8000.
ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "python3 -m uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
