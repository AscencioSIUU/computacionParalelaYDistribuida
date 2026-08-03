import time
from multiprocessing import Process

def tarea_lenta(n):
    print(f"Iniciando tarea {n}")
    time.sleep(2)
    print(f"Tarea {n} terminada")
    return n

if __name__ == "__main__":
    procesos = []
    inicio = time.time()

    for i in range(4):
        p = Process(target=tarea_lenta, args=(i,))
        procesos.append(p)
        p.start()

    for p in procesos:
        p.join()

    fin = time.time()
    print(f"Tiempo total: {fin - inicio:.2f} segundos")