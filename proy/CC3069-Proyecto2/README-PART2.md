# Proyecto 2 — Parte 2: HPC con Open MPI colectivo (Docker)

Esta parte lleva el ataque de fuerza bruta DES de la Parte 1 (un solo nodo,
`localhost`) a un **cluster distribuido real**: cada integrante corre una imagen
Docker idéntica, los contenedores se comunican por la LAN del router, uno actúa
como **Nodo Maestro** y los demás como **Workers**, y `mpirun --hostfile`
reparte la búsqueda entre todas las máquinas.

El código DES/MPI (`bruteforce_des_mpi.c`, `des_busqueda.h`) es el mismo de la
Parte 1. Lo nuevo es la **infraestructura**: `Dockerfile`, `docker-compose.yml`,
`cluster.sh`, los hostfiles y la bitácora de troubleshooting.

> **Por qué Docker.** Estandariza el entorno (mismo Open MPI 4.1.2, mismo
> compilador, mismas rutas) en Windows, macOS y Linux. Así se elimina la
> incompatibilidad de `<rpc/des_crypt.h>`, versiones de MPI distintas y rutas
> de binarios que de otra forma harían fallar el cluster.

---

## Archivos

| Archivo | Qué es |
|---|---|
| `Dockerfile` | Imagen `mpi-cluster-image`: Ubuntu 22.04 + build-essential, Open MPI, OpenSSH, OpenSSL. Hornea una llave SSH compartida y compila `/cluster/bruteforce`. |
| `docker-compose.yml` | Cluster local: maestro + worker1 + worker2 en una red bridge `10.42.0.0/24`. |
| `cluster.sh` | Orquestador: `build`, `up`, `validate`, `run`, `ips`, `shell`, `down`. |
| `cluster_hosts` | Hostfile del cluster **local** (nombres de servicio, `slots=2` c/u). |
| `cluster_hosts.lan.example` | Plantilla del hostfile del cluster **físico** (IPs, `slots`, `max_slots`). |
| `BITACORA-PART2.md` | Registro de actividad, tabla de validación, troubleshooting y discusión §VI. |

---

## A. Validación local (una sola máquina, lo que se prueba aquí)

Simula el cluster con 3 contenedores en una red bridge. Reproduce el flujo real
(SSH sin contraseña + `mpirun --hostfile` + restricción de subred por `--mca`),
que es el ensayo del despliegue físico.

```bash
./cluster.sh build       # construye la imagen
./cluster.sh up          # levanta maestro + 2 workers
./cluster.sh validate    # tabla de validacion del enunciado
./cluster.sh ips         # IP de cada contenedor (distintas => nodos distintos)
./cluster.sh run 22 4000000   # ataque distribuido; recupera la clave 4000000
./cluster.sh down        # destruye el cluster
```

`run` ejecuta exactamente el comando del enunciado (subred de ejemplo):

```bash
mpirun --hostfile cluster_hosts \
  --mca btl_tcp_if_include 10.42.0.0/24 --mca oob_tcp_if_include 10.42.0.0/24 \
  -np 6 /cluster/bruteforce 22 4000000
```

---

## B. Despliegue físico real (con el equipo y el router)

1. **Todos** construyen la imagen con el mismo `Dockerfile`:
   ```bash
   docker build -t mpi-cluster-image .
   ```
2. Conéctense al mismo router. Anoten la IP que les asignó (`192.168.1.X`):
   ```bash
    hostname -I        # o: ip addr
   ```
3. **Docker Desktop** (Windows/macOS): Settings → Resources → Network →
   habilitar **Enable Host Networking** (requiere Docker Desktop ≥ 4.34).
4. Cada integrante corre su contenedor compartiendo la red del host (sin NAT):
   ```bash
   docker run -it --network host --name mpi_node mpi-cluster-image /bin/bash
   service ssh start
   ```
5. **Firewall**: permitir conexiones entrantes en red privada (Windows Defender /
   macOS Firewall). Si no, los workers dan `Connection refused` silencioso.
6. En el **Nodo Maestro**, editen `cluster_hosts` con las IPs reales (ver
   `cluster_hosts.lan.example`) y lancen el ataque **limitando el tráfico a la
   subred física** (obligatorio, si no MPI se congela — ver bitácora §VI.1):
   ```bash
   mpirun --hostfile cluster_hosts \
     --mca btl_tcp_if_include 192.168.1.0/24 \
     --mca oob_tcp_if_include 192.168.1.0/24 \
     -np <TOTAL_SLOTS> /cluster/bruteforce <bits> <clave>
   ```

---

## C. Descifrado cruzado (texto de otro equipo, §III del enunciado)

El crib (`SEARCH`) se fija en tiempo de compilación. Para atacar el texto de
otro equipo con su *palabra objetivo*, reconstruyan la imagen con su crib:

```bash
docker build --build-arg SEARCH="su palabra objetivo" -t mpi-cluster-image .
```

Coloquen el texto cifrado del otro equipo en `texto.txt` antes de construir.
