# Proyecto 2: Open MPI con Docker

El proyecto utiliza **Open MPI**, no OpenMP. MPI distribuye procesos entre
computadoras; OpenMP distribuye hilos dentro de una computadora. El programa
actual no implementa una versión híbrida MPI/OpenMP.

Docker estandariza Ubuntu 22.04, Open MPI 4.1.2, OpenSSL y las rutas de los
binarios. Cada nodo genera sus propias claves SSH al arrancar. Ninguna clave
privada se incluye en la imagen ni se comparte entre integrantes.

## Archivos

| Archivo | Función |
|---|---|
| `Dockerfile` | Compila `/cluster/bruteforce` y `/cluster/bruteforce_secuencial`. |
| `docker-compose.yml` | Simula tres nodos en una computadora, sin publicar puertos. |
| `docker-compose.lan.yml` | Ejecuta un nodo por computadora con Docker nativo de Linux. |
| `cluster.ps1` | Operación local desde PowerShell 7 en Windows. |
| `cluster.sh` | Operación local desde Bash en Linux o macOS. |
| `docker/entrypoint.sh` | Genera identidades SSH persistentes por nodo. |
| `docker/mpi-trust.sh` | Autoriza claves públicas y fija la identidad del servidor. |
| `docker/mpi-run.sh` | Normaliza el hostfile y limita interfaces y puertos MPI. |
| `cluster_hosts` | Tres nodos locales, dos procesos por nodo. |
| `cluster_hosts.lan.example` | Ejemplo de dos computadoras, dos procesos por nodo. |
| `.gitattributes` | Conserva LF en scripts, hostfiles y configuración Docker. |

## A. Prueba local

Docker Desktop con contenedores Linux es suficiente para esta prueba.
No requiere host networking ni cambios al firewall.

Desde la carpeta del proyecto, en PowerShell 7:

```powershell
.\cluster.ps1 up
.\cluster.ps1 validate
.\cluster.ps1 run -Bits 22 -Key 4000000
.\cluster.ps1 down
```

Desde Bash:

```bash
bash ./cluster.sh up
bash ./cluster.sh validate
bash ./cluster.sh run 22 4000000
bash ./cluster.sh down
```

`up` construye la imagen, espera hasta 60 segundos por nodos saludables y registra
las claves públicas directamente desde Docker. No utiliza `ssh-keyscan` para
establecer confianza. Su uso en el healthcheck solo verifica que SSH responde.
`validate` comprueba SSH, distribución de seis procesos, recuperación de la clave
12345 y búsqueda exhaustiva de exactamente 1024 candidatas.

Los volúmenes conservan las identidades y la confianza después de `down`.
`up` puede repetirse sin duplicar claves. Los comandos `build`, `trust`, `ips` y
`shell` también están disponibles. Una ejecución directa de `docker compose up`
requiere después `.\cluster.ps1 trust` o `bash ./cluster.sh trust`.

La subred local es `10.42.0.0/24`. Si coincide con una VPN u otra red existente,
el nuevo rango debe actualizarse tanto en Compose como en ambos lanzadores.
El hostfile y los procesos predeterminados presuponen al menos dos CPU
disponibles por contenedor.

## B. Varias computadoras en la misma LAN

### Plataforma y requisitos

El despliegue LAN utiliza **Docker Engine nativo en Linux**. En Windows o macOS,
cada participante necesita una VM Linux con adaptador de red en modo **puente**,
con Docker instalado dentro de esa VM. Una VM con NAT o WSL con su configuración
predeterminada no equivale a este despliegue.

