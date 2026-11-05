# Guía para la clase — Parte 3 por Wi-Fi (router D-Link)

Esta es la guía paso a paso para el día del súper-clúster. La explicación del
algoritmo y la discusión teórica están en [README-PART3.md](README-PART3.md).
Todos los comandos se ejecutan desde `proy/CC3069-Proyecto2`.

## 0. Antes de salir de casa (cada integrante)

```bash
git pull
git rev-parse --short HEAD          # todos deben tener el mismo commit
bash ./cluster.sh up                # Windows: .\cluster.ps1 up
bash ./cluster.sh validate          # captura de pantalla de esta salida
bash ./cluster.sh down
```

- Computadora conectada al cargador, sin suspensión automática.
- Docker Desktop abierto y la imagen ya construida (en Mac, la imagen amd64
  tarda varios minutos bajo emulación).

## 1. Conexión al D-Link

1. Conectarse a la **red principal** del D-Link, de preferencia la de 5 GHz.
   **No usar la red de invitados**, porque aísla a los clientes entre sí.
2. Si el router lo permite, el **master se conecta por cable** al router. Todo
   el tráfico de control pasa por él.
3. Cada quien anota su IP y su máscara:

   | Sistema | Comando |
   |---|---|
   | macOS | `ipconfig getifaddr en0` y `ipconfig getoption en0 subnet_mask` |
   | Linux | `ip -4 addr` |
   | Windows | `ipconfig` |

   El D-Link suele usar `192.168.0.0/24`, no `192.168.1.0/24`. En todos los
   comandos se usa la subred real.
4. Antes de levantar Docker, se prueba que las computadoras se vean entre sí:
   ```bash
   ping -c 5 <IP_DE_OTRA_COMPUTADORA>       # Windows: ping -n 5 <IP>
   ```
   Si el ping falla entre dos computadoras de la misma red, revisar en la página
   del router (normalmente `http://192.168.0.1`) que **Wireless Isolation /
   AP Isolation** esté desactivado. Sin esto no hay clúster.
5. En Windows, la red Wi-Fi debe estar marcada como **Privada**, no Pública.

## 2. Registro de lo que se hace (logs)

Cada computadora guarda su propia carpeta. Así nadie pisa el archivo de otro
al hacer `git push`.

**macOS / Linux**, al abrir la terminal:

```bash
export LOG="logs/clase-$(date +%Y%m%d)/$(hostname -s)"
mkdir -p "$LOG"
run() { { echo; echo "### $(date '+%F %T') \$ $*"; } | tee -a "$LOG/comandos.log"
        "$@" 2>&1 | tee -a "$LOG/comandos.log"; }
```

A partir de ahí, cada comando importante se antepone con `run`. Ejemplo:
`run docker exec mpi_node ip -4 addr`. La salida se ve en pantalla y además
queda guardada con fecha y hora en `$LOG/comandos.log`. Si se abre otra
terminal, se vuelven a pegar las tres líneas.

**Windows (PowerShell 7)** graba toda la sesión:

```powershell
$LOG = "logs\clase-$(Get-Date -Format yyyyMMdd)\$env:COMPUTERNAME"
New-Item -ItemType Directory -Force $LOG | Out-Null
Start-Transcript -Path "$LOG\terminal.txt" -Append
# ... todos los comandos de la clase ...
Stop-Transcript
```

Datos que cada nodo registra al inicio:

```bash
run git rev-parse --short HEAD
run docker image ls
run docker exec mpi_node ip -4 addr        # modo LAN
```

- **Fotos y capturas:** van en `logs/clase-AAAAMMDD/fotos/`.
- **Problemas:** se anotan en cuanto aparecen, con hora, síntoma, causa y
  solución, en la tabla §6.6 de `README-PART3.md`. En el log quedan los
  comandos con su fecha y hora, lo que ayuda a reconstruirlos después.
- **Nunca se guardan ni se suben claves privadas** (`id_ed25519`,
  `host_ed25519_key`). Los archivos `.pub` están en `.gitignore`.

