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

  message("Persona 2/5  Educacion (300): analfabetismo, asistencia sec. y nivel alcanzado...")
  edu <- read_sav(edu_sav(year))
  # Tasa NETA de asistencia a secundaria (12-16): numerador = población del grupo de
  # edad que asiste a secundaria; denominador = toda la población del grupo. "Asiste
  # al nivel" combina la asistencia actual (P307==1 al nivel P308A==3) con una
  # corrección por el desfase del año escolar: la ENAHO es continua, y en las
  # entrevistas de inicio de año (antes de la matrícula) muchos adolescentes figuran
  # como no matriculados aunque sean estudiantes; a ellos se les cuenta por el nivel
  # al que asistieron el año anterior (P304A). Quien no asiste a secundaria = 0.
  asiste_nivel <- function(p307, p308a, p304a, nivel)
    as.integer((p307 %in% 1 & p308a %in% nivel) | (!(p307 %in% 1) & p304a %in% nivel))
  edu_std <- tibble(
    conglome = col_chr(edu, "CONGLOME"), vivienda = col_chr(edu, "VIVIENDA"),
    hogar = col_chr(edu, "HOGAR"), codperso = col_chr(edu, "CODPERSO"),
    edad = col_num(edu, "P208A"), p302 = col_num(edu, "P302"),
    p304a = col_num(edu, "P304A"), p307 = col_num(edu, "P307"),
    p308a = col_num(edu, "P308A"), p301a = col_num(edu, "P301A"),
    factora07 = col_num(edu, "FACTORA07")
  ) %>% mutate(
    # Analfabeto = persona de 15+ que no sabe leer ni escribir (P302 == 2).
    # A quien no se le preguntó P302 (tiene primaria completa o más) se le asume
    # alfabeto, así que entra como 0 en el universo de 15+, no como NA.
    analfabeto = ifelse(edad >= 15, as.integer(!is.na(p302) & p302 == 2), NA_integer_),
    w_edu      = ifelse(edad >= 15, factora07, NA_real_),
    # Desglose del indicador (sabe / no sabe), coherente con el binario y su universo.
    cat_alfab  = factor(ifelse(is.na(analfabeto), NA_character_,
                        ifelse(analfabeto == 1, "No sabe leer ni escribir", "Sabe leer y escribir")),
                        levels = c("Sabe leer y escribir", "No sabe leer ni escribir")),
    # Tasa neta de asistencia a secundaria (adolescentes 12-16), peso factora07.
    asiste_secundaria = ifelse(edad %in% 12:16, asiste_nivel(p307, p308a, p304a, 3), NA_integer_),
    w_sec             = ifelse(edad %in% 12:16, factora07, NA_real_),
    cat_asis_sec = factor(ifelse(is.na(asiste_secundaria), NA_character_,
                   ifelse(asiste_secundaria == 1, "Asiste a secundaria", "No asiste a secundaria")),
                   levels = c("Asiste a secundaria", "No asiste a secundaria")),
    # Nivel educativo alcanzado (P301A, 15+): umbral directo sobre la variable oficial.
    #   secundaria completa o más = P301A >= 6 ; con educación superior = P301A >= 7.
    # Códigos P301A: 1 sin nivel, 2 inicial, 3-4 primaria inc/comp, 5-6 secundaria
    # inc/comp, 7-8 sup. no univ inc/comp, 9-10 sup. univ inc/comp, 11 posgrado.
    sec_completa = ifelse(edad >= 15, ifelse(is.na(p301a), NA_integer_, as.integer(p301a >= 6)), NA_integer_),
    cat_sec_comp = factor(ifelse(is.na(sec_completa), NA_character_,
                   ifelse(sec_completa == 1, "Con secundaria completa o más", "Sin secundaria completa")),
                   levels = c("Con secundaria completa o más", "Sin secundaria completa")),
    edu_superior = ifelse(edad >= 15, ifelse(is.na(p301a), NA_integer_, as.integer(p301a >= 7)), NA_integer_),
    cat_superior = factor(ifelse(is.na(edu_superior), NA_character_,
                   ifelse(edu_superior == 1, "Con educación superior", "Sin educación superior")),
                   levels = c("Con educación superior", "Sin educación superior"))
  ) %>% select(all_of(key4), analfabeto, w_edu, cat_alfab,
               asiste_secundaria, w_sec, cat_asis_sec,
               sec_completa, cat_sec_comp, edu_superior, cat_superior)

  message("Persona 3/5  Salud (400): seguro de salud y problema cronico...")
  sal <- read_sav(health_sav(year))
  seg    <- sapply(sprintf("P419%d", 1:8), function(c) col_num(sal, c))   # 8 tipos de seguro
  tiene  <- apply(seg == 1, 1, function(x) any(x, na.rm = TRUE))
  all_na <- apply(seg, 1, function(x) all(is.na(x)))
  p401   <- col_num(sal, "P401")   # ¿Padece de alguna enfermedad o malestar cronico? 1=Si 2=No
  sal_std <- tibble(
    conglome = col_chr(sal, "CONGLOME"), vivienda = col_chr(sal, "VIVIENDA"),
    hogar = col_chr(sal, "HOGAR"), codperso = col_chr(sal, "CODPERSO"),
    # Con seguro = afiliado a cualquiera de los sistemas de salud.
    con_seguro = ifelse(all_na, NA_integer_, as.integer(tiene)),
    # Problema de salud cronico = declara padecer alguna enfermedad/malestar cronico.
    cronico = ifelse(is.na(p401), NA_integer_, as.integer(p401 == 1)),
    cat_cronico = factor(ifelse(is.na(p401), NA_character_,
                  ifelse(p401 == 1, "Con problema cronico", "Sin problema cronico")),
                  levels = c("Con problema cronico", "Sin problema cronico")),
    w_salud = col_num(sal, "FACTOR07")
  ) %>% select(all_of(key4), con_seguro, cronico, cat_cronico, w_salud)

  message("Persona 4/5  Empleo (500): tasa de ocupacion (PET) y empleo informal...")
  emp <- read_sav(emp_sav(year))
  emp_std <- tibble(
    conglome = col_chr(emp, "CONGLOME"), vivienda = col_chr(emp, "VIVIENDA"),
    hogar = col_chr(emp, "HOGAR"), codperso = col_chr(emp, "CODPERSO"),
    ocu500 = col_num(emp, "OCU500"), fac500a = col_num(emp, "FAC500A"),
    cat_ocu = col_fct(emp, "OCU500"),  # Ocupado / Desocupado abierto / oculto / No PEA
    p507   = col_num(emp, "P507"),     # categoria ocupacional
    p517b1 = col_num(emp, "P517B1"),   # registro SUNAT del negocio (independientes/empleadores)
    p558a5 = col_num(emp, "P558A5")    # 5 = no afiliado a ningun sistema de pensiones
  ) %>% mutate(
    # Ocupado (=1) dentro de la población en edad de trabajar (OCU500 definido).
    ocupado  = ifelse(ocu500 %in% c(1, 2, 3, 4), as.integer(ocu500 == 1), NA_integer_),
    w_empleo = ifelse(ocu500 %in% c(1, 2, 3, 4), fac500a, NA_real_),
    # Desglose por condición de actividad, solo dentro de la PET (mismo universo).
    cat_ocupacion = droplevels(replace(cat_ocu, !(ocu500 %in% c(1, 2, 3, 4)), NA)),
    # Empleo informal (OIT 17a CIET / INEI), según la categoría ocupacional:
    #  - Trabajador familiar no remunerado (P507==5): siempre informal.
    #  - Empleador/independiente (P507 en 1,2): su empleo es informal salvo que su
    #    unidad productiva esté registrada en SUNAT (P517B1 en {1,2}, persona jurídica
    #    o natural con RUC). Quien no está registrado o no responde (gran parte de los
    #    independientes agrícolas, sin RUC) pertenece al sector informal.
    #  - Asalariados y demás (P507 en 3,4,6,7): informal si no están afiliados a
    #    ningún sistema de pensiones por su empleo (P558A5==5).
    informal_raw = dplyr::case_when(
      p507 == 5             ~ 1L,
      p507 %in% c(1, 2)     ~ as.integer(!(p517b1 %in% c(1, 2))),
      p507 %in% c(3, 4, 6, 7) ~ as.integer(p558a5 %in% 5),
      TRUE                  ~ NA_integer_
    ),
    # Universo del indicador = PEA ocupada (OCU500==1) con categoría clasificable.
    empleo_informal = ifelse(ocu500 == 1, informal_raw, NA_integer_),
    w_informal = ifelse(ocu500 == 1 & !is.na(empleo_informal), fac500a, NA_real_),
    cat_informal = factor(ifelse(is.na(empleo_informal), NA_character_,
                   ifelse(empleo_informal == 1, "Empleo informal", "Empleo formal")),
                   levels = c("Empleo informal", "Empleo formal")),
    # Tasa de desempleo abierto (OIT): desocupados que buscaron trabajo activamente
    # (OCU500==2) sobre la PEA ocupada + desempleo abierto (OCU500 en {1,2}). El
    # desempleo oculto (OCU500==3, desalentados) queda fuera del universo, por el
    # criterio estándar de la OIT. Peso FAC500A.
    desempleo = ifelse(ocu500 %in% c(1, 2), as.integer(ocu500 == 2), NA_integer_),
    w_pea = ifelse(ocu500 %in% c(1, 2), fac500a, NA_real_),
    cat_desempleo = factor(ifelse(is.na(desempleo), NA_character_,
                    ifelse(desempleo == 1, "Desocupado", "Ocupado")),
                    levels = c("Desocupado", "Ocupado"))
  ) %>% select(all_of(key4), ocupado, w_empleo, cat_ocupacion,
               empleo_informal, w_informal, cat_informal,
               desempleo, w_pea, cat_desempleo)

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
