/*----------------------------------------------------------------------
 * UNIVERSIDAD DEL VALLE DE GUATEMALA
 * Curso:       CC3069 - Computacion Paralela y Distribuida
 * Proyecto:    Busqueda de clave DES por fuerza bruta - version SECUENCIAL
 * Descripcion: recorre [0, 2^bits) probando cada candidata con try_key
 *              hasta que el texto descifrado contiene la frase clave.
 *              Sirve de linea base (T_secuencial) para el analisis de
 *              Speedup de la version MPI.
 *              Uso: ./bruteforce_des_secuencial [bits] [clave] [archivo]
 *----------------------------------------------------------------------*/
#include <time.h>
#include "des_busqueda.h"

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
    config_t cfg;
    if (parse_args(argc, argv, &cfg) != 0) return EXIT_FAILURE;

    unsigned char text[MAX_TEXT + 1];
    int len = load_text(cfg.textfile, text);

    unsigned char cipher[MAX_TEXT + 1];
    memcpy(cipher, text, len);
    des_encrypt(cfg.secret, cipher, len);   /* cifra con la clave privada */

    const uint64_t total = UINT64_C(1) << cfg.bits;
    if (cfg.secret >= total)
        fprintf(stderr, "Aviso: la clave %" PRIu64 " esta fuera de 2^%u; "
                "no se encontrara.\n", cfg.secret, cfg.bits);

    unsigned char tmp[MAX_TEXT + 1];
    uint64_t found = UINT64_MAX, tested = 0;
    double start = now();
    for (uint64_t k = 0; k < total; k++) {
        tested++;
        if (try_key(k, cipher, len, tmp)) { found = k; break; }
    }
    double elapsed = now() - start;

    printf("Rango explorado: 2^%u = %" PRIu64 " candidatas\n", cfg.bits, total);
    if (found != UINT64_MAX) {
        memcpy(tmp, cipher, len);
        des_decrypt(found, tmp, len); tmp[len] = '\0';
        printf("Clave encontrada: %" PRIu64 "\n", found);
        printf("Mensaje: %s\n", tmp);
    } else {
        printf("No se encontro la clave.\n");
    }
    printf("Ejecucion: secuencial\n");
    printf("Candidatas probadas: %" PRIu64 "\n", tested);
    printf("Tiempo: %.6f segundos\n", elapsed);
    return EXIT_SUCCESS;
}