Docker Desktop host networking no expone directamente las interfaces físicas del
host. Por eso no se utiliza para seleccionar la subred LAN en MPI.
Referencia: [limitaciones de Docker Desktop host networking](https://docs.docker.com/engine/network/drivers/host/#limitations).

Cada nodo necesita:

- La misma revisión del proyecto, el mismo `SEARCH` y versiones MPI compatibles.
- Una IP Linux accesible desde todos los participantes, de preferencia reservada
  por DHCP. En una VM se utiliza la IP de Linux, no la IP de Windows.
- Una LAN sin aislamiento entre clientes. Las redes de invitados suelen bloquear
  la comunicación entre computadoras.
- El puerto TCP 22 libre para el contenedor. Si ya existe un servidor SSH del
  sistema en ese puerto, el conflicto debe resolverse antes del arranque, sin
  interrumpir una sesión remota necesaria.
- Al menos tantas CPU disponibles como `slots` asignados en el hostfile.

### 1. Firewall

Solo se permite tráfico entre las IP de los nodos participantes:

| TCP | Uso |
|---|---|
| `22` | Inicio remoto por SSH |
| `20000–20099` | Datos MPI |
| `21000–21099` | Control MPI |

En Linux con UFW, el siguiente ejemplo autoriza únicamente al otro nodo
`192.168.1.11`. En el segundo nodo se utiliza la IP del primero:

```bash
sudo ufw allow from 192.168.1.11 to any port 22 proto tcp
sudo ufw allow from 192.168.1.11 to any port 20000:20099 proto tcp
sudo ufw allow from 192.168.1.11 to any port 21000:21099 proto tcp
```

Las mismas restricciones aplican al firewall del hipervisor si filtra el tráfico
de la VM. No se requiere desactivar el firewall ni configurar port forwarding en
el router. MPI no cifra su tráfico TCP; esta configuración se limita a una LAN
de confianza, no a Internet.

### 2. Arranque de un nodo por computadora

Desde la carpeta del proyecto dentro de Linux:

```bash
ip -4 addr
docker compose -f docker-compose.lan.yml up -d --build --wait --wait-timeout 60
docker exec mpi_node ip -4 addr
```

La última salida debe mostrar una interfaz de la subred LAN elegida. SSH arranca
automáticamente. El volumen `node-ssh` conserva las claves privadas solo en esa
computadora.

### 3. Intercambio de claves públicas

En cada nodo, los siguientes comandos exportan **solo claves públicas**:

```bash
docker exec mpi_node cat /root/.ssh/id_ed25519.pub > node.client.pub
docker exec mpi_node cat /root/.ssh/host_ed25519_key.pub > node.host.pub
ssh-keygen -lf node.client.pub
ssh-keygen -lf node.host.pub
```

Los dos archivos se entregan a los demás integrantes con un nombre que identifique
al propietario, por ejemplo `worker1.client.pub` y `worker1.host.pub`. Cada
integrante compara ambas huellas con el propietario por un canal independiente.
Nunca se transfieren `id_ed25519`, `host_ed25519_key` ni el volumen completo.

Después de verificar las huellas, cada nodo registra a los demás. Ejemplo para
registrar al nodo `192.168.1.11`:

```bash
docker exec mpi_node mpi-trust 192.168.1.11 \
  "$(cat worker1.client.pub)" "$(cat worker1.host.pub)"
```

El comando permite SSH desde ese integrante y fija su clave de servidor. Para el
ejemplo de dos computadoras, el worker también registra al maestro utilizando
su IP y sus dos archivos públicos. La herramienta rechaza una clave de servidor
distinta de la previamente registrada; no la reemplaza automáticamente.

### 4. Hostfile en el maestro

```bash
cp cluster_hosts.lan.example cluster_hosts.lan
```

El archivo debe contener las IP Linux reales y un número de procesos que respete
las CPU disponibles. Ejemplo:

```text
192.168.1.10 slots=2 max_slots=2
192.168.1.11 slots=2 max_slots=2
```

El maestro copia el archivo al contenedor:

```bash
docker cp cluster_hosts.lan mpi_node:/cluster/cluster_hosts
```

El lanzador normaliza CRLF al leerlo, aunque `.gitattributes` ya exige LF para los
hostfiles versionados.

### 5. Comprobación y ejecución

Desde el maestro, SSH debe devolver el hostname del worker sin preguntas:

```bash
docker exec mpi_node ssh 192.168.1.11 hostname
```

Para el ejemplo de cuatro procesos y subred `192.168.1.0/24`:

```bash
docker exec mpi_node mpi-run /cluster/cluster_hosts 192.168.1.0/24 4 16 12345
docker exec mpi_node mpi-run /cluster/cluster_hosts 192.168.1.0/24 4 22 4000000
```

El total de procesos debe coincidir con la suma de `slots`. La subred debe
corresponder a la máscara real de Linux; no siempre es `/24`. `mpi-run` selecciona
esa subred tanto para datos como para control y usa los rangos del firewall.
Un SSH exitoso no prueba por sí solo los puertos MPI: la primera búsqueda
distribuida debe recuperar la clave 12345.

Apagado en cada computadora:

```bash
docker compose -f docker-compose.lan.yml down
```

### Diagnóstico

| Síntoma | Comprobación |
|---|---|
| SSH rechaza la clave del servidor | Comparación de huellas con el propietario. No debe desactivarse la verificación. |
| `Permission denied` | Clave pública del cliente autorizada en el destino mediante `mpi-trust`. |
| SSH no conecta | IP Linux, puerto 22, firewall y aislamiento del router. |
| No hay interfaz MPI válida | Subred visible con `docker exec mpi_node ip -4 addr`. |
| SSH funciona pero MPI se congela | Rangos TCP en todos los nodos y subred correcta, sin Docker Desktop host networking. |
| Puerto 22 ocupado | Servidor SSH existente en el host Linux. |
| Clave cambió tras perder un volumen | Verificación independiente y eliminación de la entrada antigua con `ssh-keygen -R IP` dentro del contenedor antes de registrar la nueva. |

## C. Alcance del ejercicio DES

`SEARCH` se fija al construir:

```bash
docker build --build-arg SEARCH="su palabra objetivo" -t mpi-cluster-image .
```

El programa actual lee **texto plano**, lo cifra con la clave indicada y después
busca esa clave. `texto.txt` no acepta directamente el cifrado de otro equipo.
El texto plano debe contener `SEARCH` dentro de los primeros 160 bytes.
La importación de un cifrado externo requiere un cambio separado al programa.

## D. Alcance de las pruebas

La regresión automatizada se ejecuta desde PowerShell 7:

```powershell
.\tests\docker-smoke.ps1
```

La prueba construye y arranca el clúster local, verifica que la imagen no contenga
claves, comprueba identidades independientes y persistentes, rechaza cambios de
identidad y claves con saltos de línea, prueba un hostfile CRLF y ejecuta las
búsquedas MPI. Al terminar elimina los contenedores y conserva los volúmenes.
`-KeepRunning` conserva también los contenedores. No debe ejecutarse sobre un
clúster local que tenga trabajos activos, porque recrea sus contenedores.

La prueba local valida contenedores, SSH con identidades independientes y MPI en
una red Docker. No demuestra conectividad entre computadoras físicas.
La validación LAN final requiere al menos dos nodos reales y las comprobaciones
de la sección B. La bitácora anterior conserva evidencia histórica, no sustituye
esta guía actualizada.
