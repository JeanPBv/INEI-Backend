# Back — API del servicio ENAHO

API en FastAPI que expone indicadores de la ENAHO con diseño muestral (error estándar, CV e
intervalo de confianza al 95 %). FastAPI solo publica los endpoints; los cálculos los hace R con
el paquete `survey`, que es quien sabe trabajar con factores de expansión, estratos y conglomerados.

El servicio trabaja con **varios años** (2023, 2024 y 2025). Cada año es una base independiente, y
la consulta elige el año con el parámetro `year`. Agregar un año más es un paso de datos, no de
código (ver "Agregar un año nuevo").

Corre en `http://127.0.0.1:8000`. La documentación interactiva queda en `http://127.0.0.1:8000/docs`.

## Puesta en marcha paso a paso

De cero a la API corriendo. Cada punto tiene su detalle en las secciones siguientes.

1. **Consigue el proyecto.** Clónalo con Git (o descarga el `.zip` desde GitHub y descomprímelo), y
   abre una terminal dentro de la carpeta:

   ```bash
   git clone https://github.com/JeanPBv/INEI-Backend.git
   cd INEI-Backend
   ```

   Esa carpeta `INEI-Backend` es el backend; en esta guía la llamamos `back/`. Todos los comandos se
   corren **desde ahí**. (Si lo bajaste como `.zip`, descomprímelo y entra a esa carpeta.)

2. Instala **R + RStudio** y los **paquetes de R** → *Instalación · Paquetes de R*.
3. Crea y activa el **entorno de Python** e instala las dependencias → *Instalación · Entorno virtual de Python*.
4. Descarga los **microdatos de la ENAHO** (módulos 01 y 34 de cada año, en formato SPSS) y colócalos en sus carpetas → *Los datos · Descargar y colocar los `.sav`*.
5. Genera las bases **`.rds`** con `Rscript build_data.R` → *Los datos · Generar el `.rds`*.
6. **Levanta la API** con `uvicorn app.main:app` → *Levantar la API*.

Si un compañero ya te pasó la carpeta `data/processed/` con los `.rds` generados, copia esa carpeta
tal cual y sáltate los pasos 4 y 5.

## Requisitos

| Herramienta | Versión | Para qué |
|---|---|---|
| Python | 3.10 o superior | Correr la API (FastAPI + Uvicorn) |
| R | 4.x (probado con 4.6) | Motor de cálculo (`survey`) |
| Paquetes de Python | `requirements.txt` | fastapi, uvicorn, pyyaml |
| Paquetes de R | `survey`, `jsonlite`, `yaml` (+ `haven`, `dplyr` para preparar datos) | motor y lectura de `.sav` |

La API llama a R por detrás. En Windows, R suele instalarse en
`C:\Program Files\R\R-4.x.x\bin\x64\Rscript.exe`. Si ese `Rscript` no está en el `PATH`, no hay
que agregarlo: basta con indicar su ruta en la variable de entorno `RSCRIPT` al levantar la API
(ver "Levantar la API").

## Instalación

### 1. Paquetes de R

1. Instala R desde https://cran.r-project.org/ y, para trabajar cómodo, RStudio desde
   https://posit.co/download/rstudio-desktop/.
2. Abre **RStudio** y, en la consola (el panel inferior izquierdo, donde aparece el `>`), pega esta
   línea y presiona Enter:

   ```r
   install.packages(c("survey", "jsonlite", "yaml", "haven", "dplyr"))
   ```

3. La primera vez puede pedir elegir un *mirror* (un servidor de descarga): elige cualquiera cercano
   y continúa. La instalación tarda un par de minutos.
4. Para comprobar que quedaron bien, ejecuta en la misma consola:

   ```r
   library(survey); library(jsonlite); library(yaml); library(haven); library(dplyr)
   ```

   Si no aparece ningún error en rojo, están listos.

Para qué sirve cada uno: `survey`, `jsonlite` y `yaml` los usa la API en cada consulta; `haven` y
`dplyr` solo hacen falta para preparar los datos (leer los `.sav` y generar el `.rds`).

### 2. Entorno virtual de Python

El entorno virtual (`.venv`) es una carpeta donde se instalan las dependencias de este proyecto, sin
tocar el Python del sistema ni mezclarse con otros proyectos. Se crea una vez y se activa cada vez
que vayas a trabajar.

**1. Comprueba que tienes Python 3.10 o superior.** En una terminal:

```bash
python --version
```

Si imprime algo menor a 3.10 (o "no se reconoce"), instala Python desde https://www.python.org/
marcando la casilla *Add Python to PATH* durante la instalación.

**2. Crea el entorno.** Desde la carpeta `back/`:

```bash
python -m venv .venv
```

Esto crea la carpeta `back/.venv/`. Solo se hace una vez.

**3. Actívalo.** El comando depende de tu terminal:

- Windows (PowerShell):
  ```powershell
  .venv\Scripts\Activate.ps1
  ```
- Windows (CMD):
  ```bat
  .venv\Scripts\activate.bat
  ```
