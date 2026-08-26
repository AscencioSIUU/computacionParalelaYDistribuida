# Simulación de Predicción Climática con OpenMP

## Programación Paralela — Diseño del Caso

**Caso asignado:** Predicción del clima
**Lenguaje:** C
**Tecnología:** OpenMP
**Cantidad de datos:** 500 registros/regiones

---

# 1. Introducción

## ¿Qué se va a realizar?

Se desarrollará una simulación de un sistema simplificado de **predicción de condiciones climáticas para el día siguiente**.

La simulación trabajará con **500 registros**, donde cada registro representa una región con diferentes condiciones climáticas actuales.

Para cada región se almacenarán tres variables principales:

* Temperatura actual.
* Humedad actual.
* Velocidad del viento actual.

A partir de estos valores se calcularán las condiciones estimadas para el siguiente día:

* Temperatura siguiente.
* Humedad siguiente.
* Viento siguiente.

El objetivo principal no es construir un sistema meteorológico real, sino utilizar este problema para estudiar las posibilidades de **paralelización utilizando OpenMP**.

---

# 2. Objetivos

## Objetivo general

Implementar una simulación climática primero de manera **secuencial** y posteriormente de manera **paralela utilizando OpenMP**, con el propósito de comparar su rendimiento.

## Objetivos específicos

* Generar 500 registros con condiciones climáticas iniciales.
* Implementar una versión secuencial del algoritmo.
* Identificar operaciones que puedan ejecutarse concurrentemente.
* Implementar paralelismo de datos mediante `parallel for`.
* Implementar paralelismo de tareas mediante `sections`.
* Utilizar correctamente las cláusulas:

  * `shared`
  * `private`
  * `firstprivate`
  * `reduction`
* Medir el tiempo de ejecución secuencial.
* Medir el tiempo de ejecución paralelo.
* Calcular el **Speedup**.
* Calcular la **Eficiencia**.
* Comparar el comportamiento con diferentes cantidades de threads.

---

# 3. Datos iniciales

La simulación utilizará un conjunto de:

**N = 500 regiones**

Cada región tendrá inicialmente:

| Variable    | Descripción                     |
| ----------- | ------------------------------- |
| Temperatura | Temperatura actual de la región |
| Humedad     | Porcentaje actual de humedad    |
| Viento      | Velocidad actual del viento     |

Los valores iniciales serán generados aleatoriamente dentro de rangos definidos para evitar datos absurdos.

Ejemplo:

| Región | Temperatura | Humedad |    Viento |
| ------ | ----------: | ------: | --------: |
| 0      |     25.4 °C |     68% | 12.5 km/h |
| 1      |     31.2 °C |     55% |  8.3 km/h |
| 2      |     22.7 °C |     81% | 17.4 km/h |
| 3      |     28.5 °C |     64% | 11.2 km/h |
| ...    |         ... |     ... |       ... |
| 499    |     26.3 °C |     72% | 14.1 km/h |

---

# 4. Representación de los datos

Los datos pueden almacenarse utilizando arreglos.

Por ejemplo:

```text
temperatura[500]
humedad[500]
viento[500]
```

También se necesitarán arreglos para almacenar las predicciones:

```text
temperaturaSiguiente[500]
humedadSiguiente[500]
vientoSiguiente[500]
```

Por lo tanto, para cada índice `i` tendremos:

```text
Región i

temperatura[i]
humedad[i]
viento[i]

        ↓

Modelo de predicción

        ↓

temperaturaSiguiente[i]
humedadSiguiente[i]
vientoSiguiente[i]
```

---

# 5. Modelo simplificado de predicción

Para realizar la simulación se utilizarán **modelos matemáticos lineales simplificados**.

Las condiciones futuras dependerán de las condiciones actuales.

Para la temperatura:

$$
T_{sig} =
a_0 +
a_1T_{act} +
a_2H_{act} +
a_3V_{act}
$$

Para la humedad:

$$
H_{sig} =
b_0 +
b_1T_{act} +
b_2H_{act} +
b_3V_{act}
$$

Para el viento:

$$
V_{sig} =
c_0 +
c_1T_{act} +
c_2H_{act} +
c_3V_{act}
$$

Donde:

