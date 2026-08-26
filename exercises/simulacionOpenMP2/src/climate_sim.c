/*
 * Simulación de Predicción Climática — secuencial vs OpenMP (parallel for / sections)
 *
 * Modelo: T_sig = a0 + a1*T + a2*H + a3*V   (idem para H_sig, V_sig)
 * El modelo se itera `repeat` veces por región (afinamiento sucesivo del
 * pronóstico) para dar al problema una carga de cómputo controlable:
 * el trabajo total es N * repeat, así se puede escalar sin disparar la
 * memoria (arreglos de tamaño N) ni depender de sleeps artificiales.
 *
 * Uso: ./climate_sim <seq|pfor|sections> [N] [repeat] [threads]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

/* Coeficientes del modelo (contractivos: |suma fila| < 1 => no diverge) */
#define A0 8.0
#define A1 0.60
#define A2 0.05
#define A3 -0.05
#define B0 25.0
#define B1 -0.03
#define B2 0.55
#define B3 0.04
#define C0 3.0
#define C1 0.02
#define C2 -0.02
#define C3 0.50

static void generar_datos(long n, double *temp, double *hum, double *viento) {
    srand(42); /* semilla fija: seq y paralelo parten de los mismos datos */
    for (long i = 0; i < n; i++) {
        temp[i]   = 15.0 + (rand() / (double)RAND_MAX) * 20.0; /* 15-35 C   */
        hum[i]    = 40.0 + (rand() / (double)RAND_MAX) * 50.0; /* 40-90 %   */
        viento[i] =  5.0 + (rand() / (double)RAND_MAX) * 20.0; /* 5-25 km/h */
    }
}

/* Itera el modelo "repeat" veces para una region; deja el resultado en Tp/Hp/Vp */
static inline void predecir(double Tact, double Hact, double Vact, int repeat,
                             double factorAjuste,
                             double *Tp, double *Hp, double *Vp) {
    double Tnew, Hnew, Vnew;
    for (int k = 0; k < repeat; k++) {
        Tnew = (A0 + A1 * Tact + A2 * Hact + A3 * Vact) * factorAjuste;
        Hnew = (B0 + B1 * Tact + B2 * Hact + B3 * Vact) * factorAjuste;
        Vnew = (C0 + C1 * Tact + C2 * Hact + C3 * Vact) * factorAjuste;
        Tact = Tnew; Hact = Hnew; Vact = Vnew;
    }
    *Tp = Tact; *Hp = Hact; *Vp = Vact;
}

static double ejecutar_secuencial(long n, int repeat,
                                   double *temp, double *hum, double *viento,
                                   double *tempSig, double *humSig, double *vientoSig,
                                   double *sT, double *sH, double *sV) {
    double sumaTemp = 0, sumaHum = 0, sumaViento = 0;
    double factorAjuste = 1.0;

    double t0 = omp_get_wtime();
    for (long i = 0; i < n; i++) {
        double Tp, Hp, Vp;
        predecir(temp[i], hum[i], viento[i], repeat, factorAjuste, &Tp, &Hp, &Vp);
        tempSig[i] = Tp; humSig[i] = Hp; vientoSig[i] = Vp;
        sumaTemp += Tp; sumaHum += Hp; sumaViento += Vp;
    }
    double t1 = omp_get_wtime();

    *sT = sumaTemp; *sH = sumaHum; *sV = sumaViento;
    return t1 - t0;
}

/* Paralelismo de datos: cada thread procesa un subconjunto de regiones */
static double ejecutar_parallel_for(long n, int repeat,
                                     double *temp, double *hum, double *viento,
                                     double *tempSig, double *humSig, double *vientoSig,
                                     double *sT, double *sH, double *sV) {
    double sumaTemp = 0, sumaHum = 0, sumaViento = 0;
    double factorAjuste = 1.0; /* parámetro del modelo: copiado a cada thread */

    double t0 = omp_get_wtime();
    #pragma omp parallel for \
        shared(temp, hum, viento, tempSig, humSig, vientoSig) \
        firstprivate(factorAjuste) \
        reduction(+:sumaTemp, sumaHum, sumaViento) \
        schedule(static)
    for (long i = 0; i < n; i++) {
        double Tp, Hp, Vp; /* privadas: declaradas dentro del cuerpo paralelo */
        predecir(temp[i], hum[i], viento[i], repeat, factorAjuste, &Tp, &Hp, &Vp);
        tempSig[i] = Tp; humSig[i] = Hp; vientoSig[i] = Vp;
        sumaTemp += Tp; sumaHum += Hp; sumaViento += Vp;
    }
    double t1 = omp_get_wtime();

    *sT = sumaTemp; *sH = sumaHum; *sV = sumaViento;
    return t1 - t0;
}

