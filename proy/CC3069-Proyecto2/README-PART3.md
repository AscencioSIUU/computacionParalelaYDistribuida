# Proyecto 2 — Parte 3: master-worker dinámico (HPC en clase)

La Parte 3 reemplaza el reparto **estático** por bloques (Partes 1 y 2) por un
modelo **master-worker** con balance de carga **dinámico**: el master administra
el espacio de llaves y entrega chunks pequeños a cada worker conforme termina
el anterior. El clúster final se arma en clase con 5–6 computadoras de varios
grupos sobre un router.

| Entregable del enunciado | Dónde |
|---|---|
| Validar Docker en cada computadora (capturas) | §6.1 (en clase) |
| Código base elegido (¿cuál?) | §6.2 (en clase) |
| Nodo Master y justificación (¿por qué?) | §6.3 (en clase) |
| Algoritmo master-worker en C | `bruteforce_des_mpi_dinamico.c`, §1 |
| Discusión teórica estático vs. dinámico | §4 |
| Bitácora de integración, métricas y resultados | §6.4–§6.6 (en clase) |

## 1. Algoritmo

`bruteforce_des_mpi_dinamico.c` reutiliza `des_busqueda.h` sin cambios (mismo
DES, misma frase clave, mismos argumentos `[bits] [clave] [archivo]`).

- **Rank 0 = master.** Lee y cifra el texto, lo difunde con `MPI_Bcast` y desde
  ese momento solo despacha trabajo. No prueba llaves.
- **Ranks 1..N-1 = workers.** Piden trabajo, prueban su chunk y reportan.
- El master corta `[0, 2^bits)` en chunks de `CHUNK` llaves (por defecto
  65 536 = 2^16), en orden ascendente, y los entrega **bajo demanda**.

Protocolo (solo mensajes punto a punto master ↔ worker; los workers no se
comunican entre sí):

| Tag | Dirección | Contenido |
|---|---|---|
| `TAG_RESULT` | worker → master | `{clave hallada o UINT64_MAX, llaves probadas en el chunk anterior}`; es a la vez el reporte y la petición del siguiente chunk |
| `TAG_WORK` | master → worker | `{inicio, fin)` del siguiente chunk |
| `TAG_STOP` | master → worker | mensaje vacío: no hay más trabajo |

El master recibe con `MPI_ANY_SOURCE`, así que atiende primero al worker que
termina primero. Cuando alguien reporta la clave, o cuando ya no quedan chunks,
el master contesta `TAG_STOP` a cada petición. Termina cuando todos los workers
recibieron `STOP`.

Invariantes comprobados:

- Los chunks cubren `[0, 2^bits)` exactamente una vez. Sin clave en el rango,
  `Candidatas probadas` es exactamente `2^bits`, incluso cuando `CHUNK` no divide
  el rango (el último chunk se recorta).
- Con `-np 1` el programa termina con un error claro: se necesita al menos un
  master y un worker.

La salida conserva las líneas que leen los scripts (`Clave encontrada: N`,
`Candidatas probadas: N`, `Tiempo`) y agrega el reparto por worker:

```text
Ejecucion: paralela MPI master-worker con 6 procesos (1 master + 5 workers, chunk = 16384)
Candidatas probadas: 4016385
Tiempo: 1.111249 segundos
Reparto dinamico por worker:
  rank 1   maestro                    chunks: 50       candidatas: 805121
  rank 2   worker1                    chunks: 48       candidatas: 786432
  ...
```

Simplificaciones deliberadas (marcadas `ponytail:` en el código):

- El master usa `MPI_Recv` bloqueante. Open MPI hace *busy-wait*, así que el
  master ocupa un slot completo aunque casi no calcula.
- Un worker se entera de que otro halló la clave al pedir su siguiente chunk.
  El trabajo desperdiciado es, como máximo, un chunk por worker.
- No hay *prefetch*: el worker espera la respuesta del master (un viaje de ida y
  vuelta por la red) antes de empezar cada chunk.

## 2. Archivos

| Archivo | Cambio |
|---|---|
| `bruteforce_des_mpi_dinamico.c` | Nuevo: master-worker dinámico. |
| `bruteforce_des_mpi.c` | Sin cambios: versión estática, se conserva para comparar. |
| `Dockerfile` | `/cluster/bruteforce` = dinámico; `/cluster/bruteforce_estatico` = estático. |
| `docker/mpi-run.sh` | Binario configurable con `BRUTEFORCE` (por defecto `/cluster/bruteforce`). |
| `Makefile`, `.dockerignore`, `.gitignore` | Registran el programa nuevo. |

## 3. Ejecución

### Local (sin Docker)

```bash
make
mpirun -np 4 ./bruteforce_des_mpi_dinamico 22 4000000
CHUNK=4096 mpirun -np 4 ./bruteforce_des_mpi_dinamico 22 4000000
```

### Clúster Docker local (3 contenedores)

