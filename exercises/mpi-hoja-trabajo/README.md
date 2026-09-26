# Hoja de trabajo: comunicación con MPI

Este ejercicio conserva tres programas independientes para mostrar la evolución
solicitada: iniciar MPI, enviar un saludo desde el proceso 0 y, finalmente,
comunicar procesos en parejas par/impar. El saludo incluye `Nesstor07` de forma
predeterminada y puede personalizarse al compilar.

## Requisitos

Se necesita una implementación de MPI que incluya `mpicc` y `mpirun`.

En Ubuntu o Debian con OpenMPI:

```bash
sudo apt update
sudo apt install build-essential openmpi-bin libopenmpi-dev
```

En macOS con Homebrew:

```bash
brew install open-mpi
```

También se puede usar MPICH. Antes de compilar, comprobar la instalación:

```bash
mpicc --version
mpirun --version
```

## Compilación

Desde este directorio:

```bash
make NAME="Nombre Apellido"
```

Esto genera `mpi_hello`, `mpi_broadcast` y `mpi_pairs`. Si se omite `NAME`, se
usa `Nesstor07`. Si ya existen binarios y se quiere cambiar el nombre, ejecutar
primero `make clean` para forzar una nueva compilación.

El `Makefile` usa advertencias estrictas y permite reemplazar las herramientas,
por ejemplo `make MPICC=mpicc MPIRUN=mpiexec`.

## Etapa 1: estructura básica

`mpi_hello.c` inicializa el entorno, consulta el identificador del proceso
(`rank`) y el número total de procesos, imprime el saludo y finaliza MPI:

```c
MPI_Init(&argc, &argv);
MPI_Comm_rank(MPI_COMM_WORLD, &rank);
MPI_Comm_size(MPI_COMM_WORLD, &process_count);
printf("Hello World de %s: proceso %d de %d.\n",
       STUDENT_NAME, rank, process_count);
MPI_Finalize();
```

Ejecutar con cuatro procesos:

```bash
make run-hello NP=4
```

Se esperan cuatro saludos, uno por cada `rank`. El orden puede cambiar entre
ejecuciones porque los procesos avanzan concurrentemente.

## Etapa 2: envío desde el proceso 0

`mpi_broadcast.c` implementa la difusión manual requerida, sin usar
`MPI_Bcast`. El proceso 0 recorre los demás rangos y hace un envío punto a
punto; cada proceso restante publica una recepción correspondiente:

```c
if (rank == 0) {
    for (int destination = 1; destination < process_count; ++destination) {
        MPI_Send(MESSAGE, sizeof(MESSAGE), MPI_CHAR, destination,
                 MESSAGE_TAG, MPI_COMM_WORLD);
    }
} else {
    MPI_Recv(received_message, sizeof(received_message), MPI_CHAR, 0,
             MESSAGE_TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
}
```

Ejecutar:

```bash
make run-broadcast NP=4
```

Con cuatro procesos deben aparecer tres líneas de envío desde el proceso 0 y
tres líneas de recepción, una en cada proceso 1, 2 y 3.

## Etapa 3: parejas pares e impares

`mpi_pairs.c` exige al menos dos procesos y una cantidad par. Así, todo proceso
par siempre tiene como destino válido a `rank + 1`; el impar correspondiente
recibe exclusivamente desde `rank - 1`:

```c
if (rank % 2 == 0) {
    MPI_Send(MESSAGE, sizeof(MESSAGE), MPI_CHAR, rank + 1,
             MESSAGE_TAG, MPI_COMM_WORLD);
} else {
    MPI_Recv(received_message, sizeof(received_message), MPI_CHAR, rank - 1,
             MESSAGE_TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
}
```

Ejecutar:

```bash
make run-pairs NP=4
```

El resultado debe contener exactamente dos envíos y dos recepciones: la pareja
0→1 y la pareja 2→3. Cada `MPI_Send` tiene un único `MPI_Recv` con el mismo
origen/destino, etiqueta y comunicador, por lo que ningún proceso queda
esperando una comunicación inexistente.

Las configuraciones que no pueden formar parejas se rechazan limpiamente:

```bash
make run-pairs NP=3
make run-pairs NP=1
```

En ambos casos, el proceso 0 muestra el error, todos los procesos llaman a
`MPI_Finalize` y el programa termina con estado de fallo. Es normal que
`mpirun` añada un resumen indicando que uno o más procesos devolvieron un
código distinto de cero.

## Limpieza

```bash
make clean
```

Solo se eliminan los tres binarios generados.

## Evidencia para la entrega

Las capturas deben obtenerse ejecutando los programas en un equipo con MPI; no
se incluyen capturas fabricadas en este repositorio. Tomar, como mínimo:

1. `mpicc --version` y `mpirun --version` para demostrar la instalación.
2. `make clean && make NAME="Nombre Apellido"` sin errores ni advertencias.
3. `make run-hello NP=4`, mostrando los cuatro rangos.
4. `make run-broadcast NP=4`, mostrando tres envíos y tres recepciones.
5. `make run-pairs NP=4`, mostrando las parejas 0→1 y 2→3.
6. `make run-pairs NP=3` y `make run-pairs NP=1`, mostrando el rechazo de ambas
   configuraciones inválidas.

Conviene que cada captura incluya el comando completo, toda su salida y el
prompt final para evidenciar que la ejecución terminó y no quedó bloqueada.
