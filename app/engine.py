# Puente a R. Usa rpy2 (en proceso) y, si no está, cae a subprocess
# (Rscript r_bridge.R). Ambos modos reutilizan el mismo motor R (back/R/*.R).
import os
import json
import subprocess

# Raíz del motor R (back/), donde viven config.R, bridge.R y r_bridge.R.
R_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RSCRIPT = os.environ.get("RSCRIPT", r"C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe")


def _rstr(s):
    return '"' + s.replace("\\", "/").replace('"', '\\"') + '"'


class REngine:
    def __init__(self):
        self.mode = "subprocess"
        self.detail = ""
        self._try_rpy2()

    # Carga el motor R en el mismo proceso; si falla, deja el modo subprocess.
    def _try_rpy2(self):
        try:
            from rpy2 import robjects
            r = robjects.r
            r(f"setwd({_rstr(R_ROOT)})")
            for f in ("config.R", "R/utils.R", "R/levels.R", "R/catalog.R",
                      "R/estimator.R", "bridge.R"):
                r(f"source({_rstr(f)})")
            r(".CAT  <- load_catalog()")
            self._robjects = robjects
            self.mode = "rpy2"
            self.detail = "rpy2 (en proceso)"
        except Exception as e:
            self.detail = f"subprocess (rpy2 no disponible: {type(e).__name__})"
            self.mode = "subprocess"

    def _run(self, kind, indicator="", level="nacional", cross_by="pobreza", year=None):
        y = "" if year is None else str(int(year))
        if self.mode == "rpy2":
            fn = self._robjects.globalenv["bridge_json"]
            args = [kind, indicator, level, cross_by]
            if y:
                args.append(int(y))
            return json.loads(str(fn(*args)[0]))
        p = subprocess.run(
            [RSCRIPT, "r_bridge.R", kind, indicator, level, cross_by, y],
            cwd=R_ROOT, capture_output=True, text=True, encoding="utf-8",
        )
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "error desconocido en R")
        return json.loads(p.stdout)

    def estimate(self, indicator, level, year=None):
        return self._run("estimate", indicator, level, year=year)

    def crosstab(self, indicator, level, cross_by="pobreza", year=None):
        return self._run("crosstab", indicator, level, cross_by, year=year)


engine = REngine()
