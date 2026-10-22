# Bitácora — Proyecto 2, Parte 2: HPC con Open MPI colectivo (Docker)

**Curso:** CC3069 Computación Paralela y Distribuida — Universidad del Valle de Guatemala
**Equipo:** Ernesto Ascencio (23009), Hugo Barillas (23556)
**Objetivo de la parte 2:** llevar el ataque de fuerza bruta DES de la Parte 1 (un solo
nodo) a un clúster distribuido real, estandarizando el entorno con Docker y orquestando
los nodos con `mpirun --hostfile` sobre una LAN.

> **Nota de alcance.** El despliegue físico final (varias computadoras del equipo sobre el
> router del aula) se realiza en vivo con el grupo. Como ensayo verificable, se construyó un
> **clúster local de 3 contenedores** (`maestro`, `worker1`, `worker2`) sobre una red bridge
> dedicada, que reproduce el flujo completo del despliegue real: imagen Docker común, SSH sin
> contraseña entre nodos y `mpirun --hostfile` con el tráfico restringido a la subred por
> `--mca`. Toda la evidencia de abajo proviene de ejecuciones reales de ese clúster local.

---

## 1. Entregables nuevos (Parte 2)

| Archivo | Qué es |
|---|---|
| `Dockerfile` | Imagen `mpi-cluster-image`: Ubuntu 22.04 + Open MPI + OpenSSH + OpenSSL; hornea una llave SSH compartida y compila `/cluster/bruteforce`. |
| `.dockerignore` | Reduce el contexto de build a las fuentes. |
| `docker-compose.yml` | Clúster local: `maestro` + `worker1` + `worker2` en la red bridge `10.42.0.0/24`. |
| `cluster.sh` | Orquestador: `build`, `up`, `validate`, `run`, `ips`, `shell`, `down`. |
| `cluster_hosts` | Hostfile del clúster local (nombres de servicio, `slots=2`). |
| `cluster_hosts.lan.example` | Plantilla del hostfile del clúster **físico** (IPs, `slots`, `max_slots`). |
| `README-PART2.md` | Guía de uso (simulación local + despliegue físico real). |
| `BITACORA-PART2.md` | Este documento. |

El código DES/MPI (`bruteforce_des_mpi.c`, `des_busqueda.h`) es el mismo de la Parte 1; no se
modificó la lógica del algoritmo, solo se agregó la infraestructura de contenedores.

---

## 2. Registro de actividad (cronológico)

1. Se leyó el enunciado de la Parte 2 y se definió la estrategia: Dockerfile sobre
   `ubuntu:22.04`, llave SSH compartida y un clúster local de 3 contenedores para validar
   antes del despliegue físico.
2. Se redactó el `Dockerfile` con los paquetes del enunciado (`build-essential`, `openmpi-bin`,
   `libopenmpi-dev`, `openssh-server`), las variables `OMPI_ALLOW_RUN_AS_ROOT`, el
   `PermitRootLogin yes` y el `StrictHostKeyChecking no`.
