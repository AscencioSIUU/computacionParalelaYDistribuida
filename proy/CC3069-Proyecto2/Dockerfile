# ---------------------------------------------------------------------------
# CC3069 - Proyecto 2 Parte 2: imagen estandarizada del cluster MPI.
# Encapsula compilador, Open MPI y SSH para que el entorno sea identico en
# Windows, macOS y Linux. Todos los integrantes construyen ESTA imagen.
#   docker build -t mpi-cluster-image .
# Para descifrar el texto de OTRO equipo (fase de descifrado cruzado):
#   docker build --build-arg SEARCH="su palabra objetivo" -t mpi-cluster-image .
# ---------------------------------------------------------------------------
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
# Frase clave (crib) que se busca en el texto descifrado. Por defecto, la nuestra.
ARG SEARCH="Proyecto 2 de Computacion Paralela"

# Dependencias base. El enunciado pide build-essential openmpi-bin libopenmpi-dev
# openssh-server; ademas:
#   - libssl-dev: el DES esta portado a OpenSSL (-lcrypto). Sin esto no compila.
#   - openssh-client: mpirun lanza los orted en los workers por ssh.
#   - iproute2/iputils-ping: diagnostico de red (ss, ip, ping) para troubleshooting.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        openmpi-bin \
        libopenmpi-dev \
        openssh-server \
        openssh-client \
        libssl-dev \
        iproute2 \
        iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Open MPI prohibe correr como root salvo que se declare explicitamente. Como los
# contenedores corren como root y sin volumenes, se anula la restriccion.
ENV OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# SSH sin intervencion: login root permitido y sin verificacion manual de huellas.
RUN mkdir -p /var/run/sshd \
    && sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && printf '\nHost *\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n    LogLevel ERROR\n' >> /etc/ssh/ssh_config

# Una sola llave compartida HORNEADA en la imagen: todo contenedor construido de
# esta imagen confia en los demas sin copiar llaves a mano en cada arranque.
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh \
    && ssh-keygen -t rsa -b 2048 -N "" -C mpi-cluster -f /root/.ssh/id_rsa \
    && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys \
    && chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa

# Codigo del Proyecto 2 (reutilizado tal cual de la Parte 1).
WORKDIR /cluster
COPY des_busqueda.h bruteforce_des_mpi.c bruteforce_des_secuencial.c texto.txt ./

# Inyecta el crib via cabecera -include (soporta espacios sin problemas de quoting)
# y compila el binario distribuido como /cluster/bruteforce (nombre del enunciado).
RUN printf '#define SEARCH "%s"\n' "$SEARCH" > /cluster/crib.h \
    && mpicc -std=gnu11 -O2 -Wall -Wextra -include /cluster/crib.h \
        bruteforce_des_mpi.c -o /cluster/bruteforce -lcrypto \
    && mpicc -std=gnu11 -O2 -include /cluster/crib.h \
        bruteforce_des_secuencial.c -o /cluster/bruteforce_secuencial -lcrypto

EXPOSE 22
# Arranca el demonio SSH en primer plano para que el contenedor quede como nodo.
CMD ["/usr/sbin/sshd", "-D", "-e"]
