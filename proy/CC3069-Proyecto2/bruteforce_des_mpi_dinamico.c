/*----------------------------------------------------------------------
 * UNIVERSIDAD DEL VALLE DE GUATEMALA
 * Curso:       CC3069 - Computacion Paralela y Distribuida
 * Proyecto:    Busqueda de clave DES por fuerza bruta - Parte 3 (Open MPI)
 * Descripcion: modelo MASTER-WORKER con balance de carga DINAMICO.
 *              El proceso 0 (master) administra el espacio de llaves
 *              [0, 2^bits) y lo reparte en chunks pequennos BAJO DEMANDA:
 *              cada worker pide trabajo, prueba su chunk y reporta el
 *              resultado en la misma peticion con la que pide el siguiente.
 *              Un nodo rapido pide mas chunks que uno lento, asi que el
 *              tiempo total ya no queda atado a la maquina mas lenta.
 *              Al encontrar la clave el master deja de repartir y responde
 *              STOP a cada worker en su siguiente peticion.
 *              Solo hay mensajes master <-> worker; los workers no se hablan.
 *              Uso: [CHUNK=n] mpirun -np N ./bruteforce_des_mpi_dinamico
 *                   [bits] [clave] [archivo]          (N >= 2)
 *----------------------------------------------------------------------*/
#include <mpi.h>
#include "des_busqueda.h"

#define DEFAULT_CHUNK (UINT64_C(1) << 16)   /* llaves por chunk sin CHUNK   */
#define TAG_RESULT 1    /* worker -> master: {clave hallada o MAX, probadas} */
#define TAG_WORK   2    /* master -> worker: [inicio, fin) del chunk         */
#define TAG_STOP   3    /* master -> worker: ya no hay trabajo               */

/* Tamanno del chunk: variable de entorno CHUNK o DEFAULT_CHUNK. Solo la lee
 * el master, que es quien corta los chunks. */
static uint64_t read_chunk(void)
{
    const char *s = getenv("CHUNK");
    if (!s || !*s) return DEFAULT_CHUNK;
    char *end;
    errno = 0;
    unsigned long long c = strtoull(s, &end, 10);
    if (errno || *end || s[0] == '-' || c == 0) {
        fprintf(stderr, "CHUNK invalido: %s (entero > 0)\n", s);
        MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    }
    return (uint64_t)c;
}

/* Master: atiende peticiones de cualquier worker en el orden en que llegan.
 * Cada peticion trae el resultado del chunk anterior; la respuesta es el
 * siguiente chunk o STOP. Termina cuando todos los workers recibieron STOP.
 * ponytail: MPI_Recv bloqueante; Open MPI hace busy-wait, asi que el master
 * ocupa un slot completo. Con MPI_Irecv + espera corta se liberaria. */
static uint64_t master(int size, uint64_t total, uint64_t chunk,
                       uint64_t *chunks, uint64_t *keys, uint64_t *tested)
{
    uint64_t next = 0, best = UINT64_MAX;
    int active = size - 1;
    *tested = 0;
    while (active > 0) {
        uint64_t msg[2], work[2] = { 0, 0 };
        MPI_Status st;
        MPI_Recv(msg, 2, MPI_UINT64_T, MPI_ANY_SOURCE, TAG_RESULT,
                 MPI_COMM_WORLD, &st);
        int w = st.MPI_SOURCE;
        if (msg[0] < best) best = msg[0];
        *tested += msg[1];
        keys[w] += msg[1];
        if (best == UINT64_MAX && next < total) {
            work[0] = next;
            work[1] = total - next > chunk ? next + chunk : total;
            next = work[1];
            chunks[w]++;
            MPI_Send(work, 2, MPI_UINT64_T, w, TAG_WORK, MPI_COMM_WORLD);
        } else {
            MPI_Send(work, 0, MPI_UINT64_T, w, TAG_STOP, MPI_COMM_WORLD);
            active--;
        }
    }
    return best;
}

/* Worker: pide, prueba y reporta hasta recibir STOP. Si halla la clave corta
 * su chunk y la reporta en la siguiente peticion.
 * ponytail: el worker no se entera de que otro hallo la clave hasta terminar
 * su chunk actual; el trabajo desperdiciado es como mucho un chunk. */