* \(T_{act}\): temperatura actual.
* \(H_{act}\): humedad actual.
* \(V_{act}\): viento actual.
* \(T_{sig}\): temperatura estimada para el siguiente día.
* \(H_{sig}\): humedad estimada para el siguiente día.
* \(V_{sig}\): viento estimado para el siguiente día.

Los coeficientes \(a\), \(b\) y \(c\) representan parámetros del modelo.

---

# 6. ¿Por qué utilizar un modelo lineal?

El objetivo del proyecto es estudiar **programación paralela**, no desarrollar un sistema meteorológico científicamente preciso.

Un modelo lineal tiene varias ventajas:

* Es sencillo de implementar.
* Permite relacionar varias variables.
* Produce una cantidad considerable de operaciones.
* La misma operación debe repetirse para las 500 regiones.
* Las regiones pueden calcularse independientemente.
* Esto permite aplicar fácilmente paralelismo de datos.

El modelo sirve como carga de trabajo para estudiar el comportamiento de OpenMP.

---

# 7. Flujo general de la simulación

```text
        INICIO
           │
           ▼
 Generar 500 regiones
           │
           ▼
 Temperatura, humedad
       y viento
           │
           ▼
 ┌─────────────────────┐
 │ Modelo de predicción│
 └──────────┬──────────┘
            │
     ┌──────┼──────┐
     ▼      ▼      ▼
   Temp.  Humedad  Viento
 siguiente siguiente siguiente
     │      │      │
     └──────┼──────┘
            ▼
 Calcular estadísticas
            │
            ▼
 Medir rendimiento
            │
            ▼
           FIN
```

---

# 8. Primera implementación: versión secuencial

La primera versión ejecutará todas las operaciones utilizando **un único flujo de ejecución**.

Se recorrerán las 500 regiones mediante un ciclo.

Para cada región:

1. Calcular temperatura siguiente.
2. Calcular humedad siguiente.
3. Calcular viento siguiente.
4. Guardar los resultados.
5. Acumular los valores necesarios para las estadísticas.

Después se continúa con la siguiente región.

---

# 9. Flujo de ejecución secuencial

```text
Región 0
   │
   ├── Temperatura
   ├── Humedad
   └── Viento
         │
         ▼
Región 1
   │
   ├── Temperatura
   ├── Humedad
   └── Viento
         │
         ▼
Región 2
         │
         ▼
        ...
         │
         ▼
Región 499
```

Una región comienza a procesarse solamente cuando termina la anterior.

---

# 10. Pseudocódigo secuencial

```text
INICIO

N ← 500

Declarar arreglos de datos actuales
Declarar arreglos de predicciones

Generar 500 registros aleatorios

sumaTemperatura ← 0
sumaHumedad ← 0
sumaViento ← 0

iniciar temporizador

PARA i ← 0 HASTA N-1

    temperaturaSiguiente[i] ←
        calcularTemperatura(
            temperatura[i],
            humedad[i],
            viento[i]
        )

    humedadSiguiente[i] ←
        calcularHumedad(
            temperatura[i],
            humedad[i],
            viento[i]
        )

    vientoSiguiente[i] ←
        calcularViento(
            temperatura[i],
            humedad[i],
            viento[i]
        )

    sumaTemperatura ←
        sumaTemperatura + temperaturaSiguiente[i]

    sumaHumedad ←
        sumaHumedad + humedadSiguiente[i]

    sumaViento ←
        sumaViento + vientoSiguiente[i]

FIN PARA

detener temporizador

promedioTemperatura ← sumaTemperatura / N
promedioHumedad ← sumaHumedad / N
promedioViento ← sumaViento / N

Mostrar resultados

FIN
```

---

# 11. ¿Qué se puede paralelizar?

Existe una característica importante del problema:

**Las regiones son independientes.**

Para calcular:

```text
temperaturaSiguiente[20]
```

no necesitamos conocer:

```text
temperaturaSiguiente[19]
```

ni:

```text
temperaturaSiguiente[21]
```

Por lo tanto:

```text
Región 0 ──┐
Región 1 ──┤
Región 2 ──┼── Pueden procesarse simultáneamente
Región 3 ──┤
...        │
Región 499 ┘
```

Esto hace que el problema sea adecuado para **paralelismo de datos**.

---

