// Đoán con trỏ đang ở code, comment hay chuỗi — dựa vào text ngay trước con trỏ.
// Không cần biết ngôn ngữ: nhận các kiểu comment/chuỗi phổ biến (C/JS/TS/Swift/Kotlin/Dart/Go/
// Rust/Java, Python, shell, Ruby, YAML, SQL, Lua, HTML, Markdown).
#include "viet_engine.h"

#include <ctype.h>

static int is_space(uint32_t c) { return c == ' ' || c == '\t'; }

ve_context ve_detect_context(const uint32_t *t, int len) {
    enum { S_CODE, S_LINE, S_BLOCK, S_HTML, S_STR } st = S_CODE;
    uint32_t q = 0; /* ký tự mở chuỗi */
    int triple = 0; /* chuỗi 3 dấu nháy (Python, Kotlin, Swift) */
    int line_start = 0;
    for (int i = 0; i < len; i++) {
        uint32_t c = t[i];
        uint32_t n1 = i + 1 < len ? t[i + 1] : 0;
        uint32_t n2 = i + 2 < len ? t[i + 2] : 0;
        uint32_t n3 = i + 3 < len ? t[i + 3] : 0;
        if (c == '\n') line_start = i + 1;
        switch (st) {
        case S_CODE:
            if (c == '/' && n1 == '/') {
                st = S_LINE;
                i++;
            } else if (c == '/' && n1 == '*') {
                st = S_BLOCK;
                i++;
            } else if (c == '<' && n1 == '!' && n2 == '-' && n3 == '-') {
                st = S_HTML;
                i += 3;
            } else if (c == '#' && (i == 0 || is_space(t[i - 1]) || t[i - 1] == '\n') &&
                       (n1 == ' ' || n1 == '\t' || n1 == '#' || n1 == '!')) {
                /* "# ..." (Python, shell, YAML, Markdown) — không phải #include, #if, #fff */
                st = S_LINE;
            } else if (c == '-' && n1 == '-' && (n2 == ' ' || n2 == '\t')) {
                st = S_LINE; /* SQL, Lua, Haskell */
                i++;
            } else if (c == '"' || c == '`' ||
                       (c == '\'' && !(i > 0 && t[i - 1] < 128 && isalnum((int)t[i - 1])))) {
                q = c;
                triple = (c != '`' && n1 == c && n2 == c);
                if (triple) i += 2;
                st = S_STR;
            }
            break;
        case S_LINE:
            if (c == '\n') st = S_CODE;
            break;
        case S_BLOCK:
            if (c == '*' && n1 == '/') {
                st = S_CODE;
                i++;
            }
            break;
        case S_HTML:
            if (c == '-' && n1 == '-' && n2 == '>') {
                st = S_CODE;
                i += 2;
            }
            break;
        case S_STR:
            if (c == '\\') {
                i++;
            } else if (c == q) {
                if (!triple) {
                    st = S_CODE;
                } else if (n1 == q && n2 == q) {
                    st = S_CODE;
                    i += 2;
                }
            } else if (c == '\n' && !triple && q != '`') {
                st = S_CODE; /* chuỗi một dòng chưa đóng */
            }
            break;
        }
    }
    if (st == S_LINE || st == S_BLOCK || st == S_HTML) return VE_CTX_COMMENT;
    if (st == S_STR) return VE_CTX_STRING;

    /* Dòng văn bản: tiếp nối block comment "* ", Markdown "- ", "> ", "+ ", "1. " */
    int i = line_start;
    while (i < len && is_space(t[i])) i++;
    if (i < len) {
        uint32_t c = t[i], n1 = i + 1 < len ? t[i + 1] : 0;
        if ((c == '*' || c == '-' || c == '>' || c == '+') && (n1 == ' ' || n1 == '\t')) return VE_CTX_COMMENT;
        int j = i;
        while (j < len && t[j] < 128 && isdigit((int)t[j])) j++;
        if (j > i && j + 1 < len && t[j] == '.' && t[j + 1] == ' ') return VE_CTX_COMMENT;
    }
    return VE_CTX_CODE;
}
