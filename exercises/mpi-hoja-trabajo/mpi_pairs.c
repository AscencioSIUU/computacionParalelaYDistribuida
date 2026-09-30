#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef STUDENT_NAME
#define STUDENT_NAME "Ernesto"
#endif

#define MESSAGE "Hello World de " STUDENT_NAME

enum { MESSAGE_TAG = 0 };

int main(int argc, char **argv)
{
    int rank;
    int process_count;

    if (MPI_Init(&argc, &argv) != MPI_SUCCESS) {
        fprintf(stderr, "No se pudo inicializar MPI.\n");
        return EXIT_FAILURE;
    }

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &process_count);

    if (process_count < 2 || process_count % 2 != 0) {
        if (rank == 0) {
            fprintf(stderr,
                    "Error: mpi_pairs requiere al menos 2 procesos y una "
                    "cantidad par (recibidos: %d).\n",
                    process_count);
        }
        MPI_Finalize();
        return EXIT_FAILURE;
    }

    if (rank % 2 == 0) {
        const int destination = rank + 1;

        MPI_Send(MESSAGE, (int)sizeof(MESSAGE), MPI_CHAR, destination,
                 MESSAGE_TAG, MPI_COMM_WORLD);
        printf("Proceso par %d envia \"%s\" al proceso %d.\n",
               rank, MESSAGE, destination);
    } else {
        const int source = rank - 1;
        char received_message[sizeof(MESSAGE)];

        MPI_Recv(received_message, (int)sizeof(received_message), MPI_CHAR,
                 source, MESSAGE_TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("Proceso impar %d recibe \"%s\" del proceso %d.\n",
               rank, received_message, source);
    }

    MPI_Finalize();
    return EXIT_SUCCESS;
}
