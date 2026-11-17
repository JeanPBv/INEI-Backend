# Rutas y constantes que usa el motor R. Aquí no hay cálculo, solo configuración.

# Carpeta back/. Funciona tanto si se ejecuta con Rscript como si se carga con source().
.back_root <- tryCatch({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(f)) normalizePath(file.path(dirname(f)), mustWork = FALSE) else getwd()
}, error = function(e) getwd())
if (!file.exists(file.path(.back_root, "config.R"))) .back_root <- getwd()
BACK_ROOT <- .back_root

# Dónde viven los microdatos crudos. Están fuera del repo porque pesan mucho.
# El orden de carpetas es Datos/<año>/<Módulo>/<archivo>.sav
RAW_DATA_DIR <- "C:/Users/Jean/Desktop/Proyecto INEI/Datos"

# Años que maneja el servicio y año que se usa por defecto.
AVAILABLE_YEARS <- c(2023, 2024, 2025)
REF_YEAR <- 2024

# Rutas a los .sav de cada año. Vivienda es el módulo 01 y Sumaria el módulo 34.
housing_sav <- function(year) file.path(RAW_DATA_DIR, year, "Vivienda", sprintf("Enaho01-%s-100.sav", year))
summary_sav <- function(year) file.path(RAW_DATA_DIR, year, "Sumaria",  sprintf("Sumaria-%s.sav", year))

# Módulos a nivel de persona (opcionales). Cada uno trae su propio factor de expansión.
roster_sav <- function(year) file.path(RAW_DATA_DIR, year, "Sexo",       sprintf("Enaho01-%s-200.sav", year))   # 200 miembros del hogar
edu_sav    <- function(year) file.path(RAW_DATA_DIR, year, "Educación", sprintf("Enaho01A-%s-300.sav", year)) # 300 educación
health_sav <- function(year) file.path(RAW_DATA_DIR, year, "Salud",      sprintf("Enaho01A-%s-400.sav", year))  # 400 salud
emp_sav    <- function(year) file.path(RAW_DATA_DIR, year, "Empleo",     sprintf("Enaho01A-%s-500.sav", year))  # 500 empleo

# Salidas ya procesadas: un .rds y un version_<año>.json por cada año.
PROCESSED_DIR <- file.path(BACK_ROOT, "data", "processed")
dataset_rds  <- function(year) file.path(PROCESSED_DIR, sprintf("enaho_%s_viv_sum.rds", year))
person_rds   <- function(year) file.path(PROCESSED_DIR, sprintf("enaho_%s_persona.rds", year))
version_json <- function(year) file.path(PROCESSED_DIR, sprintf("version_%s.json", year))

CATALOG_YAML <- file.path(BACK_ROOT, "catalog", "indicators.yaml")

# Por encima de este CV la estimación se marca como poco confiable. Es el criterio del INEI.
CV_THRESHOLD <- 15
