# Carga el motor una vez y atiende consultas por stdin (una por línea, en JSON).
# Cada respuesta va prefijada con @@R@@ para que Python la distinga de cualquier
# otra salida. Así la caché de bases de bridge.R sobrevive entre consultas.
source("config.R")
for (f in c("R/utils.R", "R/levels.R", "R/catalog.R", "R/estimator.R")) source(f)
source("bridge.R")
suppressWarnings(suppressMessages(library(jsonlite)))

.CAT <- load_catalog()
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

emit <- function(obj) {
  cat("@@R@@", toJSON(obj, dataframe = "rows", auto_unbox = TRUE, na = "null"), "\n", sep = "")
  flush(stdout())
}

con <- file("stdin", open = "r", blocking = TRUE)
repeat {
  line <- readLines(con, n = 1, warn = FALSE)
  if (length(line) == 0) break          # EOF: el proceso Python cerró stdin
  line <- trimws(line)
  if (!nzchar(line)) next
  req <- tryCatch(fromJSON(line), error = function(e) NULL)
  if (is.null(req)) next
  id <- req$id %||% 0L
  res <- tryCatch(
    list(id = id, ok = TRUE,
         data = bridge_result(req$kind %||% "", req$indicator %||% "",
                              req$level %||% "nacional", req$cross_by %||% "pobreza",
                              as.integer(req$year %||% REF_YEAR), req$subgroup %||% "")),
    error = function(e) list(id = id, ok = FALSE, error = conditionMessage(e)))
  emit(res)
}