```bash
bash ./cluster.sh up
bash ./cluster.sh validate
bash ./cluster.sh run 22 4000000
# Comparación con la versión estática y otro tamaño de chunk:
docker exec -e BRUTEFORCE=/cluster/bruteforce_estatico mpi_maestro \
  mpi-run /cluster/cluster_hosts 10.42.0.0/24 6 22 4000000
docker exec -e CHUNK=16384 mpi_maestro \
  mpi-run /cluster/cluster_hosts 10.42.0.0/24 6 22 4000000
bash ./cluster.sh down
```

### Súper-clúster en clase (5–6 computadoras)

Se usa el flujo LAN de [README-PART2.md](README-PART2.md) §B (firewall con TCP
22, 20000–20099 y 21000–21099; intercambio de claves con `mpi-trust`;
`mpi-run`). Reglas adicionales de esta parte:

1. **Todos** los nodos usan el mismo commit y **reconstruyen la imagen**. Si un
   nodo tiene el binario estático y otro el dinámico, el protocolo no coincide y
   la ejecución se congela.
2. La IP del master va **primero** en el hostfile. Así el rank 0 corre en la
   máquina donde se lanza `mpirun` y recibe la variable `CHUNK`.
3. `slots` del master = sus núcleos. El rank 0 ocupa uno como despachador y los
   demás slots del master son workers.
4. Total de procesos = suma de `slots`. Con 6 computadoras de 4 slots:
   `-np 24` = 1 master + 23 workers.

El túnel de [README-DESKTOP.md](README-DESKTOP.md) conecta solo 1 master con
1 worker (`10.77.0.0/30`), así que no sirve para el súper-clúster. Si se usa para
pruebas, conviene `.\desktop.ps1 run -MasterSlots 2 -WorkerSlots 1`: con
`1 + 1` el único worker es la Mac y el master solo despacha.

## 4. Discusión: modelo estático vs. modelo dinámico

**Modelo estático (Partes 1 y 2).** Antes de empezar, cada proceso recibe un
bloque contiguo del mismo tamaño, `[r·rango, (r+1)·rango)`. No hay que pedir
trabajo: la única comunicación es un `MPI_Allreduce` cada 4096 llaves para
avisar si alguien encontró la clave. Esa operación es **colectiva**, así que
todos los procesos se sincronizan entre sí, y cada uno avanza al ritmo del más
lento en cada sincronización. Hay dos consecuencias:

- **El tiempo lo decide la máquina más lenta.** Si un nodo es la mitad de rápido
  (CPU más vieja, emulación amd64 en una Mac, núcleos de eficiencia, otro
  programa corriendo), su bloque tarda el doble. Los demás nodos terminan y se
  quedan esperando en el `Allreduce`. Agregar una computadora lenta puede
  empeorar el tiempo total.
- **El tiempo depende de dónde cae la clave.** Una clave al inicio de un bloque
  se encuentra casi de inmediato; una al final obliga a recorrerlo entero
  (Parte 1 §5: el speedup aparente iba de 0.9× a 490×). La medición no refleja
  el paralelismo real.

**Modelo dinámico (Parte 3).** El master es el único que conoce el espacio de
llaves. Los workers piden trabajo cuando terminan, con mensajes **punto a punto**
(`MPI_Send`/`MPI_Recv`), y nunca esperan a otros workers. Así:

- **El reparto se adapta solo a la velocidad de cada nodo.** Un nodo el doble de
  rápido termina sus chunks en la mitad del tiempo, pide el doble de veces y
  recibe el doble de trabajo. No hay que medir ni configurar las máquinas de
  antemano; la tabla `Reparto dinamico por worker` lo muestra después de cada
  ejecución.
- **El desbalance final queda acotado por un chunk.** Al acabarse el rango, cada
  worker está a lo sumo a un chunk de terminar, en lugar de a un bloque completo
  de `2^bits / N` llaves.
- **El orden de búsqueda es ascendente y global.** El tiempo para hallar la
  clave `k` es aproximadamente `k / (velocidad total del clúster)`. Es
  predecible y no depende de la suerte de dónde cae la clave dentro de un bloque.

**Costos del modelo dinámico (lo que el stress test debe medir):**

1. **Latencia por chunk.** Cada chunk cuesta un viaje de ida y vuelta por la
   red durante el cual el worker no calcula. En el mismo equipo es despreciable;
   en Wi-Fi o a través de un router puede ser de 1–10 ms. Con chunks de 2^16
   llaves (≈ 65 ms a 1 M llaves/s) eso es entre 1.5 % y 15 % del tiempo.
2. **El master es un punto de serialización.** Atiende una petición a la vez.
   Con muchos workers rápidos y chunks pequeños, las peticiones hacen cola y los
   workers esperan. También es un punto único de falla.
3. **Un núcleo se dedica a despachar.** El rank 0 casi no calcula, pero ocupa un
   slot. Con 1 master + 1 worker el speedup máximo es ≈ 1.
4. **Trabajo desperdiciado al terminar.** Cuando alguien encuentra la clave, los
   demás terminan su chunk actual antes de enterarse.

**Granularidad del chunk.** Es la perilla central del modelo:

- Chunk **pequeño**: balance fino y poca espera al final, pero más mensajes y
  más overhead de red y del master.