# 12. Paralelismo de datos

Para distribuir las regiones entre diferentes threads se utilizará:

```c
#pragma omp parallel for
```

En lugar de que un solo thread procese las 500 iteraciones, OpenMP distribuye las iteraciones entre los threads disponibles.

---

# 13. Ejemplo de distribución

Supongamos que se utilizan cuatro threads.

Conceptualmente podría ocurrir:

```text
                    500 REGIONES
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
     Thread 0         Thread 1         Thread 2 ...
        │                │                │
 Regiones asignadas Regiones asignadas Regiones asignadas
        │                │                │
        ▼                ▼                ▼
    Predicción       Predicción       Predicción
```

Cada thread realiza el mismo algoritmo, pero sobre diferentes regiones.

---

# 14. `parallel for`

La estructura conceptual será:

```text
PARALLEL FOR

    PARA cada región i

        calcular temperatura siguiente

        calcular humedad siguiente

        calcular viento siguiente

    FIN PARA

FIN PARALLEL FOR
```

OpenMP será responsable de distribuir las iteraciones entre los diferentes threads.

---

# 15. Paralelismo de tareas

También existe otra forma de dividir el problema.

En lugar de distribuir las regiones, podemos distribuir **diferentes tipos de trabajo**.

Tenemos tres tareas principales:

```text
1. Calcular temperaturas
2. Calcular humedades
3. Calcular vientos
```

Estas operaciones son diferentes pero pueden realizarse independientemente.

Para esto podemos utilizar:

```c
#pragma omp sections
```

junto con:

```c
#pragma omp section
```

---

# 16. Funcionamiento de `sections`

Conceptualmente:

```text
                    PREDICCIÓN
                        │
         ┌──────────────┼──────────────┐
         │              │              │
         ▼              ▼              ▼
     SECTION 1      SECTION 2      SECTION 3
         │              │              │
 Temperaturas       Humedades        Vientos
         │              │              │
         ▼              ▼              ▼
      Thread          Thread          Thread
```

OpenMP puede asignar cada sección a un thread diferente.

---

# 17. Pseudocódigo de `sections`

```text
PARALLEL SECTIONS

    SECTION

        PARA i ← 0 HASTA N-1

            calcular temperaturaSiguiente[i]

        FIN PARA


    SECTION

        PARA i ← 0 HASTA N-1

            calcular humedadSiguiente[i]

        FIN PARA


    SECTION

        PARA i ← 0 HASTA N-1

            calcular vientoSiguiente[i]

        FIN PARA

FIN PARALLEL SECTIONS
```

Esto representa **paralelismo de tareas**.

---

# 18. Comparación de estrategias

## Paralelismo de datos

```text
Thread 0 → algunas regiones
Thread 1 → algunas regiones
Thread 2 → algunas regiones
Thread 3 → algunas regiones
```

Cada thread calcula:

```text
Temperatura + Humedad + Viento
```

de sus regiones.

## Paralelismo de tareas

```text
Thread 0 → Temperaturas
Thread 1 → Humedades
Thread 2 → Vientos
```

Cada thread realiza un tipo de trabajo diferente.

---

# 19. Manejo de variables en OpenMP

Al trabajar con múltiples threads es necesario determinar cuáles variables pueden ser utilizadas por todos y cuáles necesitan ser independientes.

Se utilizarán:

```text
shared
private
firstprivate
reduction
```

Cada una tiene un propósito diferente.

---

# 20. Variables `shared`

Una variable `shared` es compartida entre todos los threads.

Todos observan la **misma variable o estructura de memoria**.

En nuestra simulación serán compartidos principalmente los arreglos:

```text
temperatura[]
humedad[]
viento[]

temperaturaSiguiente[]
humedadSiguiente[]
vientoSiguiente[]
```

---

# 21. ¿Por qué los arreglos pueden ser `shared`?

Todos los threads necesitan acceder al mismo conjunto de regiones.

Conceptualmente:

```text
              ARREGLOS SHARED
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
   Thread 0     Thread 1     Thread 2
```

Sin embargo, cada thread procesa índices diferentes.

Por ejemplo:

```text
Thread 0 → temperaturaSiguiente[10]

Thread 1 → temperaturaSiguiente[50]

Thread 2 → temperaturaSiguiente[80]
```