## 3. ¿Qué ruta usamos?

| Ruta | Nodos | Requisito | Cuándo |
|---|---|---|---|
| **A. LAN** | 5–6 | Cada nodo con **Linux nativo** o **VM Linux en modo puente** con Docker adentro | Súper-clúster (lo que pide el enunciado) |
| **B. Túnel** | 2 | Docker Desktop en Windows (master) + Mac (worker) | Prueba del equipo; Docker Desktop no puede unirse a la ruta A |

Con Docker Desktop (Windows o Mac), el contenedor no recibe la IP del Wi-Fi, así
que MPI no lo puede alcanzar en la ruta A. La explicación está en
[README-PART2.md](README-PART2.md) §B. Una VM en modo puente sobre Wi-Fi a veces
no recibe IP del router, porque algunos routers no aceptan varias direcciones
MAC por cliente Wi-Fi. Se comprueba temprano con un ping desde otra
computadora hacia la IP de la VM.

## 4. Ruta A — súper-clúster LAN

### 4.1 En cada nodo

```bash
run docker compose -f docker-compose.lan.yml up -d --build --wait --wait-timeout 60
run docker exec mpi_node ip -4 addr                # debe mostrar la IP del D-Link

docker exec mpi_node cat /root/.ssh/id_ed25519.pub      > "$(hostname -s).client.pub"
docker exec mpi_node cat /root/.ssh/host_ed25519_key.pub > "$(hostname -s).host.pub"
run ssh-keygen -lf "$(hostname -s).client.pub"
run ssh-keygen -lf "$(hostname -s).host.pub"
```

Los dos `.pub` se comparten con los demás integrantes (USB, chat, AirDrop).
Son solo claves públicas.

### 4.2 Firewall (cada nodo, una vez por cada otra IP)

```bash
sudo ufw allow from <IP_OTRO> to any port 22 proto tcp
sudo ufw allow from <IP_OTRO> to any port 20000:20099 proto tcp
sudo ufw allow from <IP_OTRO> to any port 21000:21099 proto tcp
```

### 4.3 Confianza (cada nodo registra a los demás)

Primero se comparan las huellas con el dueño de cada clave, mirando su
pantalla. Después:

```bash
run docker exec mpi_node mpi-trust <IP_OTRO> "$(cat otro.client.pub)" "$(cat otro.host.pub)"
```

### 4.4 Hostfile (solo el master)

La IP del master va **primero**. `slots` es el número de núcleos de cada
máquina (`nproc` en Linux).

```bash
cat > cluster_hosts.lan <<'EOF'
192.168.0.10 slots=4 max_slots=4
192.168.0.11 slots=4 max_slots=4
192.168.0.12 slots=4 max_slots=4
192.168.0.13 slots=4 max_slots=4
192.168.0.14 slots=4 max_slots=4
EOF
cp cluster_hosts.lan "$LOG/"
run docker cp cluster_hosts.lan mpi_node:/cluster/cluster_hosts
```

### 4.5 Comprobación (master)

```bash
# SSH sin preguntas a cada worker
run docker exec mpi_node ssh 192.168.0.11 hostname

# Latencia del Wi-Fi hacia cada worker (dato para el overhead)
run docker exec mpi_node ping -c 20 192.168.0.11

# Primera búsqueda distribuida: debe imprimir "Clave encontrada: 12345"
H=/cluster/cluster_hosts; NET=192.168.0.0/24; NP=20     # NP = suma de slots
run docker exec mpi_node mpi-run $H $NET $NP 16 12345
```

Si SSH funciona pero MPI se congela, la causa suele ser el firewall (puertos
20000–20099 o 21000–21099) o una subred mal escrita. Se corta con `Ctrl+C`,
se anota el problema y se revisa.

## 5. Ruta B — túnel Windows (master) ↔ Mac (worker)

La IP de la Mac cambia al conectarse al D-Link, por eso `up` se repite con la
IP nueva. La identidad se conserva, así que no hay que volver a emparejar si
ya se hizo.

