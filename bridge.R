# Devuelve el JSON de cada consulta. Lo usan tanto rpy2 como el modo subprocess.
# Necesita que .CAT exista en el entorno global.
suppressWarnings(suppressMessages(library(jsonlite)))

# Guarda en caché la base de cada año: el .rds se lee una sola vez por año.
.BASES <- new.env(parent = emptyenv())
get_base <- function(year) {
  k <- as.character(year)
  if (is.null(.BASES[[k]])) .BASES[[k]] <- readRDS(dataset_rds(year))
  .BASES[[k]]
}

bridge_json <- function(kind, indicator = "", level = "nacional",
                        cross_by = "pobreza", year = REF_YEAR) {
  out <- switch(kind,
    "catalog"  = catalog_summary(.CAT),
    "levels"   = valid_levels(),
    "estimate" = estimate(get_base(year), .CAT[[indicator]], level),
    "crosstab" = crosstab(get_base(year), .CAT[[indicator]], level, cross_by),
    stop(paste("Tipo de consulta desconocido:", kind)))
  toJSON(out, dataframe = "rows", auto_unbox = TRUE, na = "null")
}
