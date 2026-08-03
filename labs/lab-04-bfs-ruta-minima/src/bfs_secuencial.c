/*
 * Problema 4: Búsqueda de Ruta Mínima (Grafos)
 * Versión SECUENCIAL — BFS sobre lista de adyacencia.
 *
 * Fases (coinciden con el diagrama de flujo en diagrama/flujo_secuencial.drawio):
 *   1) Inicialización de la red y de las estructuras de BFS.
 *   2) Bucle principal BFS (cola de tareas pendientes).
 *   3) Reconstrucción del camino a partir del arreglo de padres.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <assert.h>

#define MAX_NODOS 1000 // Límite arbitrario para el ejemplo

// --- ESTRUCTURAS DE DATOS ---

// Nodo para la Lista de Adyacencia
typedef struct Nodo {
    int vertice;
    struct Nodo* siguiente;
} Nodo;

// Arreglo global de punteros para el grafo (Lista de adyacencia)
Nodo* grafo[MAX_NODOS];

// --- FUNCIONES AUXILIARES ---

// Agregar una amistad (arista bidireccional)
void agregar_arista(int origen, int destino) {
    // Conexión de origen a destino
    Nodo* nuevo_nodo = (Nodo*)malloc(sizeof(Nodo));
    if (!nuevo_nodo) {
        fprintf(stderr, "[Error] Fallo de asignación de memoria.\n");
        exit(1);
    }
    nuevo_nodo->vertice = destino;
    nuevo_nodo->siguiente = grafo[origen];
    grafo[origen] = nuevo_nodo;

    // Conexión de destino a origen (Grafo no dirigido)
    nuevo_nodo = (Nodo*)malloc(sizeof(Nodo));
    nuevo_nodo->vertice = origen;
    nuevo_nodo->siguiente = grafo[destino];
    grafo[destino] = nuevo_nodo;
}

// --- ALGORITMO PRINCIPAL ---
// Devuelve la longitud del camino encontrado (>=1) o -1 si no hay camino.
// Si camino_out no es NULL, se llena con la secuencia inicio -> ... -> objetivo.
int bfs_camino_mas_corto(int inicio, int objetivo, int* camino_out) {
    // --- FASE 1: Inicialización ---
    int cola[MAX_NODOS];
    int frente = 0, final_cola = 0;

    bool visitados[MAX_NODOS] = {false};
    int padre[MAX_NODOS];

    for (int i = 0; i < MAX_NODOS; i++) {
        padre[i] = -1; // -1 indica que no tiene padre aún
    }

    // Agregar nodo inicial a la cola de tareas pendientes
    cola[final_cola++] = inicio;
    visitados[inicio] = true;

    bool encontrado = false;

    // --- FASE 2: Bucle principal BFS ---
    while (frente < final_cola) { // Mientras la cola no esté vacía
        int actual = cola[frente++]; // Sacar primer nodo (tarea)

        if (actual == objetivo) {
            encontrado = true;
            break;
        }

        // Obtener vecinos del nodo 'actual' y encolarlos si no fueron visitados
        Nodo* temporal = grafo[actual];
        while (temporal != NULL) {
            int vecino = temporal->vertice;

            if (!visitados[vecino]) {
                visitados[vecino] = true;     // Marcar visitado
                padre[vecino] = actual;       // Registrar padre para reconstrucción
                cola[final_cola++] = vecino;  // Encolar como nueva tarea pendiente
            }
            temporal = temporal->siguiente;
        }
    }

    // --- FASE 3: Reconstrucción del camino ---
    if (!encontrado) {
        return -1;
    }

    int longitud_camino = 0;
    int nodo_actual = objetivo;
    int camino[MAX_NODOS];

    while (nodo_actual != -1) {
        camino[longitud_camino++] = nodo_actual;
        nodo_actual = padre[nodo_actual];
    }

    // Invertir orden (quedó de objetivo -> inicio) e imprimir / copiar
    printf("Camino más corto encontrado: ");
    for (int i = longitud_camino - 1; i >= 0; i--) {
        printf("%d", camino[i]);
        if (i > 0) printf(" -> ");
        if (camino_out != NULL) {
            camino_out[longitud_camino - 1 - i] = camino[i];
        }
    }
    printf("\n");

    return longitud_camino;
}

// --- FUNCIÓN PRINCIPAL ---

int main() {
    // Inicializar el grafo vacío
    for (int i = 0; i < MAX_NODOS; i++) {
        grafo[i] = NULL;
    }

    // Crear una red social de prueba
    // 0: Alice, 1: Bob, 2: Charlie, 3: David, 4: Eve
    agregar_arista(0, 1); // Alice - Bob
    agregar_arista(0, 2); // Alice - Charlie
    agregar_arista(1, 3); // Bob - David
    agregar_arista(2, 4); // Charlie - Eve
    agregar_arista(3, 4); // David - Eve

    printf("Buscando ruta de Alice (0) a Eve (4)...\n");
    int camino[MAX_NODOS];
    int longitud = bfs_camino_mas_corto(0, 4, camino);

    printf("Buscando ruta de Charlie (2) a Bob (1)...\n");
    bfs_camino_mas_corto(2, 1, NULL);

    // --- Verificación (ponytail: smoke test mínimo, no un framework de tests) ---
    // Alice(0) -> Charlie(2) -> Eve(4) es el camino más corto posible (2 saltos, 3 nodos).
    assert(longitud == 3);
    assert(camino[0] == 0 && camino[2] == 4);
    printf("[OK] Verificación de camino Alice->Eve pasó correctamente.\n");

    return 0;
}
