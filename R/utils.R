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

# Lee una variable categórica con las ETIQUETAS reales embebidas en el .sav y la
# devuelve como factor. Si tiene más de `top` categorías, agrupa las menos
# frecuentes (por peso de expansión) en "Otros". Las categorías y su orden se
# fijan a nivel global, así el desglose es consistente en todo subámbito
# (Urbano, Rural, cada departamento...). Los NA se conservan como NA.
col_fct <- function(df, name, weight = NULL, top = 5L, otros = "Otros") {
  hit <- names(df)[toupper(names(df)) == toupper(name)]
  if (!length(hit)) stop(sprintf("La columna '%s' no existe en el modulo", name))
  x    <- df[[hit[1]]]
  code <- as.numeric(haven::zap_labels(x))
  labs <- attr(x, "labels")   # vector con nombres = etiqueta, valores = código
  lbl  <- if (is.null(labs)) as.character(code)
          else { nm <- names(labs)[match(code, labs)]
                 ifelse(is.na(nm), as.character(code), nm) }
  lbl[is.na(code)] <- NA_character_

  w   <- if (is.null(weight)) rep(1, length(code)) else weight
  agg <- tapply(w, lbl, sum, na.rm = TRUE)            # peso total por etiqueta
  agg <- sort(agg, decreasing = TRUE)
  keep <- names(agg)[seq_len(min(top, length(agg)))]  # top-N por peso

  out <- ifelse(is.na(lbl), NA_character_,
         ifelse(lbl %in% keep, lbl, otros))
  lv  <- keep
  if (any(out == otros, na.rm = TRUE)) lv <- c(lv, otros)
  factor(out, levels = lv)
}

# Factor para indicadores "sí/no" cuya condición es la UNIÓN de ciertos códigos
# (p. ej. agua por red pública = P110 en {1,2,3}). Muestra cada código que DEFINE
# el indicador con su etiqueta real, y agrupa todo lo demás en una sola categoría
# `rest`. Así las categorías del indicador suman exactamente el valor del titular,
# y `rest` es el "no" (el total sigue cuadrando a 100%). Los NA se conservan.
col_fct_sel <- function(df, name, keep_codes, rest = "Resto") {
  hit <- names(df)[toupper(names(df)) == toupper(name)]
  if (!length(hit)) stop(sprintf("La columna '%s' no existe en el modulo", name))
  x    <- df[[hit[1]]]
  code <- as.numeric(haven::zap_labels(x))
  labs <- attr(x, "labels")
  lab_of <- function(cd) {
    if (is.null(labs)) return(as.character(cd))
    nm <- names(labs)[match(cd, labs)]
    ifelse(is.na(nm), as.character(cd), nm)
  }
  keep_lbls <- vapply(keep_codes, lab_of, character(1))   # etiquetas de los códigos del indicador
  out <- ifelse(is.na(code), NA_character_,
         ifelse(code %in% keep_codes, lab_of(code), rest))
  factor(out, levels = c(keep_lbls, rest))                # el "resto" siempre al final
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
