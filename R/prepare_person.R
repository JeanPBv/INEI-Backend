# Construye la base a nivel de PERSONA: une el padrón (módulo 200) con Educación (300),
# Salud (400) y Empleo (500), y trae la condición de pobreza desde Sumaria.
# Cada módulo aporta su indicador y su propio factor de expansión.
suppressWarnings(suppressMessages({ library(haven); library(dplyr) }))

prepare_person_base <- function(year = REF_YEAR) {
  key4 <- c("conglome", "vivienda", "hogar", "codperso")   # llave de persona
  key3 <- c("conglome", "vivienda", "hogar")               # llave de hogar

  message("Persona 1/5  Padron de personas (modulo 200)...")
  pad <- read_sav(roster_sav(year))
  per <- tibble(
    conglome = col_chr(pad, "CONGLOME"),
    vivienda = col_chr(pad, "VIVIENDA"),
    hogar    = col_chr(pad, "HOGAR"),
    codperso = col_chr(pad, "CODPERSO"),
    estrato  = col_num(pad, "ESTRATO"),
    dominio  = col_num(pad, "DOMINIO"),
    ubigeo   = col_chr(pad, "UBIGEO"),
    edad     = col_num(pad, "P208A"),
    sexo     = col_num(pad, "P207")
  )

  message("Persona 2/5  Educacion (300): analfabetismo 15+...")
  edu <- read_sav(edu_sav(year))
  edu_std <- tibble(
    conglome = col_chr(edu, "CONGLOME"), vivienda = col_chr(edu, "VIVIENDA"),
    hogar = col_chr(edu, "HOGAR"), codperso = col_chr(edu, "CODPERSO"),
    edad = col_num(edu, "P208A"), p302 = col_num(edu, "P302"),
    factora07 = col_num(edu, "FACTORA07")
  ) %>% mutate(
    # Analfabeto = persona de 15+ que no sabe leer ni escribir (P302 == 2).
    # A quien no se le preguntó P302 (tiene primaria completa o más) se le asume
    # alfabeto, así que entra como 0 en el universo de 15+, no como NA.
    analfabeto = ifelse(edad >= 15, as.integer(!is.na(p302) & p302 == 2), NA_integer_),
    w_edu      = ifelse(edad >= 15, factora07, NA_real_)
  ) %>% select(all_of(key4), analfabeto, w_edu)

  message("Persona 3/5  Salud (400): seguro de salud...")
  sal <- read_sav(health_sav(year))
  seg    <- sapply(sprintf("P419%d", 1:8), function(c) col_num(sal, c))   # 8 tipos de seguro
  tiene  <- apply(seg == 1, 1, function(x) any(x, na.rm = TRUE))
  all_na <- apply(seg, 1, function(x) all(is.na(x)))
  sal_std <- tibble(
    conglome = col_chr(sal, "CONGLOME"), vivienda = col_chr(sal, "VIVIENDA"),
    hogar = col_chr(sal, "HOGAR"), codperso = col_chr(sal, "CODPERSO"),
    # Con seguro = afiliado a cualquiera de los sistemas de salud.
    con_seguro = ifelse(all_na, NA_integer_, as.integer(tiene)),
    w_salud = col_num(sal, "FACTOR07")
  ) %>% select(all_of(key4), con_seguro, w_salud)

  message("Persona 4/5  Empleo (500): tasa de ocupacion (PET)...")
  emp <- read_sav(emp_sav(year))
  emp_std <- tibble(
    conglome = col_chr(emp, "CONGLOME"), vivienda = col_chr(emp, "VIVIENDA"),
    hogar = col_chr(emp, "HOGAR"), codperso = col_chr(emp, "CODPERSO"),
    ocu500 = col_num(emp, "OCU500"), fac500a = col_num(emp, "FAC500A")
  ) %>% mutate(
    # Ocupado (=1) dentro de la población en edad de trabajar (OCU500 definido).
    ocupado  = ifelse(ocu500 %in% c(1, 2, 3, 4), as.integer(ocu500 == 1), NA_integer_),
    w_empleo = ifelse(ocu500 %in% c(1, 2, 3, 4), fac500a, NA_real_)
  ) %>% select(all_of(key4), ocupado, w_empleo)

  message("Persona 5/5  Pobreza (Sumaria) + niveles...")
  sum <- read_sav(summary_sav(year))
  sum_std <- tibble(
    conglome = col_chr(sum, "CONGLOME"), vivienda = col_chr(sum, "VIVIENDA"),
    hogar = col_chr(sum, "HOGAR"), pobreza = col_num(sum, "POBREZA")
  ) %>% mutate(
    pobreza_lbl = recode(pobreza, `1`="Pobre extremo", `2`="Pobre no extremo",
                         `3`="No pobre", .default = NA_character_)
  ) %>% select(all_of(key3), pobreza_lbl)

  base <- per %>%
    left_join(edu_std, by = key4) %>%
    left_join(sal_std, by = key4) %>%
    left_join(emp_std, by = key4) %>%
    left_join(sum_std, by = key3)
  dp <- map_department(base$ubigeo)
  base %>% mutate(
    area       = map_area(estrato),
    region_nat = map_region(dominio),
    dpto_cod   = dp$dpto_cod,
    dpto       = dp$dpto
  )
}

save_person_base <- function(base, year = REF_YEAR) {
  dir.create(PROCESSED_DIR, recursive = TRUE, showWarnings = FALSE)
  saveRDS(base, person_rds(year))
  message("Guardado: ", person_rds(year), "  (", nrow(base), " personas)")
  invisible(person_rds(year))
}
