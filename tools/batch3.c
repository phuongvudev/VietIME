// "chữ có sẵn<TAB>phím<TAB>mong đợi": nạp chữ có sẵn (sửa dấu tại chỗ), gõ phím, so sánh.
#include "viet_engine.h"
#include <stdio.h>
#include <string.h>
static int put(uint32_t x, char *o){ if(x<128){o[0]=(char)x;return 1;} if(x<0x800){o[0]=(char)(0xC0|(x>>6));o[1]=(char)(0x80|(x&63));return 2;} o[0]=(char)(0xE0|(x>>12));o[1]=(char)(0x80|((x>>6)&63));o[2]=(char)(0x80|(x&63));return 3;}
static int dec(const char *s, uint32_t *o){int n=0;const unsigned char*p=(const unsigned char*)s;while(*p){if(*p<0x80)o[n++]=*p++;else if((*p&0xE0)==0xC0){o[n++]=((p[0]&31)<<6)|(p[1]&63);p+=2;}else{o[n++]=((p[0]&15)<<12)|((p[1]&63)<<6)|(p[2]&63);p+=3;}}return n;}
int main(void) {
    ve_engine *e = ve_new(); ve_set_english_check(e, 0);
    char line[1024]; int total = 0, bad = 0;
    while (fgets(line, sizeof line, stdin)) {
        char *t1 = strchr(line, '\t'); if (!t1) continue; *t1 = 0;
        char *keys = t1 + 1; char *t2 = strchr(keys, '\t'); if (!t2) continue; *t2 = 0;
        char *want = t2 + 1; want[strcspn(want, "\n")] = 0;
        uint32_t buf[256]; int n = dec(line, buf);
        ve_load_word(e, buf, n);
        for (char *p = keys; *p; p++) {
            ve_result r = ve_process_key(e, (unsigned char)*p);
            if (r.passthrough) { buf[n++] = (unsigned char)*p; continue; }
            n -= r.backspaces; if (n < 0) n = 0;
            for (int j = 0; j < r.insert_len; j++) buf[n++] = r.insert[j];
        }
        char out[1024]; int m = 0; for (int j = 0; j < n; j++) m += put(buf[j], out + m); out[m] = 0;
        total++;
        if (strcmp(out, want)) { bad++; printf("%s + %s → %s (mong đợi %s)\n", line, keys, out, want); }
    }
    fprintf(stderr, "%d/%d đúng\n", total - bad, total);
}