static void worker(const unsigned char *cipher, int len)
{
    unsigned char tmp[MAX_TEXT + 1];
    uint64_t msg[2] = { UINT64_MAX, 0 };     /* {clave hallada, probadas} */
    uint64_t work[2];
    MPI_Status st;
    for (;;) {
        MPI_Send(msg, 2, MPI_UINT64_T, 0, TAG_RESULT, MPI_COMM_WORLD);
        MPI_Recv(work, 2, MPI_UINT64_T, 0, MPI_ANY_TAG, MPI_COMM_WORLD, &st);
        if (st.MPI_TAG == TAG_STOP) return;
        msg[1] = 0;
        for (uint64_t k = work[0]; k < work[1]; k++) {
            msg[1]++;
            if (try_key(k, cipher, len, tmp)) { msg[0] = k; break; }
        }
    }
}

int main(int argc, char **argv)
{
    config_t cfg;
    if (parse_args(argc, argv, &cfg) != 0) return EXIT_FAILURE;

    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    if (size < 2) {
        fprintf(stderr, "Se requieren al menos 2 procesos (1 master + 1 worker).\n");
        MPI_Finalize();
        return EXIT_FAILURE;
    }

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

    /* Nombre del nodo de cada proceso, para el reporte de reparto. */
    char name[MPI_MAX_PROCESSOR_NAME] = { 0 }, *names = NULL;
    int name_len;
    MPI_Get_processor_name(name, &name_len);
    if (rank == 0) names = calloc((size_t)size, MPI_MAX_PROCESSOR_NAME);
    MPI_Gather(name, MPI_MAX_PROCESSOR_NAME, MPI_CHAR,
               names, MPI_MAX_PROCESSOR_NAME, MPI_CHAR, 0, MPI_COMM_WORLD);

    const uint64_t total = UINT64_C(1) << cfg.bits;
    uint64_t chunk = 0;
    if (rank == 0) {
        if (cfg.secret >= total)
            fprintf(stderr, "Aviso: la clave %" PRIu64 " esta fuera de 2^%u; "
                    "no se encontrara.\n", cfg.secret, cfg.bits);
        chunk = read_chunk();
    }

    MPI_Barrier(MPI_COMM_WORLD);
    double start = MPI_Wtime();

    if (rank != 0) {
        worker(cipher, len);
    } else {
        uint64_t *chunks = calloc((size_t)size, sizeof *chunks);
        uint64_t *keys = calloc((size_t)size, sizeof *keys);
        if (!names || !chunks || !keys) fail("Sin memoria.");
        uint64_t tested;
        uint64_t found = master(size, total, chunk, chunks, keys, &tested);
        double elapsed = MPI_Wtime() - start;

        printf("Rango explorado: 2^%u = %" PRIu64 " candidatas\n", cfg.bits, total);
        if (found != UINT64_MAX) {
            unsigned char tmp[MAX_TEXT + 1];
            memcpy(tmp, cipher, len);
            des_decrypt(found, tmp, len); tmp[len] = '\0';
            printf("Clave encontrada: %" PRIu64 "\n", found);
            printf("Mensaje: %s\n", tmp);
        } else {
            printf("No se encontro la clave.\n");
        }
        printf("Ejecucion: paralela MPI master-worker con %d procesos "
               "(1 master + %d workers, chunk = %" PRIu64 ")\n",
               size, size - 1, chunk);
        printf("Candidatas probadas: %" PRIu64 "\n", tested);
        printf("Tiempo: %.6f segundos\n", elapsed);
        printf("Reparto dinamico por worker:\n");
        for (int w = 1; w < size; w++)
            printf("  rank %-3d %-26s chunks: %-8" PRIu64 " candidatas: %" PRIu64 "\n",
                   w, names + (size_t)w * MPI_MAX_PROCESSOR_NAME, chunks[w], keys[w]);
        free(chunks); free(keys); free(names);
    }

    MPI_Finalize();
    return EXIT_SUCCESS;
}
