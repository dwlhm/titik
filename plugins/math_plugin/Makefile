CC ?= clang
CFLAGS ?= -O2 -fPIC -Wall -Wextra
DYLIB_FLAGS ?= -dynamiclib
TARGET ?= math.dylib
SRC = math_plugin.c

all: $(TARGET)

$(TARGET): $(wildcard $(SRC))
	@if [ -f "$(SRC)" ]; then \
		$(CC) $(CFLAGS) $(DYLIB_FLAGS) -o $(TARGET) $(SRC) -lm; \
		echo "==> Built $(TARGET)"; \
	else \
		echo "==> $(SRC) not present yet (will be created in Phase 3C). Skipping plugin build."; \
	fi

clean:
	rm -f $(TARGET) *.o

.PHONY: all clean
