// Test lõi engine: mô phỏng một ô text — áp dụng đúng kết quả "xoá N, chèn S"
// như InputController làm với app thật.
#include "viet_engine.h"
#include <stdio.h>
#include <string.h>

static int fails = 0, total = 0;

static int utf8_put(uint32_t cp, char *o) {
    if (cp < 0x80) { o[0] = (char)cp; return 1; }
    if (cp < 0x800) { o[0] = (char)(0xC0 | (cp >> 6)); o[1] = (char)(0x80 | (cp & 0x3F)); return 2; }
    o[0] = (char)(0xE0 | (cp >> 12)); o[1] = (char)(0x80 | ((cp >> 6) & 0x3F)); o[2] = (char)(0x80 | (cp & 0x3F)); return 3;
}

/* '<' trong input = Backspace, '|' = đổi vị trí con trỏ (reset) */
static void type(ve_engine *e, const char *keys, char *out) {
    uint32_t buf[512];
    int n = 0;
    ve_reset(e);
    for (const char *p = keys; *p; p++) {
        if (*p == '<') { ve_backspace(e); if (n) n--; continue; }
        if (*p == '|') { ve_reset(e); continue; }
        ve_result r = ve_process_key(e, (unsigned char)*p);
        if (r.passthrough) { buf[n++] = (unsigned char)*p; continue; }
        n -= r.backspaces;
        if (n < 0) { strcpy(out, "<<NEG>>"); return; }
        for (int i = 0; i < r.insert_len; i++) buf[n++] = r.insert[i];
    }
    int m = 0;
    for (int i = 0; i < n; i++) m += utf8_put(buf[i], out + m);
    out[m] = 0;
}

static int utf8_decode_str(const char *s, uint32_t *out);

/* Sửa dấu từ đã có: nạp `existing`, gõ `keys`, so với `want` */
static void check_edit(ve_engine *e, const char *existing, const char *keys, const char *want) {
    uint32_t buf[512];
    int n = utf8_decode_str(existing, buf);
    ve_load_word(e, buf, n);
    for (const char *p = keys; *p; p++) {
        ve_result r = ve_process_key(e, (unsigned char)*p);
        if (r.passthrough) { buf[n++] = (unsigned char)*p; continue; }
        n -= r.backspaces;
        for (int i = 0; i < r.insert_len; i++) buf[n++] = r.insert[i];
    }
    char out[1024];
    int m = 0;
    for (int i = 0; i < n; i++) m += utf8_put(buf[i], out + m);
    out[m] = 0;
    total++;
    if (strcmp(out, want) != 0) {
        fails++;
        printf("FAIL  edit %s + %s → \"%s\" (mong đợi \"%s\")\n", existing, keys, out, want);
    }
}

static void check(ve_engine *e, const char *keys, const char *want) {
    char got[2048];
    type(e, keys, got);
    total++;
    if (strcmp(got, want) != 0) {
        fails++;
        printf("FAIL  %-28s → \"%s\"  (mong đợi \"%s\")\n", keys, got, want);
    }
}