Por lo tanto, aunque el arreglo sea compartido, los threads no necesariamente modifican la misma posición.

---

# 22. Variables `private`

Una variable `private` tiene una copia independiente para cada thread.

Ejemplos:

```text
variable temporal de temperatura
variable temporal de humedad
variable temporal de viento
```

Conceptualmente:

```text
Thread 0
    tempTemporal = ...

Thread 1
    tempTemporal = ...

Thread 2
    tempTemporal = ...
```

Modificar una de estas variables en un thread no modifica la copia de otro thread.

Esto ayuda a evitar conflictos entre threads.

---

# 23. `firstprivate`

`firstprivate` también crea una copia privada para cada thread.

La diferencia es que **la copia comienza con el valor que tenía la variable antes de entrar a la región paralela**.

Ejemplo:

```text
factorCambio = 0.15
```

Al utilizar:

```text
firstprivate(factorCambio)
```

se obtiene:

```text
                factorCambio
                    0.15
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
     Thread 0     Thread 1     Thread 2
       0.15         0.15         0.15
```

Cada thread obtiene su propia copia inicializada.

---

# 24. Diferencia entre variables

| Cláusula          | Comportamiento                                                         |
| ----------------- | ---------------------------------------------------------------------- |
| `shared(x)`       | Todos los threads acceden a la misma variable                          |
| `private(x)`      | Cada thread obtiene su propia copia                                    |
| `firstprivate(x)` | Cada thread obtiene su propia copia inicializada con el valor original |

Elegir correctamente estas cláusulas ayuda a evitar errores de concurrencia.

---

# 25. Problema al realizar sumas en paralelo

Después de realizar las predicciones queremos calcular estadísticas.

Por ejemplo:

$$
S_T=\sum_{i=0}^{499}T_i
$$

Si utilizamos una variable compartida:

```text
sumaTemperatura
```

varios threads podrían intentar modificarla simultáneamente:

```text
Thread 0 ───┐
Thread 1 ───┼──→ sumaTemperatura
Thread 2 ───┤
Thread 3 ───┘
```

Esto puede producir una **condición de carrera**.

---

# 26. Condición de carrera

Supongamos:

```text
suma = 10
```

Dos threads intentan sumar simultáneamente:

```text
Thread 0 quiere sumar 5
Thread 1 quiere sumar 7
```

El resultado correcto debería ser:

$$
10+5+7=22
$$

Pero si ambos leen `10` antes de que el otro actualice la variable, podrían sobrescribir resultados.

El resultado podría ser incorrecto.

---

# 27. Solución: `reduction`

OpenMP proporciona:

```text
reduction
```

para realizar este tipo de operaciones de forma segura y eficiente.

Utilizaremos conceptualmente:

```text
reduction(+: sumaTemperatura)
```

Cada thread trabaja inicialmente con una suma independiente.

---

# 28. Funcionamiento de `reduction`

```text
Thread 0 → suma parcial 0 ──┐
Thread 1 → suma parcial 1 ──┤
Thread 2 → suma parcial 2 ──┼──→ SUMA FINAL
Thread 3 → suma parcial 3 ──┘
```

Al finalizar la región paralela, OpenMP combina los resultados.

Esto evita que los threads tengan que modificar simultáneamente una única variable de acumulación.

---

# 29. Estadísticas de la simulación

Utilizando `reduction` podemos obtener:

## Temperatura promedio

$$
T_{prom}=
\frac{\sum T_{sig}}{500}
$$

## Humedad promedio

$$
H_{prom}=
\frac{\sum H_{sig}}{500}
$$

## Viento promedio

$$
V_{prom}=
\frac{\sum V_{sig}}{500}
$$

Estas estadísticas también permitirán comprobar que la versión secuencial y la paralela producen resultados equivalentes.

---

# 30. Variables compartidas y privadas

## Variables compartidas

```text
temperatura[]
humedad[]
viento[]

temperaturaSiguiente[]
humedadSiguiente[]
vientoSiguiente[]
```

Todos los threads necesitan acceder a estos datos.

## Variables privadas

```text
variables temporales utilizadas
durante cada predicción
```

Cada thread necesita trabajar con sus propios valores temporales.

## Variables `firstprivate`

