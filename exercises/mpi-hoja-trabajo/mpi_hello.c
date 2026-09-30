#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef STUDENT_NAME
#define STUDENT_NAME "Ernesto"
#endif

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

    printf("Hello World de %s: proceso %d de %d.\n",
           STUDENT_NAME, rank, process_count);

    MPI_Finalize();
    return EXIT_SUCCESS;
}