/* Paralelismo de tareas: una sección por variable climática */
static double ejecutar_sections(long n, int repeat,
                                 double *temp, double *hum, double *viento,
                                 double *tempSig, double *humSig, double *vientoSig,
                                 double *sT, double *sH, double *sV) {
    double factorAjuste = 1.0;

    double t0 = omp_get_wtime();
    #pragma omp parallel sections \
        shared(temp, hum, viento, tempSig, humSig, vientoSig) \
        firstprivate(factorAjuste)
    {
        #pragma omp section
        for (long i = 0; i < n; i++) {
            double Tp, Hp, Vp;
            predecir(temp[i], hum[i], viento[i], repeat, factorAjuste, &Tp, &Hp, &Vp);
            tempSig[i] = Tp;
        }
        #pragma omp section
        for (long i = 0; i < n; i++) {
            double Tp, Hp, Vp;
            predecir(temp[i], hum[i], viento[i], repeat, factorAjuste, &Tp, &Hp, &Vp);
            humSig[i] = Hp;
        }
        #pragma omp section
        for (long i = 0; i < n; i++) {
            double Tp, Hp, Vp;
            predecir(temp[i], hum[i], viento[i], repeat, factorAjuste, &Tp, &Hp, &Vp);
            vientoSig[i] = Vp;
        }
    }

    double sumaTemp = 0, sumaHum = 0, sumaViento = 0;
    #pragma omp parallel for reduction(+:sumaTemp, sumaHum, sumaViento)
    for (long i = 0; i < n; i++) {
        sumaTemp += tempSig[i]; sumaHum += humSig[i]; sumaViento += vientoSig[i];
    }
    double t1 = omp_get_wtime();

    *sT = sumaTemp; *sH = sumaHum; *sV = sumaViento;
    return t1 - t0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <seq|pfor|sections> [N=500] [repeat=1] [threads]\n", argv[0]);
        return 1;
    }
    const char *modo = argv[1];
    long n       = argc > 2 ? atol(argv[2]) : 500;
    int repeat   = argc > 3 ? atoi(argv[3]) : 1;
    int threads  = argc > 4 ? atoi(argv[4]) : omp_get_max_threads();

    if (n <= 0 || repeat <= 0) {
        fprintf(stderr, "N y repeat deben ser positivos\n");
        return 1;
    }
    omp_set_num_threads(threads);

    double *temp = malloc(n * sizeof(double));
    double *hum = malloc(n * sizeof(double));
    double *viento = malloc(n * sizeof(double));
    double *tempSig = malloc(n * sizeof(double));
    double *humSig = malloc(n * sizeof(double));
    double *vientoSig = malloc(n * sizeof(double));
    if (!temp || !hum || !viento || !tempSig || !humSig || !vientoSig) {
        fprintf(stderr, "No se pudo reservar memoria para N=%ld\n", n);
        return 1;
    }
    generar_datos(n, temp, hum, viento);

    double sumaTemp, sumaHum, sumaViento, elapsed;
    if (strcmp(modo, "seq") == 0) {
        elapsed = ejecutar_secuencial(n, repeat, temp, hum, viento, tempSig, humSig, vientoSig,
                                       &sumaTemp, &sumaHum, &sumaViento);
        threads = 1;
    } else if (strcmp(modo, "pfor") == 0) {
        elapsed = ejecutar_parallel_for(n, repeat, temp, hum, viento, tempSig, humSig, vientoSig,
                                         &sumaTemp, &sumaHum, &sumaViento);
    } else if (strcmp(modo, "sections") == 0) {
        elapsed = ejecutar_sections(n, repeat, temp, hum, viento, tempSig, humSig, vientoSig,
                                     &sumaTemp, &sumaHum, &sumaViento);
    } else {
        fprintf(stderr, "Modo desconocido: %s (usar seq|pfor|sections)\n", modo);
        return 1;
    }

    printf("mode=%s N=%ld repeat=%d threads=%d time=%.6f avgT=%.4f avgH=%.4f avgV=%.4f\n",
           modo, n, repeat, threads, elapsed,
           sumaTemp / n, sumaHum / n, sumaViento / n);

    free(temp); free(hum); free(viento);
    free(tempSig); free(humSig); free(vientoSig);
    return 0;
}
