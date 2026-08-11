CC=gcc
CFLAGS=-Wall -Wextra -g
LDFLAGS=-lm
TARGET=main
SRC=$(wildcard src/*.c)
OBJ=$(SRC:.c=.o)

.PHONY: all clean test install

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

test: $(TARGET)
	./$(TARGET) --test

clean:
	rm -f $(OBJ) $(TARGET)

install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/
