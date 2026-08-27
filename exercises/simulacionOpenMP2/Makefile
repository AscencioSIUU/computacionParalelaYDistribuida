ifeq ($(OS),Windows_NT)
  # MinGW-w64 (vía MSYS2) ya provee gcc con OpenMP bajo ese nombre, sin sufijo.
  CC  := gcc
  EXE := .exe
else
  CC  := $(shell command -v gcc-16 || command -v gcc-15 || command -v gcc-14 || command -v gcc-13 || echo cc)
  EXE :=
endif
CFLAGS := -O2 -Wall -fopenmp

bin/climate_sim$(EXE): src/climate_sim.c
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f bin/climate_sim bin/climate_sim.exe results/*.csv results/*.png

.PHONY: clean
