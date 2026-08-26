CC      := $(shell command -v gcc-16 || command -v gcc-15 || command -v gcc-14 || command -v gcc-13 || echo cc)
CFLAGS  := -O2 -Wall -fopenmp

bin/climate_sim: src/climate_sim.c
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f bin/climate_sim results/*.csv results/*.png

.PHONY: clean