```text
parámetros iniciales del modelo
factores utilizados por la simulación
```

Cada thread recibe una copia inicializada.

## Variables con `reduction`

```text
sumaTemperatura
sumaHumedad
sumaViento
```

Se utilizan para obtener estadísticas globales.

---

# 31. Pseudocódigo de la versión paralela

```text
INICIO

N ← 500

Generar datos iniciales

sumaTemperatura ← 0
sumaHumedad ← 0
sumaViento ← 0

iniciar temporizador

PARALLEL FOR

    shared(
        temperatura,
        humedad,
        viento,
        resultados
    )

    private(
        variablesTemporales
    )

    firstprivate(
        parametrosIniciales
    )

    reduction(
        +:
        sumaTemperatura,
        sumaHumedad,
        sumaViento
    )

    PARA i ← 0 HASTA N-1

        calcular temperatura siguiente
        calcular humedad siguiente
        calcular viento siguiente

        acumular temperatura
        acumular humedad
        acumular viento

    FIN PARA

FIN PARALLEL FOR

detener temporizador

Calcular promedios

FIN
```

---

# 32. Medición del rendimiento

Después de implementar ambas versiones se compararán sus tiempos de ejecución.

Tendremos:

$$
T_s = \text{tiempo de ejecución secuencial}
$$

y:

$$
T_p = \text{tiempo de ejecución paralelo}
$$

Estos tiempos permitirán calcular las métricas solicitadas.

---

# 33. Speedup

El **Speedup** representa cuántas veces más rápida es la solución paralela respecto a la secuencial.

Se calcula:

$$
\boxed{
S_p=\frac{T_s}{T_p}
}
$$

Donde:

* \(S_p\): Speedup.
* \(T_s\): tiempo secuencial.
* \(T_p\): tiempo paralelo.

---

# 34. Ejemplo de Speedup

Supongamos:

```text
Tiempo secuencial = 8 segundos

Tiempo paralelo = 2.5 segundos
```

Entonces:

$$
S_p=\frac{8}{2.5}
$$

$$
\boxed{S_p=3.2}
$$

Esto significa que la implementación paralela fue aproximadamente:

**3.2 veces más rápida que la secuencial.**

---

# 35. Eficiencia

El Speedup por sí solo no indica qué tan bien estamos utilizando los threads.

Para eso utilizamos la **Eficiencia**:

$$
\boxed{
E_p=\frac{S_p}{p}
}
$$

Donde:

* \(E_p\): eficiencia.
* \(S_p\): Speedup.
* \(p\): cantidad de threads.

---

# 36. Ejemplo de Eficiencia

Si tenemos:

$$
S_p=3.2
$$

utilizando:

$$
p=4
$$

threads:

$$
E_p=\frac{3.2}{4}
$$

$$
E_p=0.8
$$

En porcentaje:

$$
\boxed{E_p=80\%}
$$

Esto representa qué tan eficientemente estamos aprovechando los cuatro threads.

---

# 37. Pruebas propuestas

No se realizará únicamente una prueba.

La simulación se puede ejecutar utilizando diferentes cantidades de threads.

Por ejemplo:

```text
1 thread
2 threads
4 threads
8 threads
```

Para cada configuración se registrará:

* Tiempo.
* Speedup.
* Eficiencia.

---

# 38. Tabla de resultados esperada

Al finalizar los experimentos podremos construir una tabla similar a:

| Threads |  Tiempo |     Speedup | Eficiencia |
| ------: | ------: | ----------: | ---------: |
|       1 | \(T_1\) |        1.00 |       100% |
|       2 | \(T_2\) | \(T_1/T_2\) |  \(S_2/2\) |
|       4 | \(T_4\) | \(T_1/T_4\) |  \(S_4/4\) |
|       8 | \(T_8\) | \(T_1/T_8\) |  \(S_8/8\) |

**Los valores reales se obtendrán al ejecutar la implementación.**

No se deben inventar resultados antes de realizar las pruebas.

---

# 39. ¿Qué esperamos observar?

En teoría, al aumentar la cantidad de threads esperamos reducir el tiempo de ejecución.

Sin embargo:

$$
\text{más threads} \neq \text{siempre más rendimiento}
$$

OpenMP también introduce costos adicionales:

