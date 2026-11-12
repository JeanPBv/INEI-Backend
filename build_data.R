# Prepara los datos de cada año: convierte los .sav en un .rds + version_<año>.json.
# Uso desde back/:
#   Rscript build_data.R              prepara todos los años de AVAILABLE_YEARS
#   Rscript build_data.R 2023 2025    prepara solo esos años
source("config.R")
source("R/utils.R")
source("R/prepare_data.R")

dir.create(PROCESSED_DIR, showWarnings = FALSE, recursive = TRUE)

args  <- commandArgs(trailingOnly = TRUE)
years <- if (length(args)) as.integer(args) else AVAILABLE_YEARS

for (y in years) {
  message("\n===============================================")
  message("  Preparando ENAHO ", y)
  message("===============================================")
  base <- prepare_base(y)
  save_base(base, y)
}
message("\nListo. Anios procesados: ", paste(years, collapse = ", "))
