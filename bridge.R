# Devuelve el JSON de cada consulta. Lo usan tanto rpy2 como el modo subprocess.
# Necesita que .CAT exista en el entorno global.
suppressWarnings(suppressMessages(library(jsonlite)))

# Guarda en caché cada base por año y nivel ("hogar" o "persona"); el .rds se lee una vez.
.BASES <- new.env(parent = emptyenv())
get_base <- function(year, kind = "hogar") {
  k <- paste0(kind, "_", year)
  if (is.null(.BASES[[k]])) {
    path <- if (identical(kind, "persona")) person_rds(year) else dataset_rds(year)
    .BASES[[k]] <- readRDS(path)
  }
  .BASES[[k]]
}

# Devuelve el OBJETO R de la consulta (data.frame o lista), sin serializar.
bridge_result <- function(kind, indicator = "", level = "nacional",
                          cross_by = "pobreza", year = REF_YEAR, subgroup = "",
                          cross_value = "") {
  def <- .CAT[[indicator]]
  base_kind <- if (!is.null(def) && !is.null(def$base)) def$base else "hogar"
  switch(kind,
    "catalog"      = catalog_summary(.CAT),
    "levels"       = valid_levels(),
    "estimate"     = estimate(get_base(year, base_kind), def, level),
    "crosstab"     = crosstab(get_base(year, base_kind), def, level, cross_by),
    "distribution" = distribution(get_base(year, base_kind), def, level, subgroup, cross_value),
    stop(paste("Tipo de consulta desconocido:", kind)))
}

bridge_json <- function(...) {
  toJSON(bridge_result(...), dataframe = "rows", auto_unbox = TRUE, na = "null")
}
