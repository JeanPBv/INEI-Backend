# Niveles de inferencia válidos de la ENAHO. Pedir otro, como distrito, no está permitido.

# Cada nivel apunta a la columna por la que se agrupa en la base.
# Cuando el grupo es NULL, la cifra es una sola para todo el país.
LEVELS <- list(
  nacional        = list(group = NULL,          label = "Nacional"),
  area            = list(group = "area",        label = "Area urbano/rural"),
  region_natural  = list(group = "region_nat",  label = "Region natural"),
  departamento    = list(group = "dpto",        label = "Departamento")
)

# Nombres alternativos que se aceptan en la petición.
LEVEL_ALIAS <- c(
  nacional = "nacional",
  area = "area", "area_urbano_rural" = "area", urbano_rural = "area",
  region_natural = "region_natural", region = "region_natural", region_nat = "region_natural",
  departamento = "departamento", dpto = "departamento", depto = "departamento"
)

normalize_level <- function(level) {
  a <- tolower(trimws(level))
  if (a %in% names(LEVEL_ALIAS)) unname(LEVEL_ALIAS[a]) else a
}

is_valid_level <- function(level) {
  normalize_level(level) %in% names(LEVELS)
}

valid_levels <- function() {
  data.frame(
    level = names(LEVELS),
    label = vapply(LEVELS, function(x) x$label, character(1)),
    row.names = NULL, stringsAsFactors = FALSE
  )
}
