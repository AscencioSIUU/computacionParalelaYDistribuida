import time
from concurrent.futures import ProcessPoolExecutor

def tarea_lenta(n):
    print(f"Iniciando tarea {n}")
    time.sleep(2)
    print(f"Tarea {n} terminada")
    return n

if __name__ == "__main__":

    inicio = time.time()
    with ProcessPoolExecutor() as executor:
        resultados = list(executor.map(tarea_lenta, range(4)))

    print("Resultados:", resultados)
    fin = time.time()
    print(f"Tiempo total: {fin - inicio:.2f} segundos")