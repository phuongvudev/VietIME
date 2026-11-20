# Test lõi C — chạy được trên macOS lẫn Linux, không cần Xcode.
CC ?= cc
CFLAGS = -std=c99 -O1 -g -Wall -Wextra -Werror -I Sources/CVietEngine/include
SAN = -fsanitize=address,undefined
SRC = Sources/CVietEngine/viet_engine.c Sources/CVietEngine/english_words.c Sources/CVietEngine/english_doubles.c Sources/CVietEngine/context.c

.PHONY: test fuzz clean
test:
	$(CC) $(CFLAGS) $(SAN) $(SRC) ctests/test_engine.c -o /tmp/ve_test && /tmp/ve_test

fuzz:
	$(CC) $(CFLAGS) $(SAN) $(SRC) ctests/fuzz_engine.c -o /tmp/ve_fuzz && /tmp/ve_fuzz

clean:
	rm -f /tmp/ve_test /tmp/ve_fuzz
