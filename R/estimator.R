# Motor estadístico. Aplica el diseño muestral con el paquete survey y calcula la
# estimación con su error estándar, su CV y su intervalo de confianza al 95%.
suppressWarnings(suppressMessages(library(survey)))
options(survey.lonely.psu = "adjust")

# Columna de peso del indicador. `weight_var` (si existe) la nombra directamente;
# si no, cae al peso de hogar o persona de la base principal.
.weight_var <- function(def) {
  if (!is.null(def$weight_var)) def$weight_var
  else if (identical(def$weight_unit, "persona")) "w_per"
  else "w_hog"
}

# Diseño muestral con el peso del indicador. Se descartan las filas sin peso, que es
# como cada módulo de persona define su universo (p. ej. PET para empleo).
.design <- function(base, def) {
  wv <- .weight_var(def)
  base <- base[!is.na(base[[wv]]), ]
  svydesign(ids = ~conglome, strata = ~estrato,
            weights = as.formula(paste0("~", wv)), data = base, nest = TRUE)
}

# Arma una fila de resultado a partir de la estimación y su error estándar.
# El CV queda indefinido (NA) cuando la estimación es 0. Para proporciones, el IC
# normal (±1.96 EE) puede salirse de [0,100]; se acota a ese rango.
.row <- function(level, est, se, type, format) {
  cv    <- if (is.na(est) || est == 0) NA_real_ else (se / abs(est)) * 100
  scale <- if (format == "porcentaje") 100 else 1   # una proporción se muestra como porcentaje
  lo    <- (est - 1.96 * se) * scale
  hi    <- (est + 1.96 * se) * scale
  if (format == "porcentaje") { lo <- max(lo, 0); hi <- min(hi, 100) }  # proporción ∈ [0,100]
  data.frame(
    level          = level,
    estimate       = est * scale,
    standard_error = se  * scale,
    cv             = cv,
    ci_lower       = lo,
    ci_upper       = hi,
    unreliable     = isTRUE(cv > CV_THRESHOLD),
    stringsAsFactors = FALSE
  )
}

# Estima un indicador en un nivel. Lo nacional sale de svymean o svytotal; lo desagregado
# usa svyby, que da el error estándar propio de cada subgrupo.
estimate <- function(base, def, level_key) {
  lvl  <- LEVELS[[level_key]]
  yvar <- def$variable
  f    <- as.formula(paste0("~", yvar))
  dsn  <- .design(base, def)
  FUN  <- if (def$type == "total") svytotal else svymean

  if (is.null(lvl$group)) {
    est <- FUN(f, dsn, na.rm = TRUE)
    out <- .row("Nacional", as.numeric(coef(est)[1]), as.numeric(SE(est)[1]), def$type, def$format)
    out$sample_size <- sum(!is.na(base[[yvar]]))
    out$population  <- NA_real_
  } else {
    g  <- lvl$group
    gf <- as.formula(paste0("~", g))
    by <- svyby(f, gf, dsn, FUN, na.rm = TRUE, vartype = "se", keep.names = FALSE)
    subgroups <- by[[1]]; ests <- by[[2]]; ses <- by[[3]]
    out <- do.call(rbind, Map(function(nv, e, s)
      .row(as.character(nv), e, s, def$type, def$format),
      subgroups, ests, ses))
    nm <- tapply(!is.na(base[[yvar]]), base[[g]], sum)
    out$sample_size <- as.integer(nm[as.character(out$level)])
    out$population  <- NA_real_
  }
  rownames(out) <- NULL
  out
}

# Cruza un indicador cruzable por condición de pobreza, y por el nivel si no es nacional.
crosstab <- function(base, def, level_key = "nacional", cross_by = "pobreza") {
  if (!isTRUE(def$crossable)) stop("El indicador no es cruzable")
  if (cross_by != "pobreza") stop("Por ahora solo se puede cruzar por pobreza")

  base$pobreza_lbl <- factor(base$pobreza_lbl,
                             levels = c("Pobre extremo","Pobre no extremo","No pobre"))
  yvar <- def$variable
  f    <- as.formula(paste0("~", yvar))
  dsn  <- .design(base, def)
  lvl  <- LEVELS[[level_key]]

  groups <- c("pobreza_lbl", lvl$group)
  gf <- as.formula(paste0("~", paste(groups, collapse = " + ")))
  by <- svyby(f, gf, dsn, svymean, na.rm = TRUE, vartype = "se", keep.names = FALSE)

  k   <- length(groups)
  est <- by[[k + 1]]; se <- by[[k + 2]]
  out <- do.call(rbind, lapply(seq_len(nrow(by)), function(i) {
    # as.character columna por columna, para no colapsar los factores a su código.
    label <- paste(vapply(seq_len(k), function(j) as.character(by[i, j]), character(1)),
                   collapse = " / ")
    .row(label, est[i], se[i], def$type, def$format)
  }))

  # Tamaño muestral de cada celda, para que no salga en cero.
  cell_key <- apply(base[, groups, drop = FALSE], 1,
                    function(r) paste(as.character(r), collapse = " / "))
  cnt <- tapply(!is.na(base[[yvar]]), cell_key, sum)
  out$sample_size <- as.integer(cnt[out$level])
  out$population  <- NA_real_

  rownames(out) <- NULL
  out
}

# Desglose por etiquetas: estima la proporción de cada categoría de la variable
# categórica del indicador, con su error estándar / CV / IC 95%. Si se pasa un
# subámbito (p. ej. nivel "area" + subgroup "urbano"), restringe el cálculo a él;
# así el drill-down "clic en Urbano -> categorías dentro de Urbano" es una sola
# estimación con el mismo diseño muestral y el peso propio del indicador.
# cross_value (opcional) restringe además por condición de pobreza, para el
# drill-down de una celda del cruce (p. ej. "No pobre / Urbano" -> categorías
# dentro de los hogares no pobres del área urbana).
distribution <- function(base, def, level_key = "nacional", subgroup = "", cross_value = "") {
  catvar <- def$category_var
  if (is.null(catvar)) stop("El indicador no tiene desglose por categorias")
  lvl <- LEVELS[[level_key]]

  # Restringe al subámbito pedido dentro de la columna del nivel (área/región/dpto).
  if (!is.null(lvl$group) && nzchar(subgroup)) {
    col  <- as.character(base[[lvl$group]])
    base <- base[!is.na(col) & tolower(col) == tolower(subgroup), ]
  }

  # Restringe por condición de pobreza (celda del cruce), si se pide.
  if (nzchar(cross_value)) {
    pc   <- as.character(base$pobreza_lbl)
    base <- base[!is.na(pc) & pc == cross_value, ]
  }

  wv   <- .weight_var(def)
  base <- base[!is.na(base[[wv]]) & !is.na(base[[catvar]]), ]
  if (!nrow(base)) stop("No hay datos para ese subambito")
  base[[catvar]] <- droplevels(factor(base[[catvar]]))

  dsn <- svydesign(ids = ~conglome, strata = ~estrato,
                   weights = as.formula(paste0("~", wv)), data = base, nest = TRUE)
  est <- svymean(as.formula(paste0("~", catvar)), dsn, na.rm = TRUE)
  cf  <- coef(est); se <- SE(est)
  cats <- sub(paste0("^", catvar), "", names(cf))   # svymean antepone el nombre de la variable

  out <- do.call(rbind, Map(function(lab, e, s)
    .row(lab, e, s, "proporcion", "porcentaje"), cats, cf, se))
  nm  <- table(base[[catvar]])
  out$sample_size <- as.integer(nm[cats])
  out$population  <- NA_real_
  rownames(out) <- NULL
  out
}
