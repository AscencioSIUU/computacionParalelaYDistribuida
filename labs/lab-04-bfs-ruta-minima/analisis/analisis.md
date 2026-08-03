# Análisis y Ejecución — Problema 4: Búsqueda de Ruta Mínima (BFS)

## Capturas de pantalla

> Pegar aquí las capturas reales de la terminal: compilación exitosa y output correcto.

- Compilación: `![compilación](capturas/compilacion.png)`
- Ejecución / output correcto: `![ejecución](capturas/ejecucion.png)`

Comandos usados:
```bash
gcc-16 src/bfs_secuencial.c -o bfs -Wall
./bfs
```
Salida esperada:
```
Buscando ruta de Alice (0) a Eve (4)...
Camino más corto encontrado: 0 -> 2 -> 4
Buscando ruta de Charlie (2) a Bob (1)...
Camino más corto encontrado: 2 -> 0 -> 1
[OK] Verificación de camino Alice->Eve pasó correctamente.
```

## 2.1 Descomposición del Trabajo

El ciclo principal de `bfs_camino_mas_corto` (`while (frente < final_cola)`) **no** opera sobre
un arreglo continuo de datos homogéneos: en cada iteración saca un nodo de la cola y recorre su
lista de adyacencia, cuyo tamaño es completamente irregular (un usuario puede tener 2 amigos,
otro 10 000). Esto descarta el enfoque **A) Paralelismo de Datos** como dominante.

El trabajo real que se reparte es **B) División por Tareas**: cada nodo desencolado (y, dentro
de él, cada vecino a evaluar) es una "tarea" de validación —¿está visitado?, ¿es el objetivo?—
sobre una estructura dinámica (la lista de adyacencia), no un cálculo matemático masivo sobre
un vector fijo.

**Cómo evitar que un hilo se quede con toda la carga:** si un hilo tiene un nodo con 2 vecinos y
otro tiene el nodo de 10 000 amigos, una repartición estática (ej. "hilo 0 procesa los primeros
N/hilos nodos") deja al segundo hilo trabajando solo mientras los demás terminan y quedan
ociosos. La estrategia planeada para la fase de paralelización es:
- Procesar la **frontera del nivel actual de BFS** (todos los nodos ya encolados en ese nivel)
  repartiendo la iteración sobre sus vecinos con `#pragma omp parallel for schedule(dynamic)`
  (o una cola de tareas con `#pragma omp task`), de modo que un hilo que termina rápido con un
  nodo de pocos amigos tome dinámicamente el siguiente bloque de trabajo pendiente en vez de
  quedar ocioso mientras otro hilo agota los 10 000 vecinos.

## 2.2 Inventario de Memoria

**Variables de Referencia (acceso seguro, solo lectura durante el ciclo):**
- `grafo[]` (arreglo de listas de adyacencia): todos los hilos solo leen los punteros y nodos
  para descubrir vecinos; nunca se modifica durante la búsqueda.
- `objetivo`: constante durante toda la ejecución de `bfs_camino_mas_corto`.
- Campos `Nodo.vertice` / `Nodo.siguiente`: se leen para recorrer la lista, no se escriben.

**Variables de Colisión (riesgo de race conditions):**
- `visitados[]`: si dos hilos procesan simultáneamente nodos que comparten un mismo `vecino`,
  ambos pueden leer `visitados[vecino] == false` antes de que el otro lo marque en `true`,
  provocando que el mismo vecino se agregue **dos veces** a la cola (trabajo duplicado y
  posible desbordamiento de `cola[]`).
- `padre[]`: si dos hilos marcan visitado y escriben `padre[vecino]` casi al mismo tiempo, el
  valor final es indeterminado (race de escritura), corrompiendo la reconstrucción del camino.
- `cola[]` junto con su índice `final_cola`: `cola[final_cola++] = vecino` es una lectura +
  incremento + escritura no atómica. Si dos hilos ejecutan esto en paralelo sin control, pueden
  leer el mismo valor de `final_cola` y sobrescribirse el uno al otro (un vecino se pierde) o
  incrementar mal el índice (corrupción del arreglo).
- `frente` / `encontrado`: `frente` avanza por cada nodo desencolado; si varios hilos desencolan
  a la vez sin sincronización, pueden tomar el mismo `actual` dos veces o saltarse nodos.
  `encontrado` es una bandera de parada compartida: un hilo puede leerla como `false` justo
  después de que otro la puso en `true`, haciendo trabajo de más antes de detenerse.

En resumen: sin control (locks, atómicos, o reducción por niveles de BFS), separar la carga
entre hilos sobre estas variables produce datos duplicados, perdidos o corruptos.
