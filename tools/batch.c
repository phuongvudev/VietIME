// Đọc "phím<TAB>mong đợi" từ stdin, gõ từng dòng, in các dòng sai.
#include "viet_engine.h"
#include <stdio.h>
#include <string.h>
static int put(uint32_t x, char *o){ if(x<128){o[0]=(char)x;return 1;} if(x<0x800){o[0]=(char)(0xC0|(x>>6));o[1]=(char)(0x80|(x&63));return 2;} o[0]=(char)(0xE0|(x>>12));o[1]=(char)(0x80|((x>>6)&63));o[2]=(char)(0x80|(x&63));return 3;}
int main(int argc, char **argv) {
    ve_engine *e = ve_new();
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "vni")) ve_set_method(e, VE_VNI);
        if (!strcmp(argv[i], "code")) ve_set_english_check(e, 1);
        if (!strcmp(argv[i], "prose")) ve_set_english_check(e, 0);
        if (!strcmp(argv[i], "old")) ve_set_modern_tone(e, 0);
    }
    char line[1024]; int total = 0, bad = 0;
    while (fgets(line, sizeof line, stdin)) {
        char *tab = strchr(line, '\t'); if (!tab) continue;
        *tab = 0; char *want = tab + 1; want[strcspn(want, "\n")] = 0;
        uint32_t buf[256]; int n = 0; ve_reset(e);
        for (char *p = line; *p; p++) {
            ve_result r = ve_process_key(e, (unsigned char)*p);
            if (r.passthrough) { buf[n++] = (unsigned char)*p; continue; }
            n -= r.backspaces; if (n < 0) n = 0;
            for (int j = 0; j < r.insert_len; j++) buf[n++] = r.insert[j];
        }
        char out[1024]; int m = 0; for (int j = 0; j < n; j++) m += put(buf[j], out + m); out[m] = 0;
        total++;
        if (strcmp(out, want)) { bad++; printf("%s\t%s\t(mong đợi %s)\n", line, out, want); }
    }
    fprintf(stderr, "%d/%d đúng\n", total - bad, total);
    return 0;
}
