# Carga y resume el catálogo de indicadores desde indicators.yaml.
suppressWarnings(suppressMessages(library(yaml)))

load_catalog <- function(path = CATALOG_YAML) {
  yaml::read_yaml(path)$indicators
}

# Versión resumida que usa el endpoint de catálogo del motor.
catalog_summary <- function(cat = load_catalog()) {
  do.call(rbind, lapply(names(cat), function(id) {
    x <- cat[[id]]
    data.frame(
      id          = id,
      title       = x$title %||% NA,
      module      = x$module %||% NA,
      type        = x$type %||% NA,
      weight_unit = x$weight_unit %||% NA,
      format      = x$format %||% NA,
      crossable   = isTRUE(x$crossable),
      stringsAsFactors = FALSE
    )
  }))
}

indicator_def <- function(id, cat = load_catalog()) {
  if (!id %in% names(cat)) return(NULL)
  cat[[id]]
}

`%||%` <- function(a, b) if (is.null(a)) b else a
