# Puente a R, en tres modos de más a menos rápido: rpy2 (en proceso), un worker
# Rscript de larga vida (r_worker.R), o un Rscript por consulta como último recurso.
# Encima, una caché en memoria porque la data no cambia dentro de un año.
import os
import json
import time
import queue
import threading
import subprocess

# Raíz del motor R (back/), donde viven config.R, bridge.R, r_bridge.R y r_worker.R.
R_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RSCRIPT = os.environ.get("RSCRIPT", r"C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe")
# Tiempo máximo por consulta al motor R, configurable por entorno.
R_TIMEOUT = int(os.environ.get("R_TIMEOUT", "60"))
# Máximo de resultados cacheados (combinaciones indicador/nivel/año/subámbito).
CACHE_MAX = int(os.environ.get("R_CACHE_MAX", "4000"))
MARK = "@@R@@"   # prefijo de las respuestas del worker


def _rstr(s):
    return '"' + s.replace("\\", "/").replace('"', '\\"') + '"'


class WorkerDead(RuntimeError):
    """El proceso worker R terminó; conviene caer a subprocess."""


# Proceso Rscript de larga vida. Una consulta a la vez (lock); un hilo lee stdout
# y empuja las respuestas @@R@@ a una cola, emparejadas por id.
class RWorker:
    def __init__(self):
        self.proc = subprocess.Popen(
            [RSCRIPT, "r_worker.R"], cwd=R_ROOT,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", bufsize=1,
        )
        self._lock = threading.Lock()
        self._q = queue.Queue()
        self._id = 0
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        try:
            for line in self.proc.stdout:
                if line.startswith(MARK):
                    self._q.put(line[len(MARK):].strip())
        except Exception:
            pass

    def call(self, req, timeout):
        with self._lock:
            if self.proc.poll() is not None:
                raise WorkerDead("el worker R no está activo")
            self._id += 1
            rid = self._id
            payload = dict(req, id=rid)
            try:
                self.proc.stdin.write(json.dumps(payload) + "\n")
                self.proc.stdin.flush()
            except (BrokenPipeError, OSError):
                raise WorkerDead("no se pudo escribir al worker R")
            deadline = time.monotonic() + timeout
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"La consulta al motor R excedió {timeout}s")
                try:
                    line = self._q.get(timeout=remaining)
                except queue.Empty:
                    raise TimeoutError(f"La consulta al motor R excedió {timeout}s")
                resp = json.loads(line)
                if resp.get("id") != rid:
                    continue   # respuesta de una consulta anterior (p. ej. tras timeout)
                if not resp.get("ok"):
                    raise RuntimeError(resp.get("error") or "error desconocido en R")
                return resp.get("data")


class REngine:
    def __init__(self):
        self.mode = "subprocess"
        self.detail = ""
        self.worker = None
        self._cache = {}
        self._cache_lock = threading.Lock()
        self._try_rpy2()
        if self.mode != "rpy2":
            self._try_worker()

    # Carga el motor R en el mismo proceso; si falla, deja otro modo.
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

    # Arranca el worker persistente y lo prueba; si falla, queda en subprocess.
    def _try_worker(self):
        try:
            w = RWorker()
            w.call({"kind": "levels"}, timeout=R_TIMEOUT)   # smoke test
            self.worker = w
            self.mode = "worker"
            self.detail = "worker R persistente"
        except Exception as e:
            self.worker = None
            self.mode = "subprocess"
            self.detail = f"subprocess por consulta (worker no disponible: {type(e).__name__})"

    def _run(self, kind, indicator="", level="nacional", cross_by="pobreza", year=None,
             subgroup="", cross_value=""):
        y = "" if year is None else str(int(year))
        key = (kind, indicator, level, cross_by, y, subgroup, cross_value)
        with self._cache_lock:
            if key in self._cache:
                return self._cache[key]
        result = self._exec(kind, indicator, level, cross_by, y, subgroup, cross_value)
        with self._cache_lock:
            if len(self._cache) < CACHE_MAX:
                self._cache[key] = result
        return result

    def _exec(self, kind, indicator, level, cross_by, y, subgroup, cross_value=""):
        if self.mode == "rpy2":
            fn = self._robjects.globalenv["bridge_json"]
            args = [kind, indicator, level, cross_by]
            if y:
                args.append(int(y))
                if subgroup or cross_value:
                    args.append(subgroup)
                if cross_value:
                    args.append(cross_value)
            return json.loads(str(fn(*args)[0]))

        if self.mode == "worker" and self.worker:
            req = {"kind": kind, "indicator": indicator, "level": level,
                   "cross_by": cross_by, "subgroup": subgroup, "cross_value": cross_value}
            if y:
                req["year"] = int(y)
            try:
                return self.worker.call(req, R_TIMEOUT)
            except WorkerDead:
                self.mode = "subprocess"   # el worker murió: cae a subprocess
                self.detail = "subprocess por consulta (worker terminó)"

        # Último recurso: un Rscript por consulta.
        try:
            p = subprocess.run(
                [RSCRIPT, "r_bridge.R", kind, indicator, level, cross_by, y, subgroup, cross_value],
                cwd=R_ROOT, capture_output=True, text=True, encoding="utf-8",
                timeout=R_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            raise TimeoutError(f"La consulta al motor R excedió el límite de {R_TIMEOUT}s")
        except FileNotFoundError:
            raise RuntimeError(f"No se encontró el ejecutable de R (RSCRIPT={RSCRIPT})")
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "error desconocido en R")
        try:
            return json.loads(p.stdout)
        except json.JSONDecodeError:
            raise RuntimeError("El motor R no devolvió un JSON válido: " + (p.stdout[:200] or "(vacío)"))

    def estimate(self, indicator, level, year=None):
        return self._run("estimate", indicator, level, year=year)

    def crosstab(self, indicator, level, cross_by="pobreza", year=None):
        return self._run("crosstab", indicator, level, cross_by, year=year)

    # Desglose por etiquetas de un indicador, en un subámbito opcional (drill-down).
    # cross_value restringe además por condición de pobreza (drill-down del cruce).
    def distribution(self, indicator, level, subgroup="", year=None, cross_value=""):
        return self._run("distribution", indicator, level, subgroup=subgroup, year=year,
                         cross_value=cross_value)


engine = REngine()
