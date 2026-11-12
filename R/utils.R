# Funciones de apoyo: leer columnas de los .sav y traducir códigos geográficos.
suppressWarnings(suppressMessages({
  library(haven)
  library(dplyr)
}))

# Busca una columna sin importar mayúsculas y la devuelve como número limpio,
# sin las etiquetas que trae haven.
col_num <- function(df, name) {
  hit <- names(df)[toupper(names(df)) == toupper(name)]
  if (!length(hit)) stop(sprintf("La columna '%s' no existe en el modulo", name))
  as.numeric(haven::zap_labels(df[[hit[1]]]))
}

col_chr <- function(df, name) {
  hit <- names(df)[toupper(names(df)) == toupper(name)]
  if (!length(hit)) stop(sprintf("La columna '%s' no existe en el modulo", name))
  as.character(df[[hit[1]]])
}

# Los 25 departamentos del Perú, indexados por los dos primeros dígitos del UBIGEO.
DEPARTMENTS <- c(
  "01"="Amazonas","02"="Ancash","03"="Apurimac","04"="Arequipa","05"="Ayacucho",
  "06"="Cajamarca","07"="Callao","08"="Cusco","09"="Huancavelica","10"="Huanuco",
  "11"="Ica","12"="Junin","13"="La Libertad","14"="Lambayeque","15"="Lima",
  "16"="Loreto","17"="Madre de Dios","18"="Moquegua","19"="Pasco","20"="Piura",
  "21"="Puno","22"="San Martin","23"="Tacna","24"="Tumbes","25"="Ucayali"
)

# Área urbano/rural a partir del ESTRATO: del 1 al 5 es urbano y del 6 al 8 rural.
map_area <- function(estrato) {
  ifelse(estrato %in% 1:5, "urbano",
  ifelse(estrato %in% 6:8, "rural", NA_character_))
}

# Región natural a partir del DOMINIO. Lima Metropolitana se cuenta dentro de la Costa.
map_region <- function(dominio) {
  ifelse(dominio %in% c(1,2,3,8), "costa",
  ifelse(dominio %in% c(4,5,6),   "sierra",
  ifelse(dominio == 7,            "selva", NA_character_)))
}

# Departamento a partir del UBIGEO: devuelve su código de dos dígitos y su nombre.
map_department <- function(ubigeo) {
  u <- sprintf("%06s", trimws(as.character(ubigeo)))
  u <- gsub(" ", "0", u)
  cod <- substr(u, 1, 2)
  nombre <- unname(DEPARTMENTS[cod])
  data.frame(dpto_cod = cod, dpto = ifelse(is.na(nombre), cod, nombre),
             stringsAsFactors = FALSE)
}
