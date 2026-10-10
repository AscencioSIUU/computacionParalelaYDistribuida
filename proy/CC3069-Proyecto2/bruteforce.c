/*----------------------------------------------------------------------
 * bruteforce_.c  -  ARCHIVO ORIGINAL DEL ENUNCIADO (referencia, sin usar)
 *
 * Version canonica del curso. Usa <rpc/des_crypt.h> (ecb_crypt /
 * des_setparity), disponible solo en glibc (Linux). NO compila en macOS
 * ni en Windows nativo; por eso el proyecto porta estas funciones a
 * OpenSSL en des_busqueda.h. Se conserva aqui para documentar de que se
 * parte y para la seccion 3 del informe (explicacion de las funciones).
 *----------------------------------------------------------------------*/
#include <stdio.h>
#include <string.h>
#include <mpi.h>
#include <rpc/des_crypt.h>

void decrypt(long key, char *ciph, int len)
{
    long k = 0;
    for (int i = 0; i < 8; ++i) {
        key <<= 1;
        k += (key & (0xFE << i * 8));
    }
    des_setparity((char *)&k);
    ecb_crypt((char *)&k, (char *)ciph, len, DES_DECRYPT);
}

void encrypt(long key, char *ciph, int len)
{
    long k = 0;
    for (int i = 0; i < 8; ++i) {
        key <<= 1;
        k += (key & (0xFE << i * 8));
    }
    des_setparity((char *)&k);
    ecb_crypt((char *)&k, (char *)ciph, len, DES_ENCRYPT);
}

char search[] = "es una prueba de";
int tryKey(long key, char *ciph, int len)
{
    char temp[len + 1];
    memcpy(temp, ciph, len);
    temp[len] = 0;
    decrypt(key, temp, len);
    return strstr((char *)temp, search) != NULL;
}

unsigned char cipher[] = {108, 245, 65, 63, 125, 200, 150, 66, 17, 170, 207,
                          170, 34, 31, 70, 215, 0};

int main(int argc, char *argv[])
{
    int N, id;
    long upper = (1L << 56);        /* espacio total de claves DES          */
    long mylower, myupper;
    MPI_Status st;
    MPI_Request req;
    int flag;
    int ciphlen = strlen((char *)cipher);
    MPI_Comm comm = MPI_COMM_WORLD;

    MPI_Init(&argc, &argv);
    MPI_Comm_size(comm, &N);
    MPI_Comm_rank(comm, &id);

    long range_per_node = upper / N;
    mylower = range_per_node * id;
    myupper = range_per_node * (id + 1) - 1;
    if (id == N - 1) myupper = upper;

    long found = 0;
    MPI_Irecv(&found, 1, MPI_LONG, MPI_ANY_SOURCE, 0, comm, &req);

    for (long i = mylower; i < myupper && (found == 0); ++i) {
        if (tryKey(i, (char *)cipher, ciphlen)) {
            found = i;
            for (int node = 0; node < N; node++)
                MPI_Send(&found, 1, MPI_LONG, node, 0, comm);
            break;
        }
    }

    if (id == 0) {
        MPI_Wait(&req, &st);
        decrypt(found, (char *)cipher, ciphlen);
        printf("%li %s\n", found, cipher);
    }

    MPI_Finalize();
    return 0;
}
