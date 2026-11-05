FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG SEARCH="Proyecto 2 de Computacion Paralela"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        openmpi-bin \
        libopenmpi-dev \
        openssh-server \
        openssh-client \
        libssl-dev \
        iproute2 \
        iputils-ping \
    && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_*

ENV OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

RUN printf 'Host *\n    BatchMode yes\n    StrictHostKeyChecking yes\n    ConnectTimeout 5\n    IdentityFile /root/.ssh/id_ed25519\n    IdentitiesOnly yes\n' > /etc/ssh/ssh_config \
    && printf 'Port 22\nHostKey /root/.ssh/host_ed25519_key\nPermitRootLogin prohibit-password\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\nAuthorizedKeysFile .ssh/authorized_keys\nUsePAM no\nSubsystem sftp internal-sftp\n' > /etc/ssh/sshd_config

COPY docker/*.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/*.sh \
    && chmod 755 /usr/local/bin/*.sh \
    && ln -s /usr/local/bin/mpi-trust.sh /usr/local/bin/mpi-trust \
    && ln -s /usr/local/bin/mpi-run.sh /usr/local/bin/mpi-run \
    && ln -s /usr/local/bin/mpi-desktop.sh /usr/local/bin/mpi-desktop

WORKDIR /cluster
COPY des_busqueda.h bruteforce_des_mpi.c bruteforce_des_secuencial.c texto.txt ./
RUN printf '#define SEARCH "%s"\n' "$SEARCH" > /cluster/crib.h \
    && mpicc -std=gnu11 -O2 -Wall -Wextra -include /cluster/crib.h \
        bruteforce_des_mpi.c -o /cluster/bruteforce -lcrypto \
    && mpicc -std=gnu11 -O2 -include /cluster/crib.h \
        bruteforce_des_secuencial.c -o /cluster/bruteforce_secuencial -lcrypto

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
