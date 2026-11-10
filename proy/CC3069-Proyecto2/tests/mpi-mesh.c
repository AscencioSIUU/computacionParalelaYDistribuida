#include <mpi.h>
#include <stdio.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size, received = -1, sum = 0, length;
    char hostname[MPI_MAX_PROCESSOR_NAME];
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(hostname, &length);
    int next = (rank + 1) % size;
    int previous = (rank + size - 1) % size;
    MPI_Sendrecv(&rank, 1, MPI_INT, next, 0, &received, 1, MPI_INT,
                 previous, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    if (received != previous) {
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    MPI_Allreduce(&rank, &sum, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    if (sum != size * (size - 1) / 2) {
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    printf("Mesh rank %d/%d on %s\n", rank, size, hostname);
    if (rank == 0) {
        printf("MPI mesh PASS: ranks=%d\n", size);
    }
    MPI_Finalize();
    return 0;
}