* Creación y administración de threads.
* Distribución del trabajo.
* Sincronización.
* Acceso a memoria compartida.
* Combinación de resultados de `reduction`.

Por esta razón es importante realizar las mediciones.

---

# 40. Consideración importante: 500 registros

La simulación utiliza 500 registros.

Si cada cálculo es extremadamente pequeño, el tiempo utilizado por OpenMP para administrar los threads puede llegar a ser comparable o incluso superior al tiempo del cálculo.

En ese caso podría ocurrir:

$$
T_p \geq T_s
$$

y por lo tanto:

$$
S_p \leq 1
$$

Esto **no necesariamente significa que la implementación esté incorrecta**.

Significa que el problema puede ser demasiado pequeño para beneficiarse de la paralelización.

---

# 41. Importancia de esta observación

Uno de los objetivos del proyecto es:

> Identificar en dónde son útiles estas implementaciones.

Por lo tanto, no solamente queremos demostrar que OpenMP funciona.

Queremos determinar:

**¿Cuándo vale la pena paralelizar este problema?**

La experimentación permitirá observar si el costo computacional de las predicciones justifica el uso de múltiples threads.

---

# 42. Diseño completo

```text
                    500 REGIONES
                         │
                         ▼
             DATOS CLIMÁTICOS ACTUALES
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
         Temperatura   Humedad    Viento
              │          │          │
              └──────────┼──────────┘
                         ▼
                 MODELO PREDICTIVO
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
     Temp. siguiente Hum. siguiente Viento siguiente
          │              │              │
          └──────────────┼──────────────┘
                         ▼
                   ESTADÍSTICAS
                         │
                         ▼
               ┌─────────────────┐
               │ SERIAL/PARALELO │
               └────────┬────────┘
                        ▼
               MEDIR RENDIMIENTO
                        │
                ┌───────┴───────┐
                ▼               ▼
             SPEEDUP         EFICIENCIA
```

---

# 43. Uso de OpenMP en el proyecto

| Herramienta    | Aplicación                                         |
| -------------- | -------------------------------------------------- |
| `parallel for` | Distribuir las 500 regiones entre threads          |
| `sections`     | Separar temperatura, humedad y viento en tareas    |
| `shared`       | Compartir arreglos de datos y resultados           |
| `private`      | Variables temporales independientes                |
| `firstprivate` | Copiar parámetros iniciales a cada thread          |
| `reduction`    | Calcular sumas globales sin condiciones de carrera |

Cada herramienta se utiliza porque resuelve una necesidad específica del problema.

---

# 44. Resultado esperado del proyecto

Al finalizar tendremos:

```text
            SIMULACIÓN CLIMÁTICA
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
      SECUENCIAL           PARALELO
          │                   │
        1 hilo             N threads
          │                   │
          └─────────┬─────────┘
                    ▼
                 COMPARAR
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
       SPEEDUP            EFICIENCIA
```

Esto permitirá determinar experimentalmente cuál implementación resulta más conveniente.

---

# 45. Conclusiones

La simulación climática presenta diferentes oportunidades para aplicar programación paralela.

Las regiones son independientes entre sí, por lo que pueden distribuirse utilizando `parallel for`.

Las diferentes variables climáticas también representan tareas independientes, permitiendo experimentar con `sections`.

El uso de `shared`, `private` y `firstprivate` permite administrar correctamente los datos utilizados por los threads.

`reduction` permite calcular estadísticas globales sin introducir condiciones de carrera.

Finalmente, el Speedup y la Eficiencia permitirán determinar cuantitativamente si la paralelización produce una mejora.

---

# 46. Conclusión final

El objetivo de la implementación no es simplemente utilizar la mayor cantidad posible de threads.

El objetivo es identificar:

**qué operaciones pueden paralelizarse, cómo hacerlo correctamente y cuándo el costo de utilizar paralelismo se justifica por la mejora obtenida.**

La comparación entre la versión secuencial y la versión paralela permitirá evaluar estos aspectos utilizando datos experimentales.

---

# Fin

## Simulación de Predicción Climática

**C + OpenMP**

### Conceptos aplicados

`parallel for` · `sections` · `shared` · `private` · `firstprivate` · `reduction`

### Métricas

**Speedup · Eficiencia**
