// Fuzz: gõ ngẫu nhiên (cả Backspace), kiểm tra chữ engine nghĩ đang hiển thị
// luôn trùng với đuôi của ô text mô phỏng.
#include "viet_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    const char *keys = "aeiouydwsfrxjzqgnhtcbAEOWDS 0123456789<<<||";
    srand(42);
    for (int method = 0; method < 2; method++) {
        ve_engine *e = ve_new();
        ve_set_method(e, method);
        for (int round = 0; round < 20000; round++) {
            ve_set_free_marking(e, round % 3 == 0);
            uint32_t buf[4096]; int n = 0;
            uint32_t word[256]; int wl = 0;
            ve_reset(e);
            int len = rand() % 40;
            for (int i = 0; i < len; i++) {
                char k = keys[rand() % strlen(keys)];
                if (k == '<') { ve_backspace(e); if (n) n--; if (wl) wl--; }
                else if (k == '|') {
                    /* giả lập đặt con trỏ sau một từ có sẵn rồi sửa dấu */
                    int s0 = n;
                    while (s0 > 0 && ve_is_word_char(buf[s0 - 1]) && n - s0 < 20) s0--;
                    if (s0 < n) ve_load_word(e, buf + s0, n - s0); else ve_reset(e);
                }
                else {
                    ve_result r = ve_process_key(e, (unsigned char)k);
                    if (r.passthrough) { buf[n++] = (unsigned char)k; }
                    else {
                        if (r.backspaces > n) { printf("NEG at round %d\n", round); return 1; }
                        n -= r.backspaces;
                        for (int j = 0; j < r.insert_len; j++) buf[n++] = r.insert[j];
                    }
                }
                wl = ve_current_word(e, word, 256);
                if (wl > n || memcmp(word, buf + n - wl, wl * sizeof(uint32_t)) != 0) {
                    printf("MISMATCH method %d round %d\n", method, round); return 1;
                }
            }
        }
        ve_free(e);
    }
    puts("fuzz OK");
    return 0;
}
