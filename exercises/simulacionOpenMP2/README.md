# Simulación de Predicción Climática con OpenMP

Simulación de un modelo climático simplificado (500+ regiones, temperatura/humedad/viento)
implementada en **C**, primero secuencial y luego paralela con **OpenMP**
(`parallel for` y `sections`), para medir Speedup y Eficiencia.

## Estructura

```
.
├── src/climate_sim.c        # programa único: modos seq / pfor / sections
├── Makefile                 # compila a bin/climate_sim
├── scripts/
│   ├── run_benchmark.sh     # corre seq + pfor/sections en varios thread counts -> results/results.csv
│   └── plot_results.py      # genera results/tiempos.png y results/speedup.png
├── results/                 # CSV y gráficas generadas (se regeneran con los scripts)
├── bin/                     # binario compilado (se regenera con `make`)
└── docs/
    ├── readme.md            # diseño del caso (pseudocódigo, modelo, cláusulas OpenMP)
    ├── presentacion.html    # diapositivas del diseño
    ├── resultados.html      # diapositivas con resultados medidos y gráficas
    └── RESULTS.md           # resumen de los resultados obtenidos
```

## Requisitos

- **gcc con soporte OpenMP.**
  - **macOS**: Apple Clang no trae `-fopenmp` funcional:
    ```bash
    brew install gcc      # instala gcc-16 (o similar)
    ```
    El `Makefile` busca automáticamente `gcc-16`/`gcc-15`/`gcc-14`/`gcc-13`, si no
    encuentra ninguno cae a `cc`.
  - **Windows (MinGW-w64 vía MSYS2 — recomendado)**: instala
    [MSYS2](https://www.msys2.org/) y desde su terminal (`MSYS2 UCRT64`):
    ```bash
    pacman -S mingw-w64-ucrt-x86_64-gcc make python python-pip
    ```
    Corre todos los comandos de este README desde esa misma terminal MSYS2
    (trae `bash`, `make`, `gcc` y `python3` reales; no uses `cmd.exe`/PowerShell).
    El `Makefile` detecta Windows automáticamente y compila a `bin/climate_sim.exe`.
  - **Linux**: `sudo apt install gcc` (o el gestor de paquetes de tu distro) — gcc ya trae OpenMP.
- **Python 3 + matplotlib** (solo para las gráficas):
  ```bash
  pip3 install matplotlib   # o `pip install matplotlib` dentro de MSYS2
  ```

## Cómo correr

```bash
make
```

Ejecutar una simulación puntual:

```bash
./bin/climate_sim <seq|pfor|sections> [N] [repeat] [threads]
```

| Argumento | Significado                                              | Default             |
|-----------|-----------------------------------------------------------|----------------------|
| modo      | `seq` (secuencial), `pfor` (`parallel for`), `sections`   | requerido            |
| N         | número de regiones a simular                               | 500                  |
| repeat    | veces que se itera el modelo por región (carga de cómputo) | 1                    |
| threads   | cantidad de threads OpenMP a usar (ignorado en `seq`)      | `omp_get_max_threads()` |

`N × repeat` es el trabajo total: subir `repeat` escala el cómputo sin disparar
la memoria, para poder demostrar el paralelismo sin necesitar arreglos gigantes.

Ejemplos:

```bash
./bin/climate_sim seq 3000000 40 1        # baseline secuencial
./bin/climate_sim pfor 3000000 40 8       # parallel for con 8 threads
./bin/climate_sim sections 3000000 40 4   # sections con 4 threads
```

### Benchmark completo + gráficas

```bash
./scripts/run_benchmark.sh 3000000 40 "1 2 4 8"   # N, repeat, lista de threads
python3 scripts/plot_results.py                    # results/tiempos.png y results/speedup.png
```

### Ver las diapositivas

```bash
open docs/presentacion.html   # diseño del caso
open docs/resultados.html     # código real + resultados medidos + gráficas
```

## Resultados (resumen)

Con **N = 3,000,000** y **repeat = 40**, `parallel for` alcanza **~4.77× de
speedup** con 8 threads (eficiencia ~60%); `sections` se satura en ~0.7× porque
solo reparte 3 tareas (temperatura/humedad/viento), sin importar cuántos
threads se pidan. Con la carga original (**N = 500**, cómputo trivial), el
overhead de administrar threads domina y `Sp ≤ 1` — el problema es demasiado
pequeño para beneficiarse del paralelismo.

Detalle completo, tablas y gráficas: [`docs/RESULTS.md`](docs/RESULTS.md) y
[`docs/resultados.html`](docs/resultados.html).
