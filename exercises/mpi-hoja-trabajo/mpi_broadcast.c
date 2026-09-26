#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef STUDENT_NAME
#define STUDENT_NAME "Nesstor07"
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

    if (rank == 0) {
        for (int destination = 1; destination < process_count; ++destination) {
            MPI_Send(MESSAGE, (int)sizeof(MESSAGE), MPI_CHAR, destination,
                     MESSAGE_TAG, MPI_COMM_WORLD);
            printf("Proceso 0 envia \"%s\" al proceso %d.\n",
                   MESSAGE, destination);
        }
    } else {
        char received_message[sizeof(MESSAGE)];

        MPI_Recv(received_message, (int)sizeof(received_message), MPI_CHAR, 0,
                 MESSAGE_TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("Proceso %d recibe \"%s\" del proceso 0.\n",
               rank, received_message);
    }

    MPI_Finalize();
    return EXIT_SUCCESS;
}
