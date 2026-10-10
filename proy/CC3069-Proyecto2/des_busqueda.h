/*----------------------------------------------------------------------
 * UNIVERSIDAD DEL VALLE DE GUATEMALA
 * Curso:       CC3069 - Computacion Paralela y Distribuida
 * Proyecto:    Busqueda de clave privada DES por fuerza bruta (Open MPI)
 *
 * Utilidades compartidas por bruteforce_des_secuencial.c (secuencial) y
 * bruteforce_des_mpi.c (Open MPI), para que ambas versiones prueben
 * exactamente las mismas claves de la misma forma.
 *
 * Portabilidad: el bruteforce_.c del enunciado usa <rpc/des_crypt.h>
 * (ecb_crypt / des_setparity), presente solo en glibc (Linux). Aqui se
 * usa el DES de bajo nivel de OpenSSL (openssl/des.h), que compila en
 * macOS, Linux y Windows/WSL. Las firmas encrypt/decrypt/try_key se
 * conservan para describir el mismo programa del enunciado.
 *----------------------------------------------------------------------*/
#ifndef DES_BUSQUEDA_H
#define DES_BUSQUEDA_H

#define _POSIX_C_SOURCE 200809L
#define OPENSSL_SUPPRESS_DEPRECATED 1   /* DES de bajo nivel: deprecated en OpenSSL 3 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <errno.h>
#include <openssl/des.h>

#define DES_BLOCK 8               /* DES cifra bloques de 8 bytes (64 bits)  */
#define MAX_TEXT  8192            /* limite del texto a cifrar (bytes)       */
#define DEFAULT_BITS 24           /* se exploran 2^bits candidatas           */
#define DEFAULT_SECRET UINT64_C(12345)
#define DEFAULT_TEXTFILE "texto.txt"
/* Frase clave (crib) que debe aparecer como substring del texto descifrado.
 * ASCII puro para evitar diferencias de codificacion en strstr. */
#define SEARCH "Proyecto 2 de Computacion Paralela"
/* La frase clave vive al inicio del texto: para probar una candidata basta
 * descifrar los primeros CHECK_BYTES (optimizacion de rendimiento). El texto
 * completo solo se descifra al encontrar la clave, para mostrarlo. */
#define CHECK_BYTES 160

typedef struct {
    unsigned  bits;                      /* 2^bits candidatas                */
    uint64_t  secret;                    /* solo para preparar el ejercicio  */
    const char *textfile;                /* archivo con el texto a cifrar    */
} config_t;

static inline void fail(const char *msg)
{
    fprintf(stderr, "%s\n", msg);
    exit(EXIT_FAILURE);
}

/*
 * Construye la clave DES de 64 bits a partir de una candidata de 56 bits:
 * reparte 7 bits de la candidata en los bits 1..7 de cada byte y deja el
 * bit 0 para la paridad (igual idea que des_setparity del original). El
 * mapeo es identico al cifrar y al probar, asi que la busqueda es correcta.
 */
static inline void make_des_key(uint64_t candidate, DES_cblock *key)
{
    for (int i = 0; i < 8; i++) {
        (*key)[i] = (unsigned char)(((candidate >> (7 * i)) & 0x7F) << 1);
    }
    DES_set_odd_parity(key);
}

/* Cifra (enc!=0) o descifra (enc==0) buf in-place, bloque a bloque. len
 * debe ser multiplo de DES_BLOCK. Equivale a ecb_crypt del enunciado. */
static inline void des_crypt_blocks(uint64_t candidate, unsigned char *buf,
                                    int len, int enc)
{
    DES_cblock k;
    DES_key_schedule ks;
    make_des_key(candidate, &k);
    DES_set_key_unchecked(&k, &ks);
    for (int off = 0; off + DES_BLOCK <= len; off += DES_BLOCK) {
        DES_ecb_encrypt((const_DES_cblock *)(buf + off),
                        (DES_cblock *)(buf + off), &ks,
                        enc ? DES_ENCRYPT : DES_DECRYPT);
    }
}

/* encrypt / decrypt del enunciado, sobre texto multi-bloque. */
static inline void des_encrypt(uint64_t key, unsigned char *buf, int len)
{ des_crypt_blocks(key, buf, len, 1); }

static inline void des_decrypt(uint64_t key, unsigned char *buf, int len)
{ des_crypt_blocks(key, buf, len, 0); }

/*
 * try_key del enunciado: memcpy copia el cifrado a un buffer temporal para
 * no destruir el cifrado compartido; se descifra la copia con la candidata
 * y strstr decide si aparece la frase clave. tmp debe tener len+1 bytes.
 */
static inline int try_key(uint64_t candidate, const unsigned char *cipher,
                          int len, unsigned char *tmp)
{
    int clen = len < CHECK_BYTES ? len : CHECK_BYTES;   /* multiplo de 8 */
    memcpy(tmp, cipher, clen);
    des_decrypt(candidate, tmp, clen);
    tmp[clen] = '\0';
    return strstr((char *)tmp, SEARCH) != NULL;
}

/* Lee el texto del archivo y lo rellena con espacios hasta multiplo de 8.
 * Devuelve la longitud rellenada; aborta si no cabe o no contiene la frase. */
static inline int load_text(const char *path, unsigned char *out)
{
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "No se pudo abrir %s\n", path); exit(EXIT_FAILURE); }
    size_t n = fread(out, 1, MAX_TEXT, f);
    fclose(f);
    if (n == 0 || n >= MAX_TEXT) fail("Texto vacio o demasiado grande.");
    out[n] = '\0';
    char *pos = strstr((char *)out, SEARCH);
    if (!pos)
        fail("El texto no contiene la frase clave: \"" SEARCH "\"");
    if (pos - (char *)out + (int)sizeof(SEARCH) > CHECK_BYTES)
        fail("La frase clave debe aparecer dentro de los primeros CHECK_BYTES bytes.");
    int len = (int)n;
    while (len % DES_BLOCK != 0) out[len++] = ' ';   /* padding con espacios */
    return len;
}

/* uso: prog [bits 1-40] [clave_secreta] [archivo_texto] */
static inline int parse_args(int argc, char **argv, config_t *cfg)
{
    char *end;
    cfg->bits = DEFAULT_BITS;
    cfg->secret = DEFAULT_SECRET;
    cfg->textfile = DEFAULT_TEXTFILE;

    if (argc > 4) goto usage;
    if (argc > 1) {
        errno = 0;
        unsigned long long b = strtoull(argv[1], &end, 10);
        if (errno || *end || argv[1][0] == '\0' || b < 1 || b > 40) goto usage;
        cfg->bits = (unsigned)b;
    }
    if (argc > 2) {
        errno = 0;
        unsigned long long s = strtoull(argv[2], &end, 10);
        if (errno || *end || argv[2][0] == '\0' || argv[2][0] == '-') goto usage;
        cfg->secret = (uint64_t)s;
    }
    if (argc > 3) cfg->textfile = argv[3];
    return 0;
usage:
    fprintf(stderr, "Uso: %s [bits 1-40, def. %d] [clave_secreta, def. %" PRIu64
            "] [archivo_texto, def. %s]\n",
            argv[0], DEFAULT_BITS, (uint64_t)DEFAULT_SECRET, DEFAULT_TEXTFILE);
    return -1;
}

#endif
