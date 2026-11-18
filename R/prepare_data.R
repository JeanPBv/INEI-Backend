# Lee los microdatos crudos, estandariza las variables y une Vivienda con Sumaria.
# Deja listo back/data/processed/enaho_<año>_viv_sum.rds y su version_<año>.json.
suppressWarnings(suppressMessages({ library(haven); library(dplyr); library(jsonlite) }))

prepare_base <- function(year = REF_YEAR) {
  message("1/5  Leyendo microdatos crudos del anio ", year, "...")
  viv <- read_sav(housing_sav(year))
  sum <- read_sav(summary_sav(year))
  message(sprintf("     Vivienda: %d filas x %d cols", nrow(viv), ncol(viv)))
  message(sprintf("     Sumaria : %d filas x %d cols", nrow(sum), ncol(sum)))

  # Sumaria es la base del análisis. Sus hogares son los de Vivienda con RESULT 1 o 2,
  # es decir entrevistas completas e incompletas, que también cuentan en las cifras oficiales.
  message("2/5  Estandarizando el modulo Vivienda...")
  na_si <- function(cond, base_na) ifelse(is.na(base_na), NA_integer_, as.integer(cond))
  viv_std <- tibble(
    conglome = col_chr(viv, "CONGLOME"),
    vivienda = col_chr(viv, "VIVIENDA"),
    hogar    = col_chr(viv, "HOGAR"),
    result   = col_num(viv, "RESULT"),
    p110     = col_num(viv, "P110"),
    p111a    = col_num(viv, "P111A"),
    p1121    = col_num(viv, "P1121"),
    # Desglose = las categorías que DEFINEN el indicador (red pública) + "Sin red
    # pública" como resto. Las del indicador suman el valor del titular.
    cat_agua    = col_fct_sel(viv, "P110",  c(1, 2, 3), rest = "Sin red pública"),  # agua: {1,2,3} = red
    cat_desague = col_fct_sel(viv, "P111A", c(1, 2),    rest = "Sin red pública")   # desagüe: {1,2} = red
  ) %>%
    filter(result %in% c(1, 2)) %>%
    mutate(
      agua_red      = na_si(p110  %in% c(1, 2, 3), p110),   # acceso a agua por red pública
      desague_red   = na_si(p111a %in% c(1, 2),    p111a),  # desagüe por red pública
      electricidad  = na_si(p1121 == 1,            p1121),  # alumbrado eléctrico
      unos          = 1L,                                    # sirve para contar hogares
      # Desglose del indicador binario de electricidad (sí/no, con sus etiquetas).
      cat_electric  = factor(ifelse(is.na(p1121), NA_character_,
                             ifelse(p1121 == 1, "Con alumbrado eléctrico", "Sin alumbrado eléctrico")),
                             levels = c("Con alumbrado eléctrico", "Sin alumbrado eléctrico"))
    )

  message("3/5  Estandarizando el modulo Sumaria...")
  sum_std <- tibble(
    conglome = col_chr(sum, "CONGLOME"),
    vivienda = col_chr(sum, "VIVIENDA"),
    hogar    = col_chr(sum, "HOGAR"),
    estrato  = col_num(sum, "ESTRATO"),
    dominio  = col_num(sum, "DOMINIO"),
    ubigeo   = col_chr(sum, "UBIGEO"),
    factor07 = col_num(sum, "FACTOR07"),
    mieperho = col_num(sum, "MIEPERHO"),
    pobreza  = col_num(sum, "POBREZA"),
    gashog2d = col_num(sum, "GASHOG2D")
  ) %>%
    mutate(
      # Conserva los faltantes: un hogar sin dato de pobreza NO debe contar como
      # "no pobre". (NA %in% c(1,2) daría FALSE/0; por eso el guardado explícito.)
      pobre_total   = ifelse(is.na(pobreza), NA_integer_, as.integer(pobreza %in% c(1, 2))),
      pobre_extremo = ifelse(is.na(pobreza), NA_integer_, as.integer(pobreza == 1)),
      gpc_mensual   = (gashog2d / mieperho) / 12,   # gasto per cápita mensual, en soles corrientes
      pobreza_lbl   = recode(pobreza, `1`="Pobre extremo", `2`="Pobre no extremo",
                             `3`="No pobre", .default = NA_character_),
      # Desglose de pobreza: las 3 categorías oficiales, en orden.
      cat_pobreza   = factor(pobreza_lbl,
                             levels = c("Pobre extremo", "Pobre no extremo", "No pobre"))
    )

  message("4/5  Uniendo los modulos por conglome, vivienda y hogar...")
  n_viv <- nrow(viv_std); n_sum <- nrow(sum_std)
  base <- left_join(sum_std, viv_std, by = c("conglome", "vivienda", "hogar"))

  # Después de la unión no debería quedar ningún hogar duplicado.
  dups <- base %>% count(conglome, vivienda, hogar) %>% filter(n > 1) %>% nrow()
  if (dups > 0) stop(sprintf("ERROR: %d hogares duplicados tras la union", dups))
  sin_viv <- sum(is.na(base$result))
  message(sprintf("     Sumaria=%d  Vivienda(realizadas)=%d  ->  Base=%d  (hogares sin match en Vivienda: %d)",
                  n_sum, n_viv, nrow(base), sin_viv))
  for (v in c("agua_red","desague_red","electricidad"))
    message(sprintf("       NA en %-13s: %d", v, sum(is.na(base[[v]]))))

  message("5/5  Derivando niveles y pesos...")
  dp <- map_department(base$ubigeo)
  base <- base %>%
    mutate(
      area       = map_area(estrato),
      region_nat = map_region(dominio),
      dpto_cod   = dp$dpto_cod,
      dpto       = dp$dpto,
      w_hog      = factor07,                 # peso para indicadores a nivel de hogar
      w_per      = factor07 * mieperho       # peso para indicadores a nivel de persona
    )

  na_crit <- sapply(base[c("estrato","conglome","w_hog","w_per","area","region_nat")],
                    function(x) sum(is.na(x)))
  if (any(na_crit > 0)) {
    warning("Hay valores faltantes en variables criticas:\n",
            paste(names(na_crit), na_crit, sep="=", collapse="  "))
  }

  base
}

save_base <- function(base, year = REF_YEAR) {
  dir.create(PROCESSED_DIR, recursive = TRUE, showWarnings = FALSE)
  saveRDS(base, dataset_rds(year))
  ver <- list(
    dataset      = paste0("ENAHO ", year, " - Modulos 01 (Vivienda) y 34 (Sumaria)"),
    anio         = year,
    generado     = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    n_hogares    = nrow(base),
    n_conglome   = length(unique(base$conglome)),
    version      = paste0("enaho", year, "-vivsum-", format(Sys.Date(), "%Y%m%d")),
    fuente       = c(basename(housing_sav(year)), basename(summary_sav(year)))
  )
  write_json(ver, version_json(year), auto_unbox = TRUE, pretty = TRUE)
  message("Guardado: ", dataset_rds(year))
  message("Version : ", ver$version)
  invisible(ver)
}
