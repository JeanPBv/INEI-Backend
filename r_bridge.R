# Punto de entrada del modo subprocess.
# Uso: Rscript r_bridge.R <kind> [indicator] [level] [cross_by] [year] [subgroup] [cross_value]
source("config.R")
for (f in c("R/utils.R", "R/levels.R", "R/catalog.R", "R/estimator.R")) source(f)
source("bridge.R")

.CAT <- load_catalog()

a <- commandArgs(trailingOnly = TRUE)
g <- function(i, d) if (length(a) >= i && nzchar(a[i])) a[i] else d
year <- suppressWarnings(as.integer(g(5, REF_YEAR)))
if (is.na(year)) year <- REF_YEAR
cat(bridge_json(g(1, ""), g(2, ""), g(3, "nacional"), g(4, "pobreza"), year, g(6, ""), g(7, "")))