3. Primer `docker build`: **falló** la compilación (ver Troubleshooting #1 y #4). Se corrigió
   agregando `libssl-dev` y cambiando `-std=c11` por `-std=gnu11`.
4. Build exitoso. Imagen `mpi-cluster-image` con `gcc 11.4.0` y `/cluster/bruteforce`.
5. Se levantó el clúster (`docker compose up`) y se corrió la tabla de validación del enunciado.
   La prueba de SSH imprimía vacío (Troubleshooting #7): se corrigió el comando remoto.
6. Se probó el pedido del usuario de "revertir al `bruteforce.c` original para Linux". Se
   demostró empíricamente que **no compila en Ubuntu 22.04** (Troubleshooting #3) y se decidió
   mantener el port a OpenSSL.
7. Se ejecutó el ataque distribuido (`cluster.sh run 22 4000000`): clave recuperada en los 3
   contenedores. Se capturó el mapeo rank→nodo y el tiempo secuencial base.
8. Se publicó el texto cifrado del equipo para la fase de descifrado cruzado (§III).
9. Se documentó todo en esta bitácora.

---

## 3. Tabla de validación del entorno (§IV del enunciado)

| Validar | Esperado | ¿Funcionó? | Qué se tuvo que modificar o hacer |
|---|---|---|---|
| `docker run --rm mpi-cluster-image mpicc --version` | mostrar gcc (Ubuntu 11.4.0 ~22.04) 11.4.0 | ✅ Sí | Agregar `libssl-dev` y compilar con `-std=gnu11` para que la imagen construyera. |
| `docker run --rm mpi-cluster-image mpirun -np 2 echo "Proceso MPI ejecutado"` | imprime el mensaje 2 veces | ✅ Sí | `ENV OMPI_ALLOW_RUN_AS_ROOT=1` y `..._CONFIRM=1` (OpenMPI no corre como root sin esto). |
| `docker run -it --rm mpi-cluster-image /bin/bash` | entra a la terminal del contenedor | ✅ Sí | Ninguna. |
| `service ssh start` / `sshd` | arranca el demonio SSH | ✅ Sí | `mkdir /var/run/sshd`; el `CMD` del contenedor lanza `sshd -D`. |
| `ssh-keygen` + `authorized_keys` | genera y prueba la llave localmente | ✅ Sí | Se **horneó una llave compartida en la imagen**: todos los contenedores confían entre sí sin copiar llaves a mano. |
| `ssh localhost echo "..."` | conexión SSH sin contraseña | ✅ Sí | `PermitRootLogin yes` + `StrictHostKeyChecking no` + `UserKnownHostsFile /dev/null`. |

**Salida real de `./cluster.sh validate`:**

```
== 1) mpicc --version ==
gcc (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0

== 2) mpirun -np 2 echo (debe imprimir 2 veces) ==
Proceso MPI ejecutado
Proceso MPI ejecutado

== 3) SSH maestro -> workers sin contrasena ==
maestro -> worker1  OK (sin contrasena; hostname remoto: worker1)
maestro -> worker2  OK (sin contrasena; hostname remoto: worker2)
```

---

## 4. Despliegue del clúster y ataque distribuido (§V del enunciado)

**Paso A — Sincronización de llaves SSH inter-nodo.** Resuelto de forma reproducible: el
`Dockerfile` genera un par RSA y lo copia a `authorized_keys` dentro de la imagen, así que
cada contenedor construido de `mpi-cluster-image` ya trae la llave pública del resto. No hay
copiado manual por nodo. Evidencia: la prueba 3 de la tabla anterior (SSH maestro→workers sin
contraseña).

**IPs asignadas a cada nodo del clúster** (`./cluster.sh ips`):

```
mpi_maestro    10.42.0.2
mpi_worker1    10.42.0.3
mpi_worker2    10.42.0.4
```

**Paso B — Ejecución del ataque distribuido** (`./cluster.sh run 22 4000000`), que ejecuta:

```
mpirun --hostfile cluster_hosts \
  --mca btl_tcp_if_include 10.42.0.0/24 --mca oob_tcp_if_include 10.42.0.0/24 \
  --mca btl tcp,self -np 6 /cluster/bruteforce 22 4000000
```

Salida (resumen):

```
Rango explorado: 2^22 = 4194304 candidatas
Clave encontrada: 4000000
Mensaje: Este documento es una prueba preparada para el Proyecto 2 de Computacion Paralela
         y Distribuida de la Universidad del Valle de Guatemala. [... texto completo de 363 palabras ...]
Ejecucion: paralela MPI con 6 procesos (reparto por bloques)
Candidatas probadas: 3044266
Tiempo: 0.954614 segundos
```

**Evidencia de que participaron distintos nodos (IPs).** Mapeo rank → contenedor:

```
rank 0 -> maestro (10.42.0.2)
rank 1 -> maestro (10.42.0.2)
rank 2 -> worker1 (10.42.0.3)
rank 3 -> worker1 (10.42.0.3)
rank 4 -> worker2 (10.42.0.4)
rank 5 -> worker2 (10.42.0.4)
```

Los 6 procesos se repartieron en las 3 IPs del clúster; la llave del reto se recuperó
correctamente y se descifró el texto completo.

---

## 5. Troubleshooting (problemas encontrados y su solución)

**#1 — `-lcrypto` no enlaza: falta `libssl-dev`.**
El DES del proyecto está portado a OpenSSL (`openssl/des.h`, `-lcrypto`). La lista de paquetes
del enunciado (`build-essential openmpi-bin libopenmpi-dev openssh-server`) no incluye las
cabeceras de OpenSSL, así que la compilación fallaba. *Solución:* agregar `libssl-dev` al
`apt-get install` del Dockerfile.

**#2 — `mpirun` necesita cliente SSH: falta `openssh-client`.**
Con `--no-install-recommends`, `openssh-server` no arrastra el cliente, y `mpirun` lanza los
`orted` en los workers por `ssh`. *Solución:* agregar `openssh-client`.

**#3 — El `bruteforce.c` original NO compila en Ubuntu 22.04.**
Se probó el pedido de usar el archivo original del enunciado (`<rpc/des_crypt.h>`,
`ecb_crypt`/`des_setparity`). En Ubuntu 22.04 (glibc 2.35) el Sun-RPC DES fue **removido de
glibc**:

```
bruteforce.c:13:10: fatal error: rpc/des_crypt.h: No such file or directory
```

Instalar `libtirpc-dev` provee la **cabecera** `rpc/des_crypt.h`, pero **no los símbolos**:

```
/usr/bin/ld: undefined reference to `des_setparity'
/usr/bin/ld: undefined reference to `ecb_crypt'
# nm -D libtirpc.so  => ninguno de ecb_crypt/des_setparity/cbc_crypt exportado
```

*Conclusión:* el original solo compila en glibc antiguo (≤ Ubuntu 18.04). En Ubuntu 22.04 la
versión portada a OpenSSL es la única que compila. *Decisión:* mantener el port. Se verificó
además que el mapeo clave→DES del port es **idéntico byte a byte** al del `bruteforce.c`
original (little-endian, paridad impar), por lo que el cifrado sigue siendo interoperable con
otros grupos que usen el esquema canónico.

**#4 — `CLOCK_MONOTONIC` indefinido bajo `-std=c11` en glibc.**
`bruteforce_des_secuencial.c` incluye `<time.h>` antes de que `des_busqueda.h` defina
`_POSIX_C_SOURCE`. En glibc, `-std=c11` activa modo ANSI estricto y oculta la función POSIX:

```
error: 'CLOCK_MONOTONIC' undeclared (first use in this function)
```

En macOS (clang) compilaba igual porque su libc no es tan estricta. *Solución:* compilar con
`-std=gnu11` en la imagen Linux (mantiene C11 + extensiones/POSIX visibles).

**#5 — OpenMPI se niega a correr como root.**
Los contenedores corren como root; OpenMPI aborta por seguridad. *Solución:*
`ENV OMPI_ALLOW_RUN_AS_ROOT=1` y `ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1` (indicadas en el
enunciado).

**#6 — SSH sin contraseña entre contenedores.**
En vez de copiar `authorized_keys` a mano en cada nodo (frágil y manual), se **horneó una
llave RSA compartida en la imagen**. Todo contenedor de la misma imagen confía en los demás al
instante. Compromiso aceptado: la llave es común a la imagen (apropiado para un clúster de
laboratorio efímero, no para producción).

**#7 — La prueba de SSH imprimía vacío (`->` interpretado como redirección).**
El mensaje remoto `echo ... $(hostname) -> $w` hacía que el shell del worker interpretara `->`
como el operador de redirección `>`, mandando la salida a un archivo llamado `worker1`. El
`ssh` devolvía `rc=0` pero sin imprimir nada. *Solución:* quitar el `->` del comando remoto y
construir el mensaje del lado del maestro.

**#8 — Aislamiento de red en macOS y el "MPI hang".**
En macOS, `--network host` requiere Docker Desktop ≥ 4.34 y es problemático. Para la
simulación local se usó una **red bridge dedicada** (`10.42.0.0/24`) donde los contenedores se
resuelven por nombre. En el **despliegue físico** sí se usa `--network host` + se restringe MPI
a la subred del router con `--mca btl_tcp_if_include 192.168.1.0/24` y
`--mca oob_tcp_if_include 192.168.1.0/24` (ver §6.1 de por qué es obligatorio).

**#9 — El crib (`SEARCH`) es de tiempo de compilación.**
Para descifrar el texto de otro equipo hay que reconstruir con su palabra objetivo. Se agregó
un `ARG SEARCH` que inyecta el crib por cabecera (`-include crib.h`), evitando problemas de
comillas/espacios: `docker build --build-arg SEARCH="su palabra objetivo" ...`.

---

## 6. Discusión de resultados y conclusiones (§VI del enunciado)

### 6.1 ¿Por qué OpenMPI se congela sin `--mca btl_tcp_if_include`?

El motor de ruteo de OpenMPI (BTL TCP) inspecciona **todas** las interfaces de red de cada
máquina y publica *todas* sus direcciones a los demás procesos como posibles puntos de
contacto. Con Docker, cada host tiene además la interfaz puente `docker0` (típicamente
`172.17.0.0/16`), que es **privada a esa máquina**: la `172.17.x.x` del maestro no es
alcanzable desde la `172.17.x.x` de otra computadora. Cuando un worker intenta abrir la
conexión usando esa dirección publicada, el paquete no tiene ruta y la operación queda
esperando. Como el *handshake* de MPI es bloqueante y no hay timeout corto, el programa se
**congela indefinidamente sin error** (los datos criptográficos "se van" por una interfaz que
no lleva a ningún lado). Al pasar `--mca btl_tcp_if_include 192.168.1.0/24` se fuerza a MPI a
usar **únicamente** la subred física del router, eliminando las candidatas `docker0`/VirtualBox
y el bloqueo.

### 6.2 Problemas de red enfrentados

- **Aislamiento del bridge por defecto (NAT):** sin `--network host`, los contenedores quedan
  tras `docker0`/NAT y no se ven entre máquinas (Troubleshooting #8).
- **Interfaces fantasma `docker0`:** causan el "MPI hang" si no se restringe la subred (§6.1).
- **Firewall del sistema operativo:** con red host, los daemons de OpenMPI abren puertos
  dinámicos entrantes; Windows Defender / macOS Firewall los bloquean silenciosamente y
  producen `Connection refused`. Hay que permitir conexiones entrantes en red privada.
- **`--network host` en macOS/Windows:** requiere Docker Desktop ≥ 4.34 y habilitar *Enable
  Host Networking*.
- **Redirección accidental en un comando SSH remoto** (Troubleshooting #7), propio de nuestra
  automatización.

### 6.3 Tiempo local vs. clúster

| Configuración | Procesos | Candidatas | Tiempo (s) |
|---|---|---|---|
| Secuencial (1 contenedor) | 1 | 4 000 001 | 4.589417 |
| Clúster (3 contenedores) | 6 | 3 044 266 | 0.954614 |

Speedup aparente ≈ **4.81×** con 6 procesos. No es 6× por dos razones: (a) con **reparto por
bloques** el proceso dueño de la clave (`4 000 000` cae en un bloque alto) recorre bastante de
su sub-rango mientras otros terminan antes — el speedup depende de *dónde* cae la clave, no solo
de cuántos procesos hay (analizado a fondo en el informe de la Parte 1); (b) en un clúster
**físico** se suma la **latencia de red**: cada `MPI_Allreduce` de sincronización viaja por TCP
entre máquinas, costo que en un solo host (o en contenedores del mismo host) es casi nulo. En
el router real, ese overhead de comunicación crece y acerca el speedup real a algo menor que el
número de procesos, sobre todo si se sincroniza con mucha frecuencia.

### 6.4 ¿32 procesos MPI en una máquina de 4 núcleos?

El rendimiento **empeora**, no mejora. Con 32 procesos sobre 4 núcleos físicos hay
**oversubscription** 8:1: el sistema operativo multiplexa por tiempo y paga **cambio de
contexto** constante. La fuerza bruta DES es CPU-bound y mantiene los núcleos al 100%, así que
agregar procesos por encima de los núcleos no agrega cómputo: solo agrega competencia por la
misma CPU, fallos de caché y overhead de planificación. Por eso el hostfile declara
`max_slots` igual al número de núcleos lógicos, para que OpenMPI no lance más procesos que
núcleos.

### 6.5 Vulnerabilidades y retos logísticos del HPC heterogéneo

- **Superficie de ataque por SSH sin contraseña y root:** habilitar `PermitRootLogin yes`,
  `StrictHostKeyChecking no` y llaves compartidas facilita el clúster pero es inseguro fuera de
  un laboratorio aislado; un nodo comprometido compromete a todos.
- **Confianza entre nodos heterogéneos:** mezclar Windows/macOS/Linux obliga a homogeneizar el
  entorno (de ahí Docker); versiones distintas de OpenMPI o del binario rompen el clúster.
- **Red como cuello de botella y punto de fallo:** firewalls, NAT, interfaces múltiples y
  latencia variable hacen que "más máquinas" no sea "más rendimiento" automáticamente.
- **Oversubscription y recursos no uniformes:** nodos con distinto número de núcleos requieren
  balancear `slots`/`max_slots`; un nodo lento frena a todo el colectivo bloqueante.
- **Gestión de llaves y secretos:** distribuir llaves y mantener `authorized_keys` a escala es
  un problema operativo real.

### 6.6 Retrospectiva

Se logró el objetivo: una imagen Docker reproducible y un clúster que recupera la clave de
forma distribuida, con el flujo real SSH + `mpirun --hostfile`. Lo que más aportó fue aislar
cada problema de forma empírica (compilación, red, SSH) en vez de asumir. Lo más incómodo fue
el diagnóstico del "MPI hang" por interfaces `docker0` y los bloqueos silenciosos sin mensaje
de error. Mejorable: parametrizar el crib por línea de comandos (hoy es de compilación) y
aceptar un texto cifrado externo como entrada para atacar el reto de otro equipo sin
recompilar; ambos quedan anotados como trabajo futuro.

---

## 7. Cómo reproducir

```bash
cd proy/CC3069-Proyecto2
./cluster.sh build      # construye mpi-cluster-image
./cluster.sh up         # levanta maestro + worker1 + worker2
./cluster.sh validate   # tabla de validación del §IV
./cluster.sh ips        # IP de cada contenedor
./cluster.sh run 22 4000000   # ataque distribuido (recupera la clave)
./cluster.sh down       # destruye el clúster
```

El despliegue físico real (router + computadoras del equipo) está documentado en
`README-PART2.md`, sección B.
