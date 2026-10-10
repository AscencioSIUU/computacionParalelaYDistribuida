/*----------------------------------------------------------------------
 * UNIVERSIDAD DEL VALLE DE GUATEMALA
 * Curso:       CC3069 - Computacion Paralela y Distribuida
 * Proyecto:    Busqueda de clave DES por fuerza bruta - version Open MPI
 * Descripcion: reparto POR BLOQUES CONTIGUOS (como el bruteforce_.c del
 *              enunciado): el proceso r prueba el sub-rango
 *              [r*range, (r+1)*range). Cada SYNC_INTERVAL pasos,
 *              MPI_Allreduce(MPI_MIN) comparte la menor clave encontrada
 *              y todos terminan a la vez. El proceso 0 cifra el texto y lo
 *              difunde con MPI_Bcast. Se reporta la menor clave valida.
 *
 *              El reparto por bloques hace que el tiempo dependa de DONDE
 *              cae la clave: una clave baja la halla el proceso 0 casi de
 *              inmediato; una clave alta obliga a su proceso duenno a
 *              recorrer casi todo su bloque. Por eso el Speedup aparente
 *              cambia con la clave (ver informe).
 *              Uso: mpirun -np N ./bruteforce_des_mpi [bits] [clave] [archivo]
 *----------------------------------------------------------------------*/
#include <mpi.h>
#include "des_busqueda.h"

#define SYNC_INTERVAL 4096

int main(int argc, char **argv)
{
    config_t cfg;
    if (parse_args(argc, argv, &cfg) != 0) return EXIT_FAILURE;

    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    /* El proceso 0 lee el texto, lo cifra y difunde longitud + cifrado. */
    unsigned char cipher[MAX_TEXT + 1];
    int len = 0;
    if (rank == 0) {
        unsigned char text[MAX_TEXT + 1];
        len = load_text(cfg.textfile, text);
        memcpy(cipher, text, len);
        des_encrypt(cfg.secret, cipher, len);
    }
    MPI_Bcast(&len, 1, MPI_INT, 0, MPI_COMM_WORLD);
    MPI_Bcast(cipher, len, MPI_UNSIGNED_CHAR, 0, MPI_COMM_WORLD);

    const uint64_t total = UINT64_C(1) << cfg.bits;
    if (rank == 0 && cfg.secret >= total)
        fprintf(stderr, "Aviso: la clave %" PRIu64 " esta fuera de 2^%u; "
                "no se encontrara.\n", cfg.secret, cfg.bits);

    /* Reparto por bloques contiguos. Todos dan el mismo numero de pasos
     * para que las colectivas coincidan aunque total no sea multiplo de
     * size; cada quien recorre candidate = mylower + j dentro de su bloque. */
    const uint64_t range  = (total + size - 1) / (uint64_t)size;
    const uint64_t mylower = (uint64_t)rank * range;
    const uint64_t myupper = mylower + range;          /* exclusivo */

    unsigned char tmp[MAX_TEXT + 1];
    uint64_t local_found = UINT64_MAX, global_found = UINT64_MAX;
    uint64_t local_tested = 0;

    MPI_Barrier(MPI_COMM_WORLD);
    double start = MPI_Wtime();

    for (uint64_t j = 0; j < range; j++) {
        if (j % SYNC_INTERVAL == 0) {
            MPI_Allreduce(&local_found, &global_found, 1, MPI_UINT64_T,
                          MPI_MIN, MPI_COMM_WORLD);
            if (global_found != UINT64_MAX) break;
        }
        uint64_t candidate = mylower + j;
        if (candidate >= total || candidate >= myupper) continue;
        local_tested++;
        if (try_key(candidate, cipher, len, tmp)) {
            local_found = candidate;
            j = (j / SYNC_INTERVAL + 1) * SYNC_INTERVAL - 1; /* al prox. sync */
        }
    }
    if (global_found == UINT64_MAX)
        MPI_Allreduce(&local_found, &global_found, 1, MPI_UINT64_T,
                      MPI_MIN, MPI_COMM_WORLD);

    double local_elapsed = MPI_Wtime() - start, elapsed = 0.0;
    uint64_t tested = 0;
    MPI_Reduce(&local_elapsed, &elapsed, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_tested, &tested, 1, MPI_UINT64_T, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        printf("Rango explorado: 2^%u = %" PRIu64 " candidatas\n", cfg.bits, total);
        if (global_found != UINT64_MAX) {
            memcpy(tmp, cipher, len);
            des_decrypt(global_found, tmp, len); tmp[len] = '\0';
            printf("Clave encontrada: %" PRIu64 "\n", global_found);
            printf("Mensaje: %s\n", tmp);
        } else {
            printf("No se encontro la clave.\n");
        }
        printf("Ejecucion: paralela MPI con %d procesos (reparto por bloques)\n", size);
        printf("Candidatas probadas: %" PRIu64 "\n", tested);
        printf("Tiempo: %.6f segundos\n", elapsed);
    }

    MPI_Finalize();
    return EXIT_SUCCESS;
}
