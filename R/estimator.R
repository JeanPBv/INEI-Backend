# Motor estadístico. Aplica el diseño muestral con el paquete survey y calcula la
# estimación con su error estándar, su CV y su intervalo de confianza al 95%.
suppressWarnings(suppressMessages(library(survey)))
options(survey.lonely.psu = "adjust")

# Diseño muestral con el peso que corresponde: persona usa w_per y hogar usa w_hog.
.design <- function(base, unit) {
  weight <- if (unit == "persona") ~w_per else ~w_hog
  svydesign(ids = ~conglome, strata = ~estrato, weights = weight, data = base, nest = TRUE)
}

# Arma una fila de resultado a partir de la estimación y su error estándar.
.row <- function(level, est, se, type, format) {
  cv    <- ifelse(est != 0, (se / abs(est)) * 100, NA_real_)
  scale <- if (format == "porcentaje") 100 else 1   # una proporción se muestra como porcentaje
  data.frame(
    level          = level,
    estimate       = est * scale,
    standard_error = se  * scale,
    cv             = cv,
    ci_lower       = (est - 1.96 * se) * scale,
    ci_upper       = (est + 1.96 * se) * scale,
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
  dsn  <- .design(base, def$weight_unit)
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
  dsn  <- .design(base, def$weight_unit)
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