static int utf8_decode_str(const char *s, uint32_t *out) {
    int n = 0;
    const unsigned char *p = (const unsigned char *)s;
    while (*p) {
        if (*p < 0x80) out[n++] = *p++;
        else if ((*p & 0xE0) == 0xC0) { out[n++] = ((p[0] & 0x1F) << 6) | (p[1] & 0x3F); p += 2; }
        else { out[n++] = ((p[0] & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F); p += 3; }
    }
    return n;
}

static void ctx(const char *text, ve_context want) {
    uint32_t buf[512];
    int n = utf8_decode_str(text, buf);
    ve_context got = ve_detect_context(buf, n);
    total++;
    if (got != want) {
        fails++;
        printf("FAIL  ctx %-30s → %d (mong đợi %d)\n", text, got, want);
    }
}

int main(void) {
    ve_engine *e = ve_new();

    /* ---- Telex cơ bản ---- */
    check(e, "vieetj", "việt");
    check(e, "Vieetj Nam", "Việt Nam");
    check(e, "VIEETJ NAM", "VIỆT NAM");
    check(e, "tieengs", "tiếng");
    check(e, "tieesng", "tiếng");
    check(e, "nguowif", "người");
    check(e, "nguoiwf", "người");
    check(e, "nguwowif", "người");
    check(e, "dduowcj", "được");
    check(e, "ddi", "đi");
    check(e, "DDi", "Đi");
    check(e, "truowngf", "trường");
    check(e, "truwowngf", "trường");
    check(e, "quas", "quá");
    check(e, "quoocs", "quốc");
    check(e, "gias", "giá");
    check(e, "gif", "gì");
    check(e, "gioos", "giố");
    check(e, "khuyeens", "khuyến");
    check(e, "chuyeenj", "chuyện");
    check(e, "muwa", "mưa");
    check(e, "muaw", "mưa");
    check(e, "hoawcj", "hoặc");
    check(e, "tuowi", "tươi");
    check(e, "ruwowuj", "rượu");
    check(e, "ruowuj", "rượu");
    check(e, "nhaast", "nhất");
    check(e, "ddepj", "đẹp");
    check(e, "laf", "là");
    check(e, "cuar", "của");
    check(e, "nhuwngx", "những");
    check(e, "thuwr", "thử");
    check(e, "gaaps", "gấp");
    check(e, "aw", "ă");
    check(e, "w", "ư");
    check(e, "uw", "ư");
    check(e, "ow", "ơ");
    check(e, "aa", "â");
    check(e, "asz", "á");   /* "as" là từ ngoại lệ → z ép tiếng Việt */
    check(e, "ajz", "a");
    check(e, "tieengs Vieetj raast hay", "tiếng Việt rất hay");
    check(e, "nguyeenx", "nguyễn");
    check(e, "ngoaif", "ngoài");
    check(e, "khuyru", "khuỷu");
    check(e, "luyeenj", "luyện");
    check(e, "yeeu", "yêu");
    check(e, "ddaay", "đây");
    check(e, "Ddaay", "Đây");

    /* ---- Vị trí dấu kiểu mới / cũ ---- */
    check(e, "hoaf", "hoà");
    check(e, "thuyr", "thuỷ");
    check(e, "khoer", "khoẻ");
    check(e, "hoafng", "hoàng");
    check(e, "toans", "toán");
    ve_set_modern_tone(e, 0);
    check(e, "hoaf", "hòa");
    check(e, "thuyr", "thủy");
    check(e, "khoer", "khỏe");
    check(e, "hoafng", "hoàng");
    ve_set_modern_tone(e, 1);

    /* ---- Gõ lặp để huỷ dấu ---- */
    check(e, "ass", "ass");
    check(e, "nhajj", "nhaj");
    check(e, "nhapjj", "nhapj");
    check(e, "texxt", "text");
    check(e, "nhass", "nhas");
    check(e, "laff", "laf");
    check(e, "off", "off");
    check(e, "diff", "diff");
    check(e, "offset", "offset");
    check(e, "passwd", "passwd");
    check(e, "errors", "errors");
    check(e, "array", "array");
    check(e, "buffer", "buffer");
    check(e, "sorry", "sorry");
    check(e, "assets", "assets");
    check(e, "tests", "tests");
    check(e, "order", "order");
    check(e, "wrapper", "wrapper");
    check(e, "vieetjj", "viêtj");
    check(e, "ngoeof", "ngoèo");
    check(e, "ngoeoj", "ngoẹo");
    check(e, "Thuowr", "Thuở");
    check(e, "huow", "huơ");
    check(e, "dduowcj", "được");
    check(e, "huwowu", "hươu");
    check(e, "yeue", "yêu");
    check(e, "qus", "qú");
    check(e, "qusa", "quá");
    check(e, "Qusooc", "Quốc");
    check(e, "qurayeen", "qurayeen");
    check(e, "quryeen", "quyển");
    check(e, "aaa", "aa");
    check(e, "ddd", "dd");
    check(e, "uww", "uw");
    check(e, "tesst", "test");

    /* ---- Gõ code: giữ nguyên tiếng Anh ---- */
    check(e, "pass", "pass");
    check(e, "class", "class");
    check(e, "useEffect", "useEffect");
    check(e, "useState", "useState");
    check(e, "isOwner", "isOwner");
    check(e, "if", "if");
    check(e, "as", "as");
    check(e, "is", "is");
    check(e, "or", "or");
    check(e, "max", "max");
    check(e, "mix", "mix");
    check(e, "test", "test");
    check(e, "var", "var");
    check(e, "for", "for");
    check(e, "const", "const");
    check(e, "return", "return");
    check(e, "function", "function");
    check(e, "string", "string");
    check(e, "fetch", "fetch");
    check(e, "default", "default");
    check(e, "export", "export");
    check(e, "async", "async");
    check(e, "await", "await");
    check(e, "where", "where");
    check(e, "select", "select");
    check(e, "process", "process");
    check(e, "reset", "reset");
    check(e, "address", "address");
    check(e, "success", "success");
    check(e, "error", "error");
    check(e, "for i in range", "for i in range");
    check(e, "def main", "def main");
    check(e, "if x is None", "if x is None");
    check(e, "let user = await fetchUser", "let user = await fetchUser");

    /* ---- Backspace ---- */
    check(e, "tieengs<", "tiến");
    check(e, "tieengs<g", "tiếng");
    check(e, "tieengs<gx", "tiễng");
    check(e, "vieetj<t", "việt");
    check(e, "vieetj<<<", "v");
    check(e, "nguowif<<<", "ng");
    check(e, "nguowif<<", "ngư");
    check(e, "nguowif<<ows", "ngướ");
    check(e, "pass<", "pas");
    check(e, "pass<s", "pass");
    check(e, "ddi<", "đ");
    check(e, "ddi<a", "đa");
    check(e, "nguoiwf<i", "người");
    check(e, "nguoiwf<f", "ngươf");

    /* ---- Đổi con trỏ thì bắt đầu từ mới ---- */
    check(e, "vie|es", "vieé");

    /* ---- Tắt khôi phục: luôn bỏ dấu ---- */
    ve_set_auto_restore(e, 0);
    ve_set_english_check(e, 0);
    check(e, "pass", "pas");
    check(e, "max", "mã");
    ve_set_auto_restore(e, 1);
    ve_set_english_check(e, 1);

    /* ---- Từ điển tuỳ chỉnh ---- */
    check(e, "sex", "sẽ");
    ve_add_english_word(e, "sex");
    check(e, "sex", "sex");
    ve_remove_english_word(e, "sex");
    check(e, "sex", "sẽ");
    ve_set_english_check(e, 0);
    check(e, "max", "mã");
    ve_set_english_check(e, 1);

    /* ---- Free marking ---- */
    check(e, "tana", "tân");   /* dấu mũ sau phụ âm cuối hợp lệ */
    check(e, "banana", "banana");
    check(e, "Viejte", "Việt");
    check(e, "Vietej", "Việt");
    check(e, "tiengse", "tiếng");
    check(e, "ddongof", "đồng");
    check(e, "data", "data");
    ve_set_free_marking(e, 1);
    check(e, "tana", "tân");
    check(e, "dida", "đia");
    ve_set_free_marking(e, 0);

    /* ---- VNI ---- */
    ve_set_method(e, VE_VNI);
    check(e, "vie65t", "việt");
    check(e, "vie6t5", "việt");
    check(e, "tie61ng", "tiếng");
    check(e, "nguo72i", "người");
    check(e, "d9u7o7c5", "được");
    check(e, "d9i", "đi");
    check(e, "hoa85c", "hoặc");
    check(e, "hoa82c", "hoa82c");
    check(e, "a11", "a1");
    check(e, "a10", "a");
    check(e, "tie61ng<", "tiến");
    check(e, "x1", "x1");
    ve_set_method(e, VE_TELEX);

    /* ---- Ép tiếng Việt bằng "z" sau từ ngoại lệ (chế độ code) ---- */
    check(e, "maxz", "mã");
    check(e, "Maxz ddown hangf", "Mã đơn hàng");
    check(e, "testz", "tét");
    check(e, "isz", "í");
    check(e, "texzn", "tẽn");
    check(e, "maxz<", "m");
    check(e, "quiz", "quiz");   /* z thường vẫn là z */
    check(e, "classz", "classz");
    /* ---- Ngữ cảnh tiếng Việt (tắt từ điển): gõ lặp để giữ tiếng Anh ---- */
    ve_set_english_check(e, 0);
    check(e, "max", "mã");
    check(e, "maxx", "max");
    check(e, "test", "tét");
    check(e, "tesst", "test");
    check(e, "maxz", "ma");
    check(e, "asz", "a");
    ve_set_english_check(e, 1);

    /* ---- Sửa dấu từ đã gõ (con trỏ đặt sau từ) ---- */
    check_edit(e, "việt", "s", "viết");
    check_edit(e, "viết", "z", "viêt");
    check_edit(e, "viet", "j", "viẹt");
    check_edit(e, "viet", "ej", "việt");
    check_edit(e, "người", "s", "ngưới");
    check_edit(e, "nguoi", "wf", "người");
    check_edit(e, "hoà", "r", "hoả");
    check_edit(e, "di", "d", "đi");
    check_edit(e, "Viet", "ee", "Viete");  /* ee lặp: huỷ mũ */
    check_edit(e, "Viet", "ej", "Việt");
    check_edit(e, "tan", "a", "tân");
    check_edit(e, "bàc", "s", "bác");
    check_edit(e, "chiềc", "s", "chiếc");
    check_edit(e, "class", "s", "classs");
    check_edit(e, "max", "x", "maxx");
    check_edit(e, "tieng", "s", "tiéng");
    check_edit(e, "tiêng", "s", "tiếng");
    check_edit(e, "class", "s", "classs");

    /* ---- Từ dài ---- */
    check(e, "supercalifragilisticexpialidocious", "supercalifragilisticexpialidocious");

    ve_free(e);

    {
        uint32_t w[] = {0x0111, 'i'};
        total += 3;
        if (!ve_is_word_char(0x1EC7)) { fails++; puts("FAIL is_word_char ệ"); }
        if (ve_is_word_char(' ') || ve_is_word_char('1')) { fails++; puts("FAIL is_word_char space/digit"); }
        ve_engine *e2 = ve_new();
        if (!ve_load_word(e2, w, 2)) { fails++; puts("FAIL load đi"); }
        ve_free(e2);
    }

    /* ---- Nhận biết comment / chuỗi ---- */
    ctx("let x = 1; ", VE_CTX_CODE);
    ctx("let x = 1; // ", VE_CTX_COMMENT);
    ctx("// done\nlet ", VE_CTX_CODE);
    ctx("/* mô tả ", VE_CTX_COMMENT);
    ctx("/* a */ x = ", VE_CTX_CODE);
    ctx("/**\n * Lấy ", VE_CTX_COMMENT);
    ctx("/**\n * a\n */\nfunc ", VE_CTX_CODE);
    ctx("x = 1  # ", VE_CTX_COMMENT);
    ctx("#include <", VE_CTX_CODE);
    ctx("#", VE_CTX_CODE);
    ctx("color: #", VE_CTX_CODE);
    ctx("SELECT * FROM t -- ", VE_CTX_COMMENT);
    ctx("i--; ", VE_CTX_CODE);
    ctx("<!-- ", VE_CTX_COMMENT);
    ctx("title = \"Xin ", VE_CTX_STRING);
    ctx("title = \"a\" + ", VE_CTX_CODE);
    ctx("s = 'don\\'t ", VE_CTX_STRING);
    ctx("msg = `Xin chào ${name} ", VE_CTX_STRING);
    ctx("\"\"\"\nDocstring ", VE_CTX_STRING);
    ctx("\"\"\"\nDoc\n\"\"\"\ndef ", VE_CTX_CODE);
    ctx("x = \"// not comment\"; ", VE_CTX_CODE);
    ctx("url = \"http://", VE_CTX_STRING);
    ctx("// it's \"fine\"\nx = ", VE_CTX_CODE);
    ctx("don't ", VE_CTX_CODE);
    ctx("# Tiêu đề\n", VE_CTX_CODE);
    ctx("## Tiêu ", VE_CTX_COMMENT);
    ctx("- Việc ", VE_CTX_COMMENT);
    ctx("  1. Bước ", VE_CTX_COMMENT);
    ctx("a = b * c", VE_CTX_CODE);

    printf("%d/%d test đạt\n", total - fails, total);
    return fails ? 1 : 0;
}
