# Lab 04 — Búsqueda de Ruta Mínima (Grafos)

Red social con usuarios (nodos) y amistades (aristas). Se busca el camino más corto entre dos
usuarios con BFS explorando vecinos mediante una cola de tareas pendientes.

Entregables de esta fase (Parte 1 + Parte 2 — la paralelización con OpenMP es la siguiente fase):

- `src/bfs_secuencial.c` — versión secuencial funcional y comentada.
- `diagrama/flujo_secuencial.drawio` — diagrama de flujo del algoritmo (abrir con la extensión
  **Draw.io Integration** de VSCode).
- `analisis/analisis.md` — capturas de ejecución + respuestas 2.1 (descomposición del trabajo) y
  2.2 (inventario de memoria: variables de referencia vs. de colisión).

## Compilar y ejecutar

```bash
gcc-16 src/bfs_secuencial.c -o bfs -Wall
./bfs
```

Requiere GCC con soporte OpenMP para la fase siguiente (`gcc-16` vía Homebrew en macOS; el
Clang del sistema no soporta `-fopenmp`).