**Mac:**
```bash
run ipconfig getifaddr en0
run bash ./desktop.sh worker up <IP_MAC>
run bash ./desktop.sh worker identity          # pasar "Codigo publico" al master
run bash ./desktop.sh worker trust-code 'CODIGO_DEL_MASTER' --verified   # solo la primera vez
```

En macOS, si el firewall está activo, hay que permitir las conexiones entrantes
de Docker.

**Windows (master):**
```powershell
.\desktop.ps1 up
.\desktop.ps1 identity
.\desktop.ps1 trust -PeerCode 'CODIGO_DE_LA_MAC' -Verified    # solo la primera vez
.\desktop.ps1 connect -PeerAddress <IP_MAC>
.\desktop.ps1 validate
.\desktop.ps1 run -Bits 22 -Key 4000000 -MasterSlots 2 -WorkerSlots 4
```

Se usa `-MasterSlots 2` porque uno de los slots del master solo despacha
trabajo. Con `1 + 1`, únicamente la Mac calcula.

## 6. Stress test (master, ruta A)

Barrido completo de 2^26 llaves con una clave que no está en el rango. Cada
corrida se guarda en su propio archivo:

```bash
stress() { docker exec -e "$2" mpi_node mpi-run "$H" "$NET" "$NP" 26 999999999 2>&1 | tee "$LOG/stress-$1.txt"; }
stress estatico     BRUTEFORCE=/cluster/bruteforce_estatico
stress chunk1024    CHUNK=1024
stress chunk65536   CHUNK=65536
stress chunk1048576 CHUNK=1048576
```

Base de un solo nodo para calcular el speedup (solo la máquina del master):

```bash
echo "<IP_MASTER> slots=4 max_slots=4" > solo.txt
docker cp solo.txt mpi_node:/cluster/solo.txt
docker exec mpi_node mpi-run /cluster/solo.txt $NET 4 26 999999999 2>&1 | tee "$LOG/stress-1nodo.txt"
```

De cada archivo se pasan `Tiempo`, `Candidatas probadas` y la tabla
`Reparto dinamico por worker` a §6.5 de `README-PART3.md`.

- Llaves/s = 67 108 864 / Tiempo.
- Speedup = Tiempo de 1 nodo / Tiempo del clúster.

Si `CHUNK=1024` sale más lento que `CHUNK=65536`, es el overhead del Wi-Fi: el
tiempo del ping se acerca al tiempo que tarda un worker en calcular un chunk.

## 7. Apagar y subir la evidencia

```bash
docker compose -f docker-compose.lan.yml down    # ruta A
bash ./desktop.sh worker down                    # ruta B (Mac); Windows: .\desktop.ps1 down

git pull
git add logs/ README-PART3.md
git commit -m "docs: logs y resultados del stress test en clase"
git push
```

Si el `push` choca con el de otro integrante, se hace `git pull` y se repite.
Las carpetas por computadora evitan conflictos.

## 8. Problemas típicos por Wi-Fi

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Ping falla entre laptops | Red de invitados o AP isolation | Red principal; desactivar isolation en el D-Link |
| La IP cambió | DHCP al reconectar | Revisar la IP antes del hostfile; reserva DHCP en el router |
| SSH `Connection refused` | Firewall o contenedor caído | `docker ps`; reglas de firewall; red Privada en Windows |
| SSH pide confirmar la clave | Clave de servidor no registrada | `mpi-trust` después de comparar huellas |
| SSH OK pero MPI se congela | Puertos MPI bloqueados o subred incorrecta | Puertos 20000–20099 y 21000–21099; subred real |
| No hay interfaz MPI válida | Docker Desktop sin IP del Wi-Fi | Ruta A solo con Linux nativo o VM en modo puente |
| Tiempos muy variables | Wi-Fi compartido, latencia con picos | Master por cable, banda de 5 GHz, chunk más grande, repetir corridas |
| Un nodo recibe pocos chunks | Nodo lento o con mala señal | Es lo esperado del modelo dinámico; anotarlo como resultado |