- macOS / Linux:
  ```bash
  source .venv/bin/activate
  ```

Cuando está activo, el prompt de la terminal muestra `(.venv)` al inicio. Si en PowerShell sale el
error *"la ejecución de scripts está deshabilitada"*, habilítalos para tu usuario una sola vez y
vuelve a activar:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**4. Instala las dependencias** (con el entorno ya activo):

```bash
pip install -r requirements.txt
```

**5. Comprueba que quedó listo:**

```bash
python -c "import fastapi, uvicorn, yaml; print('ok')"
```

Si imprime `ok`, el entorno está completo. Para salir del entorno cuando termines, escribe
`deactivate`.

> Si prefieres no activar el entorno cada vez, puedes llamar al Python del `.venv` directamente,
> por ejemplo `.venv\Scripts\python -m pip install -r requirements.txt`.

`rpy2` es opcional. Si está instalado, la API llama a R dentro del mismo proceso; si no (lo normal
en Windows), usa `Rscript` por detrás automáticamente. No hace falta `rpy2` para que funcione.

## Los datos: de los `.sav` al `.rds`

La API no lee los microdatos crudos en cada consulta. Trabaja sobre una base ya preparada
(`data/processed/enaho_<año>_viv_sum.rds`): un único archivo por año con Vivienda y Sumaria ya
unidas, los pesos calculados y los ámbitos derivados. Ese `.rds` se genera una vez con
`build_data.R` y después la API solo lo lee.

### Descargar y colocar los `.sav`

Los microdatos son públicos y se descargan del INEI. Viven **fuera del repositorio** porque pesan
mucho y no se versionan.

**1. Descárgalos del INEI.** Por cada año necesitas dos módulos:

1. Entra al portal de microdatos: https://proyectos.inei.gob.pe/microdatos/.
2. Elige la encuesta **ENAHO — Condiciones de Vida y Pobreza** (metodología actualizada / continua),
   el **año** que quieras y el periodo **Anual**.
3. Elige el formato **SPSS**, que es el que entrega los archivos `.sav`.
4. Descarga estos dos módulos:
   - **Módulo 01 — Características de la Vivienda y del Hogar** → trae `Enaho01-<año>-100.sav`.
   - **Módulo 34 — Sumaria, Variables Calculadas** → trae `Sumaria-<año>.sav`.
5. Cada módulo baja como un `.zip`. Descomprímelo y quédate con el archivo `.sav`.

**2. Elige dónde van a vivir.** Crea una carpeta para los datos (fuera del repo) y apunta a ella la
variable `RAW_DATA_DIR` en `config.R`:

```r
RAW_DATA_DIR <- "C:/Users/Jean/Desktop/Proyecto INEI/Datos"
```

**3. Colócalos con esta estructura exacta.** Una subcarpeta por año y, dentro, una por módulo.
El `build_data.R` espera estos nombres de archivo tal cual:

```
Datos/
├─ 2023/
│  ├─ Vivienda/
│  │  └─ Enaho01-2023-100.sav      módulo 01 (Vivienda)
│  └─ Sumaria/
│     └─ Sumaria-2023.sav          módulo 34 (Sumaria)
├─ 2024/
│  ├─ Vivienda/
│  │  └─ Enaho01-2024-100.sav
│  └─ Sumaria/
│     └─ Sumaria-2024.sav
└─ 2025/
   ├─ Vivienda/
   │  └─ Enaho01-2025-100.sav
   └─ Sumaria/
      └─ Sumaria-2025.sav
```

Los nombres los arma `config.R`, así que no los cambies a mano: Vivienda `Enaho01-<año>-100.sav` y
Sumaria `Sumaria-<año>.sav`.

Si el archivo de Sumaria baja como `Sumaria-<año>-12g.sav` (la variante con los 12 grandes grupos de
gasto), ese **no se usa**: el motor necesita `Sumaria-<año>.sav`. Puedes dejarlo en la carpeta, se
ignora.

### Generar el `.rds`

Con los `.sav` en su sitio y `RAW_DATA_DIR` apuntando a tu carpeta, desde `back/`:

```bash
Rscript build_data.R
```

Esto prepara todos los años declarados en `AVAILABLE_YEARS` (en `config.R`). Para preparar solo
algunos, pásalos como argumentos:

```bash
Rscript build_data.R 2023 2025
```

Si `Rscript` no está en el `PATH`, usa la ruta completa entre comillas:

```bash
"C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" build_data.R
```

Por cada año, el script deja en `data/processed/`:

- `enaho_<año>_viv_sum.rds` — la base lista para la API.
- `version_<año>.json` — metadatos (fecha, nº de hogares, nº de conglomerados, versión).

Mientras corre, imprime el avance (lectura, estandarización, unión, ámbitos) y verifica integridad:
que no haya hogares duplicados tras la unión y que no falten variables críticas. Si algo no cuadra,
se detiene con un mensaje claro en vez de generar una base a medias.

Como atajo, si ya te pasan la carpeta `data/processed/` generada, cópiala tal cual y te saltas este
paso.

