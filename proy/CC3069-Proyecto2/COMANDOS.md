# Comandos — Proyecto 2 (DES + Open MPI)

Uso de los programas: `[bits] [clave] [archivo]`

- `bits`: se prueban 2^bits claves (de 0 a 2^bits − 1). Con 22 son 4 194 304 claves.
- `clave`: clave secreta con la que se cifra el texto. Debe ser menor que 2^bits.
- `archivo`: texto a cifrar (por defecto `texto.txt`).

## 1. Entrar a la carpeta y compilar

```bash
cd /Users/nesstor/Documents/git_u/2026/computacionParalelaYDistribuida/proy/CC3069-Proyecto2

# Compila la versión secuencial y la versión MPI
make
```

## 2. Versión secuencial (tiempo base)

```bash
# Un solo proceso prueba las claves 0..2^22 hasta encontrar la 4000000
# Su "Tiempo" es la base para calcular el speedup
./bruteforce_des_secuencial 22 4000000
```

## 3. Versión paralela con MPI

```bash
# El mismo rango repartido en bloques entre 2, 3 y 4 procesos
# Comparar su "Tiempo" contra el secuencial
mpirun -np 2 ./bruteforce_des_mpi 22 4000000
mpirun -np 3 ./bruteforce_des_mpi 22 4000000
mpirun -np 4 ./bruteforce_des_mpi 22 4000000
```

## 4. Benchmark automático (tabla "Tiempos y Speedup" del README)

```bash
# 5 corridas por configuración, toma la mediana y calcula speedup y eficiencia
./bench.sh 22 4000000
```

## 5. Efecto de la posición de la clave (sección 5 del README)

Con `-np 4` y 2^22, cada proceso recibe 1 048 576 claves:
P0 = 0–1 048 575, P1 = 1 048 576–2 097 151, P2 = 2 097 152–3 145 727, P3 = 3 145 728–4 194 303.

```bash
# Clave baja, en el bloque de P0: speedup ≈ 0.9 (no hay ganancia)
./bruteforce_des_secuencial 22 100000
mpirun -np 4 ./bruteforce_des_mpi 22 100000

# Clave al inicio del bloque de P2: speedup enorme (~490x), engañoso
./bruteforce_des_secuencial 22 2100000
mpirun -np 4 ./bruteforce_des_mpi 22 2100000

# Clave alta, adentro del bloque de P3: speedup ≈ 4 (la medición justa)
./bruteforce_des_secuencial 22 4100000
mpirun -np 4 ./bruteforce_des_mpi 22 4100000
```

## 6. Validar el invariante (no se repite ni se salta ninguna clave)

```bash
# La clave está fuera del rango, así que se recorre todo
# "Candidatas probadas" debe ser exactamente 1024 (2^10)
mpirun -np 3 ./bruteforce_des_mpi 10 999999
```

## 7. Medir la velocidad para estimar 2^56

```bash
# Recorre el rango completo sin encontrar la clave (la clave es imposible)
./bruteforce_des_secuencial 24 999999999999
```

- Velocidad = `Candidatas probadas / Tiempo` ≈ 980 000 claves/s
- 2^56 / 980 000 ≈ 7.35 · 10^10 s ≈ 2 300 años (estimación, no medición)

## 8. Limpiar

```bash
# Borra los binarios compilados
make clean
```
