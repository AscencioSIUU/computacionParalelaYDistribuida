# macOS: OpenSSL por Homebrew. Linux/WSL: make OPENSSL=/usr
OPENSSL ?= $(shell brew --prefix openssl@3 2>/dev/null || echo /usr)
MPICC   ?= mpicc
MPIRUN  ?= mpirun
NP      ?= 4

CFLAGS ?= -std=c11 -O2 -Wall -Wextra
SSL     = -I$(OPENSSL)/include -L$(OPENSSL)/lib -lcrypto

PROGRAMS := bruteforce_des_secuencial bruteforce_des_mpi

all: $(PROGRAMS)

bruteforce_des_secuencial: bruteforce_des_secuencial.c des_busqueda.h
	$(CC) $(CFLAGS) $< -o $@ $(SSL)

bruteforce_des_mpi: bruteforce_des_mpi.c des_busqueda.h
	$(MPICC) $(CFLAGS) $< -o $@ $(SSL)

run-secuencial: bruteforce_des_secuencial
	./bruteforce_des_secuencial $(ARGS)

run-mpi: bruteforce_des_mpi
	$(MPIRUN) -np $(NP) ./bruteforce_des_mpi $(ARGS)

bench: all
	./bench.sh $(ARGS)

clean:
	$(RM) $(PROGRAMS)

.PHONY: all run-secuencial run-mpi bench clean
