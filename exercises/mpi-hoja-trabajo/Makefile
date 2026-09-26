MPICC ?= mpicc
MPIRUN ?= mpirun
NP ?= 4
NAME ?= Nesstor07

CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic
PROGRAMS := mpi_hello mpi_broadcast mpi_pairs
NAME_DEFINE = '-DSTUDENT_NAME="$(NAME)"'

all: $(PROGRAMS)

$(PROGRAMS): %: %.c
	$(MPICC) $(CPPFLAGS) $(CFLAGS) $(NAME_DEFINE) $< $(LDFLAGS) $(LDLIBS) -o $@

run-hello: mpi_hello
	$(MPIRUN) -np $(NP) ./mpi_hello

run-broadcast: mpi_broadcast
	$(MPIRUN) -np $(NP) ./mpi_broadcast

run-pairs: mpi_pairs
	$(MPIRUN) -np $(NP) ./mpi_pairs

clean:
	$(RM) $(PROGRAMS)

.PHONY: all run-hello run-broadcast run-pairs clean