- Chunk **grande**: pocos mensajes, pero más desbalance al final y más trabajo
  desperdiciado; en el límite (un chunk por worker) vuelve a ser el modelo
  estático.

El chunk adecuado hace que el tiempo de cálculo de un chunk sea mucho mayor que
la latencia de la red (al menos 50–100 veces). Por eso se puede ajustar con
`CHUNK` sin recompilar.

**Patrón de comunicación.** El estático usa una colectiva que involucra a todos
los procesos en cada sincronización. El dinámico usa una topología en estrella:
los workers solo hablan con el master. Es más tolerante a nodos lentos, porque
nadie espera a nadie, pero concentra todo el tráfico de control en un solo nodo.

## 5. Resultados de referencia (antes de la clase)

**Pruebas de corrección (Mac, Open MPI 5.0.11, nativo):**

| Prueba | Resultado |
|---|---|
| `-np 4 … 22 4000000` | `Clave encontrada: 4000000` |
| `-np 3 … 10 999999` (clave fuera del rango) | `Candidatas probadas: 1024` (= 2^10) |
| `CHUNK=1000 -np 5 … 20 99999999` (último chunk recortado) | `Candidatas probadas: 1048576` (= 2^20) |
| `CHUNK=1 -np 2 … 4 0` (clave 0) | `Clave encontrada: 0`, 1 candidata |
| `-np 1` | error claro, código de salida 1, sin congelarse |
| `CHUNK=abc` | `CHUNK invalido`, `MPI_Abort` |
| `cluster.sh validate` (3 contenedores, Open MPI 4.1.2) | 1024 candidatas y clave 12345 |

**Heterogeneidad en una sola máquina.** La MacBook (M5 Pro) tiene 5 núcleos de
rendimiento y 10 de eficiencia, y durante la prueba había una compilación de
Xcode en paralelo (load average ≈ 146). Es un caso de nodos heterogéneos y
cargados. Barrido completo de 2^26 llaves (clave imposible), 3–4 corridas:

| Versión | Procesos que calculan | Tiempos (s) | Mediana (s) |
|---|---|---|---|
| Estático `-np 15` | 15 | 9.64, 13.12, 23.95 | 13.12 |
| Estático `-np 14` | 14 | 9.14, 14.34, 60.78 | 14.34 |
| Dinámico `-np 15` | 14 (+1 master) | 7.56, 7.41, 10.38, 15.66 | ≈ 9.0 |

El dinámico fue más rápido y, sobre todo, más estable. El peor caso estático
(60.8 s) se da cuando un proceso queda en un núcleo saturado y todos lo esperan.
En el dinámico, los 14 workers recibieron entre 70 y 77 chunks de los 1024: el
reparto se ajustó a lo que cada núcleo pudo dar en esa corrida.

**Clúster Docker local (6 procesos, 2^22, clave 4 000 000):** el dinámico tardó
1.11 s (`CHUNK=16384`, 48–50 chunks por worker) y el estático 0.71 s. No es una
contradicción: con 6 bloques la clave cae al 72 % del bloque del rank 5, así que
el estático solo recorre 504 745 llaves por proceso. El dinámico barre en orden
hasta 4 000 000 con 5 workers. Es el efecto de la posición de la clave descrito
en §4; la comparación justa es el barrido completo.

Estos números son de una sola máquina con carga externa. Las métricas finales
salen del súper-clúster (§6.5).

## 6. En clase (por llenar)

### 6.1 Validación de Docker por integrante

| Integrante | SO / hardware | `cluster.sh validate` o `desktop.sh … up` | Captura |
|---|---|---|---|
| | | | |

### 6.2 Código base elegido

> ¿Cuál? … — Criterios sugeridos: corrección comprobada (invariante 2^bits),
> facilidad de despliegue en Docker en todos los SO del grupo, claridad del
> código para modificarlo.

### 6.3 Nodo Master

> ¿Cuál y por qué? … — Criterios sugeridos: SO host con Docker nativo (Linux)
> o red puente, conexión por cable al router, más núcleos y RAM, sin suspensión
> ni otras cargas durante la prueba. El master despacha y recibe todo el tráfico
> de control, así que importa más su red que su CPU.

### 6.4 Hostfile final

```text
# IP_MASTER va primero
IP_MASTER slots=? max_slots=?
IP_WORKER1 slots=? max_slots=?
```

### 6.5 Métricas del stress test

Barrido completo con clave imposible (`mpi-run … <np> 26 999999999`), variando
el chunk con `-e CHUNK=…` y la versión con `-e BRUTEFORCE=…`:

| Versión | Nodos | Procesos | CHUNK | Tiempo (s) | Llaves/s | Speedup vs. 1 nodo | Observación |
|---|---|---|---|---|---|---|---|
| estático | | | — | | | | |
| dinámico | | | 1024 | | | | |
| dinámico | | | 65536 | | | | |
| dinámico | | | 1048576 | | | | |

### 6.6 Bitácora de integración

| # | Problema | Síntoma | Causa | Solución |
|---|---|---|---|---|
| 1 | | | | |

Evidencias: foto de cómo se unieron las computadoras, comando ejecutado en el
master y salida con la tabla `Reparto dinamico por worker`.