## Levantar la API

1. Abre una terminal en `back/` y **activa el entorno** (ver "Entorno virtual de Python" → paso 3).
   Con el entorno activo verás `(.venv)` en el prompt.
2. Si tu `Rscript` **no** está en el `PATH`, indícalo antes de levantar (ajusta la ruta a tu versión
   de R). Si sí está en el `PATH`, salta este paso:

   ```powershell
   $env:RSCRIPT = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe"
   ```

3. Levanta la API:

   ```bash
   uvicorn app.main:app --host 127.0.0.1 --port 8000
   ```

4. Cuando aparezca `Application startup complete`, abre `http://127.0.0.1:8000/docs`.

Si prefieres no activar el entorno, el equivalente al paso 3 llamando directamente al Python del
`.venv` es `.venv\Scripts\python -m uvicorn app.main:app --port 8000`.

## Endpoints

| Método y ruta | Qué devuelve |
|---|---|
| `GET /indicators` | Catálogo de indicadores (nombre, unidad, niveles permitidos, definición) |
| `GET /levels` | Niveles de inferencia válidos (nacional, área, región natural, departamento) |
| `GET /years` | Años cargados y su estado |
| `GET /estimates?indicator=&level=&year=` | Estimación del indicador por nivel, con EE, CV e IC 95 % |
| `GET /crosstabs?indicator=&level=&cross_by=pobreza` | El indicador cruzado por condición de pobreza |

Todas responden `{ "meta": {...}, "data": [...] }`. Agrega `&format=csv` para descargar en CSV.

Las rutas y los parámetros van en inglés; los valores son los de la ENAHO (`nacional`,
`departamento`, `porcentaje`, `pobreza`…).

Errores: `404` indicador o año inexistente · `422` ámbito no permitido para ese indicador (la
respuesta incluye los ámbitos válidos) · `400` ámbito inválido.

El parámetro `year` acepta cualquiera de los años cargados (2023, 2024 o 2025). Si lo omites, se usa
el más reciente. Ejemplos:

```
http://127.0.0.1:8000/estimates?indicator=pobreza_total&level=departamento&year=2025
http://127.0.0.1:8000/estimates?indicator=gasto_pc&level=region_natural&year=2023
http://127.0.0.1:8000/crosstabs?indicator=agua_red_publica&level=nacional&cross_by=pobreza&year=2024
```

## Agregar un año nuevo

1. Descarga los módulos 01 y 34 del año desde INEI.
2. Déjalos en `Datos/<año>/Vivienda/` y `Datos/<año>/Sumaria/` con los nombres de siempre.
3. Agrega el año a `AVAILABLE_YEARS` en `config.R`.
4. Corre `Rscript build_data.R <año>`.

El catálogo de indicadores (`catalog/indicators.yaml`) no depende del año, así que no hay que
tocarlo. La UI toma los años nuevos del endpoint `/years`.

## Problemas frecuentes

- `'Rscript' no se reconoce` → no está en el `PATH`. Usa la variable `RSCRIPT` o la ruta completa.
- Sale vacío o "error en R" → falta el `.rds` del año (genera con `build_data.R`) o faltan paquetes
  de R.
- `Variable 'X' no existe en el modulo` al preparar → el `.sav` no corresponde al módulo esperado
  (por ejemplo, pusiste el `-12g` como Sumaria principal). Revisa los nombres.
- `Address already in use` (puerto 8000 ocupado) → usa otro puerto con `--port 8001` y ajusta
  `VITE_API_BASE` en el front.
- La primera consulta tarda 1–2 s → es normal: arranca un proceso de R. Las siguientes van rápidas.

## Estructura

```
back/
├─ app/                       Paquete FastAPI (se levanta como app.main:app)
│  ├─ main.py                   Crea la app, CORS e incluye los routers
│  ├─ settings.py               Rutas base y constantes (niveles, alias, umbral de CV)
│  ├─ catalog.py                Carga indicators.yaml y lo expone a la UI
│  ├─ versions.py               Versiones por año (.rds) y construcción del meta
│  ├─ engine.py                 Puente a R (rpy2 → fallback subprocess)
│  ├─ responses.py              Validaciones de entrada y salida (JSON/CSV)
│  └─ routers/
│     ├─ metadata.py              /indicators · /levels · /years
│     └─ queries.py               /estimates · /crosstabs
├─ config.R                   Rutas y constantes de R (aquí está RAW_DATA_DIR)
├─ build_data.R               Prepara los datos de cada año (.sav → .rds)
├─ bridge.R                   Lógica R que devuelve JSON (la usan rpy2 y subprocess)
├─ r_bridge.R                 Entrada del modo subprocess (Rscript)
├─ R/                         Motor: prepare_data, utils, levels, catalog, estimator (survey)
├─ catalog/indicators.yaml    Definición de los indicadores
├─ data/processed/            enaho_<año>_viv_sum.rds + version_<año>.json (generados; no en git)
└─ requirements.txt
```
