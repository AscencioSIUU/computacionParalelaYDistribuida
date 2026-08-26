# Resultados de la simulación

## Cómo correr

Desde la raíz del proyecto:

```bash
make                                     # compila bin/climate_sim (usa gcc-16/homebrew si está disponible)
./bin/climate_sim <seq|pfor|sections> [N] [repeat] [threads]

./scripts/run_benchmark.sh [N] [repeat] ["threads_list"]   # ej: ./scripts/run_benchmark.sh 3000000 40 "1 2 4 8"
python3 scripts/plot_results.py                             # genera results/tiempos.png y results/speedup.png
```

`N` = número de regiones. `repeat` = veces que se itera el modelo por región
(controla la carga de cómputo por región sin disparar el uso de memoria — así
se puede escalar el trabajo total N × repeat a un tamaño "inmenso" con N moderado).

## Caso grande (N = 3,000,000, repeat = 40): demuestra el paralelismo

| Threads | Tiempo (pfor) | Speedup | Eficiencia |
|--------:|--------------:|--------:|-----------:|
|       1 |      0.2516 s |    0.72 |        72% |
|       2 |      0.1236 s |    1.47 |        74% |
|       4 |      0.0658 s |    2.77 |        69% |
|       8 |      0.0382 s |    4.77 |        60% |

(T secuencial de referencia = 0.1822 s)

`sections` solo reparte 3 tareas (temperatura/humedad/viento) → su speedup se
satura en ~0.7 a partir de 4 threads: **no hay más de 3 secciones para
repartir**, el resto de threads queda ocioso. Este es el cuello de botella de
sincronización/paralelismo esperado con `sections` cuando p > número de tareas.

Ver `results/tiempos.png` y `results/speedup.png`.

## Caso pequeño (N = 500, repeat = 1): overhead domina

```
seq          threads=1  time=0.000001s
pfor threads=1  time=0.000021s
pfor threads=2  time=0.000042s
pfor threads=4  time=0.000060s
pfor threads=8  time=0.000128s
```

Con 500 registros y un cálculo trivial por región, el costo de crear y
sincronizar threads supera el trabajo real: `Tp ≥ Ts` y `Sp ≤ 1`. Confirma
experimentalmente la observación del diseño (sección 40-41 del README): el
problema debe ser lo bastante grande para que el paralelismo compense.

## Verificación de correctitud

Las tres versiones (`seq`, `pfor`, `sections`) producen los mismos promedios
(`avgT`, `avgH`, `avgV`) para el mismo `N`/`repeat`, confirmando que el
paralelismo no altera el resultado.

## Conclusión

Se logró la optimización esperada: con carga suficiente (`N × repeat` grande),
`parallel for` alcanza speedups de hasta ~4.6× con 8 threads (eficiencia ~58%,
cayendo por el overhead de agendamiento y por la caída de eficiencia normal al
subir p). `sections` expone el cuello de botella de paralelismo de tareas:
limitado por la cantidad de tareas independientes (3), no por los threads
disponibles.
