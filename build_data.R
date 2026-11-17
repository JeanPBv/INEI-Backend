# Prepara los datos de cada año: convierte los .sav en los .rds que lee la API.
# Siempre genera la base de hogar (Vivienda + Sumaria). Si están descargados los
# módulos de persona (200/300/400/500), genera además la base de persona.
# Uso desde back/:
#   Rscript build_data.R              todos los años de AVAILABLE_YEARS
#   Rscript build_data.R 2023 2025    solo esos años
source("config.R")
source("R/utils.R")
source("R/prepare_data.R")
source("R/prepare_person.R")

dir.create(PROCESSED_DIR, showWarnings = FALSE, recursive = TRUE)

args  <- commandArgs(trailingOnly = TRUE)
years <- if (length(args)) as.integer(args) else AVAILABLE_YEARS

for (y in years) {
  message("\n===============================================")
  message("  Preparando ENAHO ", y)
  message("===============================================")
  save_base(prepare_base(y), y)

  # Base de persona: solo si existen los módulos (educación, salud, empleo, padrón).
  if (all(file.exists(roster_sav(y), edu_sav(y), health_sav(y), emp_sav(y)))) {
    message("--- Modulos de persona encontrados: preparando base persona ---")
    save_person_base(prepare_person_base(y), y)
  }
}
message("\nListo. Anios procesados: ", paste(years, collapse = ", "))
