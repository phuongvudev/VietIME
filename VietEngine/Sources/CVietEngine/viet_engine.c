// VietEngine — lõi bộ gõ tiếng Việt.
//
// Ý tưởng chính: engine giữ lại chuỗi phím thô (raw) của từ đang gõ và
// mỗi lần có phím mới thì DỰNG LẠI toàn bộ chữ từ raw. Nhờ vậy:
//   - Dấu thanh là thuộc tính của cả âm tiết, vị trí dấu luôn tính lại đúng.
//   - Khôi phục chữ gốc (từ tiếng Anh, code) chỉ là trả về raw.
//   - Kết quả là "xoá N ký tự, chèn S" bằng cách so khớp tiền tố → ít thay chữ nhất,
//     giữ suggestion của editor.

#include "viet_engine.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#define MAXW 32 /* số phím tối đa của một từ còn được xử lý */

enum { M_NONE = 0, M_CIRC = 1, M_BREVE = 2, M_HORN = 3, M_STROKE = 4 };

typedef struct {
    char base;  /* 'a'..'z' hoặc '0'..'9' (chữ số VNI không dùng làm dấu) */
    char mod;   /* M_* */
    char upper; /* 1 = chữ hoa */
    char autohorn; /* móc của "ơ" do normalize tự thêm (gõ "uwo") */
} Letter;

typedef struct {
    Letter L[MAXW * 2];
    int n;
    int tone;    /* 0 không dấu, 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng */
    int literal; /* đã "huỷ dấu" bằng gõ lặp → các phím sau chỉ là chữ thường */
    int tone_undo; /* lần huỷ là do gõ lặp phím thanh Telex (pass, class, off...) */
    int undo_raw;  /* vị trí (trong raw) của phím gõ lặp để huỷ dấu */
    int tone_raw;  /* vị trí (trong raw) của phím đặt dấu thanh hiện tại */
    int cur_raw;   /* vị trí phím đang xử lý */
} Comp;

/* ---------------- Từ điển ngoại lệ (hash set ASCII lowercase) ---------------- */

#define DICT_SIZE 4096 /* luỹ thừa của 2 */

typedef struct {
    char *slots[DICT_SIZE];
    int count;
} Dict;

static uint32_t dict_hash(const char *s) {
    uint32_t h = 2166136261u;
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= 16777619u;
    }
    return h;
}

static int dict_find_slot(const Dict *d, const char *w, int *found) {
    uint32_t i = dict_hash(w) & (DICT_SIZE - 1);
    int first_free = -1;
    for (int probe = 0; probe < DICT_SIZE; probe++) {
        char *s = d->slots[i];
        if (s == NULL) {
            *found = 0;
            return first_free >= 0 ? first_free : (int)i;
        }
        if (s == (char *)1) { /* tombstone */
            if (first_free < 0) first_free = (int)i;
        } else if (strcmp(s, w) == 0) {
            *found = 1;
            return (int)i;
        }
        i = (i + 1) & (DICT_SIZE - 1);
    }
    *found = 0;
    return first_free;
}

static int normalize_word(const char *word, char *buf, int cap) {
    int n = 0;
    for (const char *p = word; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (c > 127 || !isalnum(c)) return 0;
        if (n >= cap - 1) return 0;
        buf[n++] = (char)tolower(c);
    }
    buf[n] = 0;
    return n;
}

static int dict_add(Dict *d, const char *word) {
    char buf[64];
    if (!normalize_word(word, buf, sizeof buf)) return 0;
    if (d->count >= DICT_SIZE * 3 / 4) return 0;
    int found;
    int slot = dict_find_slot(d, buf, &found);
    if (found || slot < 0) return 0;
    size_t len = strlen(buf) + 1;
    char *copy = (char *)malloc(len);
    if (!copy) return 0;
    memcpy(copy, buf, len);
    d->slots[slot] = copy;
    d->count++;
    return 1;
}

static int dict_remove(Dict *d, const char *word) {
    char buf[64];
    if (!normalize_word(word, buf, sizeof buf)) return 0;
    int found;
    int slot = dict_find_slot(d, buf, &found);
    if (!found) return 0;
    free(d->slots[slot]);
    d->slots[slot] = (char *)1;
    d->count--;
    return 1;
}

static int dict_has(const Dict *d, const char *word) {
    char buf[64];
    if (!normalize_word(word, buf, sizeof buf)) return 0;
    int found;
    dict_find_slot(d, buf, &found);
    return found;
}

extern const char *const ve_builtin_english_words[];
int ve_common_english_word(const char *w);

/* ---------------- Engine ---------------- */

struct ve_engine {
    int method, modern, auto_restore, english, free_marking, w_standalone;
    uint32_t raw[MAXW * 2];
    int raw_len;
    uint32_t out[MAXW * 2];
    int out_len;
    int frozen; /* từ này không bỏ dấu nữa, chỉ chép phím */
    int synthetic; /* raw được dựng lại sau Backspace, không phải phím người dùng gõ */
    int force_vn;  /* người dùng gõ "z" sau một từ ngoại lệ → ép bỏ dấu tiếng Việt cho từ này */
    int loaded;    /* từ được nạp từ văn bản có sẵn (sửa dấu) → cho phép bỏ dấu cách xa */
    Dict dict;
};

/* Bảng nguyên âm có dấu: [hoa?][nguyên âm][thanh] */
static const char *const VOWELS_LOWER[12] = {
    "aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
    "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ"};
static const char *const VOWELS_UPPER[12] = {
    "AÁÀẢÃẠ", "ĂẮẰẲẴẶ", "ÂẤẦẨẪẬ", "EÉÈẺẼẸ", "ÊẾỀỂỄỆ", "IÍÌỈĨỊ",
    "OÓÒỎÕỌ", "ÔỐỒỔỖỘ", "ƠỚỜỞỠỢ", "UÚÙỦŨỤ", "ƯỨỪỬỮỰ", "YÝỲỶỸỴ"};
static uint32_t VTAB[2][12][6];
static int vtab_ready = 0;

static const char VBASE[12] = {'a', 'a', 'a', 'e', 'e', 'i', 'o', 'o', 'o', 'u', 'u', 'y'};
static const char VMOD[12] = {M_NONE, M_BREVE, M_CIRC, M_NONE, M_CIRC, M_NONE,
                              M_NONE, M_CIRC,  M_HORN, M_NONE, M_HORN, M_NONE};

static int utf8_decode(const char **ps, uint32_t *cp) {
    const unsigned char *s = (const unsigned char *)*ps;
    if (!*s) return 0;
    if (s[0] < 0x80) { *cp = s[0]; *ps += 1; }
    else if ((s[0] & 0xE0) == 0xC0) { *cp = ((s[0] & 0x1F) << 6) | (s[1] & 0x3F); *ps += 2; }
    else if ((s[0] & 0xF0) == 0xE0) { *cp = ((s[0] & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F); *ps += 3; }
    else { *cp = ((s[0] & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F); *ps += 4; }
    return 1;
}

static void vtab_init(void) {
    if (vtab_ready) return;
    for (int c = 0; c < 2; c++)
        for (int v = 0; v < 12; v++) {
            const char *p = c ? VOWELS_UPPER[v] : VOWELS_LOWER[v];
            for (int t = 0; t < 6; t++) utf8_decode(&p, &VTAB[c][v][t]);
        }
    vtab_ready = 1;
}

static int vowel_index(char base, char mod) {
    for (int i = 0; i < 12; i++)
        if (VBASE[i] == base && VMOD[i] == mod) return i;
    return -1;
}

static int is_vowel(char b) {
    return b == 'a' || b == 'e' || b == 'i' || b == 'o' || b == 'u' || b == 'y';
}

ve_engine *ve_new(void) {
    vtab_init();
    ve_engine *e = (ve_engine *)calloc(1, sizeof(ve_engine));
    if (!e) return NULL;
    e->method = VE_TELEX;
    e->modern = 1;
    e->auto_restore = 1;
    e->english = 1;
    e->free_marking = 0;
    e->w_standalone = 1;
    for (int i = 0; ve_builtin_english_words[i]; i++) dict_add(&e->dict, ve_builtin_english_words[i]);
    return e;
}

void ve_free(ve_engine *e) {
    if (!e) return;
    for (int i = 0; i < DICT_SIZE; i++)
        if (e->dict.slots[i] && e->dict.slots[i] != (char *)1) free(e->dict.slots[i]);
    free(e);
}

void ve_set_method(ve_engine *e, ve_method m) { e->method = m; ve_reset(e); }
void ve_set_modern_tone(ve_engine *e, int on) { e->modern = on ? 1 : 0; }
void ve_set_auto_restore(ve_engine *e, int on) { e->auto_restore = on ? 1 : 0; }
void ve_set_english_check(ve_engine *e, int on) { e->english = on ? 1 : 0; }
void ve_set_free_marking(ve_engine *e, int on) { e->free_marking = on ? 1 : 0; }
void ve_set_w_standalone(ve_engine *e, int on) { e->w_standalone = on ? 1 : 0; }
int ve_add_english_word(ve_engine *e, const char *w) { return dict_add(&e->dict, w); }
int ve_remove_english_word(ve_engine *e, const char *w) { return dict_remove(&e->dict, w); }
int ve_has_english_word(const ve_engine *e, const char *w) { return dict_has(&e->dict, w); }

void ve_reset(ve_engine *e) {
    e->raw_len = 0;
    e->out_len = 0;
    e->frozen = 0;
    e->synthetic = 0;
    e->force_vn = 0;
    e->loaded = 0;
}

int ve_current_word(const ve_engine *e, uint32_t *out, int cap) {
    int n = e->out_len < cap ? e->out_len : cap;
    memcpy(out, e->out, (size_t)n * sizeof(uint32_t));
    return n;
}

static const char *const FINALS[] = {"", "c", "ch", "m", "n", "ng", "nh", "p", "t", NULL};
static int in_list(const char *const *list, const char *s, int prefix);

static int is_valid_syllable(const Comp *c);

/* ---------------- Phân tích âm tiết ---------------- */

/* Tách: [0, os) phụ âm đầu, [os, ne) nguyên âm, [ne, n) phụ âm cuối */
static void parse(const Comp *c, int *os, int *ne) {
    int i = 0;
    while (i < c->n && !is_vowel(c->L[i].base)) i++;
    if (i == 1 && c->L[0].base == 'q' && i < c->n && c->L[i].base == 'u') {
        i++; /* qu */
    } else if (i == 1 && c->L[0].base == 'g' && i + 1 < c->n && c->L[i].base == 'i' &&
               is_vowel(c->L[i + 1].base)) {
        i++; /* gi + nguyên âm */
    }
    int j = i;
    while (j < c->n && is_vowel(c->L[j].base)) j++;
    *os = i;
    *ne = j;
}

static void append_letter(Comp *c, char lo, int up) {
    if (c->n >= MAXW * 2) return;
    c->L[c->n].base = lo;
    c->L[c->n].mod = M_NONE;
    c->L[c->n].upper = (char)up;
    c->L[c->n].autohorn = 0;
    c->n++;
}

/* Huỷ dấu bằng gõ lặp: chèn phím đó như chữ thường và tắt bỏ dấu cho phần còn lại */
static void undo_literal(Comp *c, uint32_t key) {
    append_letter(c, (char)tolower((int)key), isupper((int)key) ? 1 : 0);
    c->literal = 1;
}

/* "qu" chưa có nguyên âm: dấu thanh tạm đặt lên u ("qus" → "qú", gõ tiếp "a" → "quá") */
static int qu_only(const Comp *c, int os, int ne) {
    return ne == os && os == 2 && c->n == 2 && c->L[0].base == 'q' && c->L[1].base == 'u';
}

static int op_tone(Comp *c, int tone, uint32_t key) {
    int os, ne;
    parse(c, &os, &ne);
    if (ne == os && !qu_only(c, os, ne)) return 0;
    if (c->tone == tone) {
        c->tone = 0;
        undo_literal(c, key);
        /* chỉ tính là "gõ lặp" khi hai phím liền nhau (ss, xx, jj) */
        c->tone_undo = !isalpha((int)key) ? 0 : (c->tone_raw == c->cur_raw - 1 ? 1 : 2);
        return 1;
    }
    c->tone = tone;
    c->tone_raw = c->cur_raw;
    return 1;
}

static int op_clear_tone(Comp *c) {
    if (!c->tone) return 0;
    c->tone = 0;
    return 1;
}

/* Dấu mũ: Telex aa/ee/oo (want = 'a'/'e'/'o'), VNI 6 (want = 0: a/e/o bất kỳ) */
static int op_circ(const ve_engine *e, Comp *c, char want, uint32_t key) {
    int os, ne;
    parse(c, &os, &ne);
    if (ne == os) return 0;
    if (!e->free_marking && !e->loaded && ne != c->n) {
        /* Cho phép gõ dấu mũ sau phụ âm cuối hợp lệ: "vietej", "viejte" → "việt",
           "tiengse" → "tiếng". Không cho qua phụ âm cuối lạ ("banana" không thành "bânna"). */
        char fin[8];
        int fl = c->n - ne;
        if (fl > 2) return 0;
        for (int k = 0; k < fl; k++) fin[k] = c->L[ne + k].base;
        fin[fl] = 0;
        if (!in_list(FINALS, fin, 0)) return 0;
    }
    for (int k = ne - 1; k >= os; k--) {
        Letter *l = &c->L[k];
        int match = want ? (l->base == want) : (l->base == 'a' || l->base == 'e' || l->base == 'o');
        if (!match) continue;
        if (want && k != c->n - 1 && l->mod != M_CIRC) {
            /* Không liền nhau: nếu thêm phím này như nguyên âm thường vẫn ra âm tiết hợp lệ
               ("ngoeo", "ngoao") thì coi là nguyên âm, không phải dấu mũ. */
            Comp t = *c;
            append_letter(&t, want, 0);
            if (is_valid_syllable(&t)) return 0;
        }
        if (l->mod == M_CIRC) {
            l->mod = M_NONE;
            undo_literal(c, key);
        } else {
            l->mod = M_CIRC;
        }
        return 1;
    }
    return 0;
}

/* mode 0: Telex w (móc + trăng), 1: VNI 7 (móc), 2: VNI 8 (trăng) */
static int op_horn(const ve_engine *e, Comp *c, int mode, uint32_t key) {
    int os, ne;
    parse(c, &os, &ne);
    if (ne == os) {
        if (mode == 0 && e->w_standalone && os == c->n) {
            append_letter(c, 'u', isupper((int)key) ? 1 : 0);
            c->L[c->n - 1].mod = M_HORN;
            return 1;
        }
        return 0;
    }
    Letter *t1 = NULL, *t2 = NULL;
    char want = M_HORN;
    if (mode != 2) {
        for (int k = os; k + 1 < ne; k++)
            if (c->L[k].base == 'u' && c->L[k + 1].base == 'o') {
                t1 = &c->L[k];
                t2 = &c->L[k + 1];
                break;
            }
    }
    if (!t1 && mode == 0) {
        for (int k = os; k + 1 < ne; k++)
            if (c->L[k].base == 'o' && c->L[k + 1].base == 'a') {
                t1 = &c->L[k + 1];
                want = M_BREVE;
                break;
            }
    }
    if (!t1 && mode != 2) {
        for (int k = os; k < ne && !t1; k++)
            if (c->L[k].base == 'u') t1 = &c->L[k];
        for (int k = os; k < ne && !t1; k++)
            if (c->L[k].base == 'o') t1 = &c->L[k];
    }
    if (!t1 && mode != 1) {
        for (int k = ne - 1; k >= os && !t1; k--)
            if (c->L[k].base == 'a') {
                t1 = &c->L[k];
                want = M_BREVE;
            }
    }
    if (!t1) return 0;
    if (t2 && t2->autohorn && t1->mod == M_HORN && t2->mod == M_HORN) {
        /* "uwow": móc của ơ đã có sẵn, phím w này chỉ xác nhận */
        t2->autohorn = 0;
        return 1;
    }
    if (t1->mod == want && (!t2 || t2->mod == want)) {
        t1->mod = M_NONE;
        if (t2) t2->mod = M_NONE;
        undo_literal(c, key);
        return 1;
    }
    t1->mod = want;
    if (t2) {
        t2->mod = want;
        t2->autohorn = 0;
    }
    return 1;
}

static int op_stroke(const ve_engine *e, Comp *c, uint32_t key) {
    if (c->n < 1 || c->L[0].base != 'd') return 0;
    if (!e->free_marking && !e->loaded && c->n != 1) return 0;
    if (c->L[0].mod == M_STROKE) {
        c->L[0].mod = M_NONE;
        undo_literal(c, key);
    } else {
        c->L[0].mod = M_STROKE;
    }
    return 1;
}

/* "ưo" → "ươ" (người dùng gõ uwo) */
static void normalize(Comp *c) {
    for (int k = 0; k + 1 < c->n; k++)
        if (c->L[k].base == 'u' && c->L[k].mod == M_HORN && c->L[k + 1].base == 'o' &&
            c->L[k + 1].mod == M_NONE) {
            c->L[k + 1].mod = M_HORN;
            c->L[k + 1].autohorn = 1;
        }
}

static void compose(const ve_engine *e, const uint32_t *raw, int len, Comp *c) {
    c->n = 0;
    c->tone = 0;
    c->literal = 0;
    c->tone_undo = 0;
    c->undo_raw = -1;
    c->tone_raw = -1;
    for (int i = 0; i < len; i++) {
        uint32_t k = raw[i];
        c->cur_raw = i;
        char lo = (char)tolower((int)k);
        int up = isupper((int)k) ? 1 : 0;
        if (c->literal) {
            append_letter(c, lo, up);
            continue;
        }
        int handled = 0;
        int was_literal = c->literal;
        if (e->method == VE_TELEX) {
            switch (lo) {
            case 's': handled = op_tone(c, 1, k); break;
            case 'f': handled = op_tone(c, 2, k); break;
            case 'r': handled = op_tone(c, 3, k); break;
            case 'x': handled = op_tone(c, 4, k); break;
            case 'j': handled = op_tone(c, 5, k); break;
            case 'z': handled = op_clear_tone(c); break;
            case 'a': case 'e': case 'o': handled = op_circ(e, c, lo, k); break;
            case 'w': handled = op_horn(e, c, 0, k); break;
            case 'd': handled = op_stroke(e, c, k); break;
            default: break;
            }
        } else {
            switch (lo) {
            case '1': case '2': case '3': case '4': case '5': handled = op_tone(c, lo - '0', k); break;
            case '0': handled = op_clear_tone(c); break;
            case '6': handled = op_circ(e, c, 0, k); break;
            case '7': handled = op_horn(e, c, 1, k); break;
            case '8': handled = op_horn(e, c, 2, k); break;
            case '9': handled = op_stroke(e, c, k); break;
            default: break;
            }
        }
        if (!handled) append_letter(c, lo, up);
        if (!was_literal && c->literal) c->undo_raw = i;
        if (!c->literal) normalize(c);
    }
    /* "ươ" đứng cuối từ (chưa có phụ âm cuối) sau th/h/kh là "uơ": thuở, huơ, khuơ.
       Gõ tiếp phụ âm cuối / i / u thì tự thành ươ (được, người, rượu). */
    if (!c->literal) {
        int os, ne;
        parse(c, &os, &ne);
        if (ne - os == 2 && ne == c->n && c->L[os].base == 'u' && c->L[os].mod == M_HORN &&
            c->L[os + 1].base == 'o' && c->L[os + 1].mod == M_HORN &&
            ((os == 1 && c->L[0].base == 'h') ||
             (os == 2 && (c->L[0].base == 't' || c->L[0].base == 'k') && c->L[1].base == 'h')))
            c->L[os].mod = M_NONE; /* chỉ th-, h-, kh-: thuở, huơ, khuơ */
    }
}

/* ---------------- Vị trí dấu thanh ---------------- */

static int tone_position(const ve_engine *e, const Comp *c) {
    int os, ne;
    parse(c, &os, &ne);
    int n = ne - os;
    if (n <= 0) return qu_only(c, os, ne) ? 1 : -1;
    int last_mod = -1;
    for (int k = os; k < ne; k++)
        if (c->L[k].mod == M_CIRC || c->L[k].mod == M_BREVE || c->L[k].mod == M_HORN) last_mod = k;
    if (last_mod >= 0) return last_mod;
    if (n == 1) return os;
    if (n >= 3) return os + 1;
    /* hai nguyên âm */
    if (ne < c->n) return os + 1; /* có phụ âm cuối: toán, hoàng */
    char a = c->L[os].base, b = c->L[os + 1].base;
    int pair = (a == 'o' && b == 'a') || (a == 'o' && b == 'e') || (a == 'u' && b == 'y');
    if (pair) return e->modern ? os + 1 : os;
    return os;
}

static int render(const ve_engine *e, const Comp *c, uint32_t *out) {
    int pos = c->tone ? tone_position(e, c) : -1;
    int m = 0;
    for (int k = 0; k < c->n; k++) {
        const Letter *l = &c->L[k];
        uint32_t cp;
        if (l->base == 'd' && l->mod == M_STROKE) {
            cp = l->upper ? 0x0110 : 0x0111;
        } else if (is_vowel(l->base)) {
            int vi = vowel_index(l->base, l->mod);
            if (vi < 0) vi = vowel_index(l->base, M_NONE);
            cp = VTAB[l->upper ? 1 : 0][vi][k == pos ? c->tone : 0];
        } else {
            cp = (uint32_t)(l->upper ? toupper((int)l->base) : l->base);
        }
        out[m++] = cp;
    }
    return m;
}

/* ---------------- Kiểm tra chính tả ---------------- */

static const char *const ONSETS[] = {
    "", "b", "c", "ch", "d", "#", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh",
    "nh", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x", NULL};

/* Mã hoá nguyên âm: a ă=A â=B e ê=E i o ô=O ơ=P u ư=U y.
   Cờ: bit0 = đứng cuối được (không phụ âm cuối), bit1 = có phụ âm cuối được. */
typedef struct {
    const char *s;
    int flags;
} Nucleus;

static const Nucleus NUCLEI[] = {
    {"a", 3},   {"A", 2},   {"B", 2},   {"e", 3},   {"E", 3},   {"i", 3},   {"o", 3},
    {"O", 3},   {"P", 3},   {"u", 3},   {"U", 3},   {"y", 1},   {"ai", 1},  {"ao", 1},
    {"au", 1},  {"ay", 1},  {"Bu", 1},  {"By", 1},  {"eo", 1},  {"Eu", 1},  {"ia", 1},
    {"iE", 2},  {"iu", 1},  {"oa", 3},  {"oA", 2},  {"oe", 3},  {"oi", 1},  {"Oi", 1},
    {"Pi", 1},  {"oo", 2},  {"ua", 1},  {"uB", 2},  {"uE", 3},  {"ui", 1},  {"uO", 2},
    {"uP", 1},  {"uy", 3},  {"Ua", 1},  {"Ui", 1},  {"Uu", 1},  {"UP", 2},  {"yE", 2},
    {"iEu", 1}, {"oai", 1}, {"oay", 1}, {"oeo", 1}, {"uBy", 1}, {"uOi", 1}, {"uya", 1},
    {"uyE", 2}, {"uyu", 1}, {"UPi", 1}, {"UPu", 1}, {"yEu", 1}, {NULL, 0}};

static char nucleus_code(const Letter *l) {
    switch (l->mod) {
    case M_BREVE: return 'A';
    case M_CIRC: return l->base == 'a' ? 'B' : l->base == 'e' ? 'E' : 'O';
    case M_HORN: return l->base == 'o' ? 'P' : 'U';
    default: return l->base;
    }
}

static char code_base(char code) {
    switch (code) {
    case 'A': case 'B': return 'a';
    case 'E': return 'e';
    case 'O': case 'P': return 'o';
    case 'U': return 'u';
    default: return code;
    }
}

/* So khớp nucleus đang gõ với bảng; cho phép thiếu dấu mũ/móc (sẽ gõ sau) và
   cho phép là tiền tố khi chưa có phụ âm cuối. */
static int nucleus_ok(const char *nuc, int len, int has_final) {
    for (int i = 0; NUCLEI[i].s; i++) {
        const char *t = NUCLEI[i].s;
        int tl = (int)strlen(t);
        if (has_final) {
            if (tl != len || !(NUCLEI[i].flags & 2)) continue;
        } else if (tl < len) {
            continue;
        }
        int ok = 1;
        for (int k = 0; k < len && ok; k++) {
            if (nuc[k] == t[k]) continue;
            if (code_base(nuc[k]) == nuc[k] && code_base(t[k]) == nuc[k]) continue; /* thiếu dấu */
            ok = 0;
        }
        if (ok) return 1;
    }
    return 0;
}

static int in_list(const char *const *list, const char *s, int prefix) {
    size_t sl = strlen(s);
    for (int i = 0; list[i]; i++) {
        if (prefix ? strncmp(list[i], s, sl) == 0 : strcmp(list[i], s) == 0) return 1;
    }
    return 0;
}

static int is_valid_syllable(const Comp *c) {
    if (c->n == 0) return 1;
    for (int k = 0; k < c->n; k++)
        if (c->L[k].base < 'a' || c->L[k].base > 'z') return 0;
    int os, ne;
    parse(c, &os, &ne);
    char onset[8], nuc[8], fin[8];
    if (os > 4 || ne - os > 3 || c->n - ne > 2) return 0;
    for (int k = 0; k < os; k++) {
        const Letter *l = &c->L[k];
        onset[k] = (l->base == 'd' && l->mod == M_STROKE) ? '#' : l->base;
    }
    onset[os] = 0;
    if (ne == os) return c->n == os && in_list(ONSETS, onset, 1);
    if (!in_list(ONSETS, onset, 0)) return 0;

    for (int k = os; k < ne; k++) nuc[k - os] = nucleus_code(&c->L[k]);
    nuc[ne - os] = 0;
    for (int k = ne; k < c->n; k++) fin[k - ne] = c->L[k].base;
    fin[c->n - ne] = 0;

    /* quy tắc chính tả c/k, g/gh, ng/ngh */
    char v = code_base(nuc[0]);
    int front = (v == 'i' || v == 'e' || v == 'y');
    if (strcmp(onset, "k") == 0 && !front) return 0;
    if (strcmp(onset, "c") == 0 && front) return 0;
    if ((strcmp(onset, "gh") == 0 || strcmp(onset, "ngh") == 0) && !(v == 'i' || v == 'e')) return 0;
    if (strcmp(onset, "g") == 0 && v == 'e') return 0;
    if (strcmp(onset, "ng") == 0 && (v == 'e' || v == 'i')) return 0;

    if (!in_list(FINALS, fin, 0)) return 0;
    if (!nucleus_ok(nuc, ne - os, fin[0] != 0)) return 0;

    /* phụ âm cuối tắc (c, ch, p, t) chỉ đi với sắc / nặng */
    int stop = fin[0] == 'p' || fin[0] == 't' || (fin[0] == 'c');
    if (stop && (c->tone == 2 || c->tone == 3 || c->tone == 4)) return 0;
    return 1;
}

/* camelCase: có chữ hoa đứng sau chữ thường */
static int raw_is_camel(const uint32_t *raw, int len) {
    int seen_lower = 0;
    for (int i = 0; i < len; i++) {
        if (raw[i] < 128 && islower((int)raw[i])) seen_lower = 1;
        else if (raw[i] < 128 && isupper((int)raw[i]) && seen_lower) return 1;
    }
    return 0;
}

static int to_ascii(const uint32_t *s, int len, char *buf, int cap) {
    if (len >= cap) return 0;
    for (int i = 0; i < len; i++) {
        if (s[i] > 127) return 0;
        buf[i] = (char)s[i];
    }
    buf[len] = 0;
    return 1;
}

/* raw[0..k) (k > undo_pos) là một từ tiếng Anh có chữ đôi? */
static int raw_has_english_prefix(const char *raw, int len, int undo_pos) {
    char buf[MAXW * 2 + 1];
    for (int i = 0; i < len; i++) buf[i] = (char)tolower((unsigned char)raw[i]);
    for (int k = len; k > undo_pos && k >= 2; k--) {
        buf[k] = 0;
        if (ve_common_english_word(buf)) return 1;
    }
    return 0;
}

/* Dựng chữ hiển thị cho chuỗi raw (kể cả quyết định khôi phục) */
static int compute_output(const ve_engine *e, const uint32_t *raw, int len, int frozen, int synthetic,
                          uint32_t *out) {
    if (frozen) {
        memcpy(out, raw, (size_t)len * sizeof(uint32_t));
        return len;
    }
    Comp c;
    compose(e, raw, len, &c);
    int m = render(e, &c, out);

    int same = (m == len);
    for (int i = 0; same && i < len; i++) same = (out[i] == raw[i]);
    if (same) return m;

    char rawbuf[MAXW * 2 + 1];
    int raw_ascii = to_ascii(raw, len, rawbuf, sizeof rawbuf);
    int use_raw = 0;
    /* Từ nạp từ văn bản có sẵn (sửa dấu tại chỗ): không đổi về phím thô, để sửa được cả
       chữ đang sai dấu ("bàc" + s → "bác"). */
    if (e->loaded) return m;
    if (e->english && !e->force_vn && raw_ascii && dict_has(&e->dict, rawbuf)) use_raw = 1;
    if (!use_raw && e->auto_restore) {
        if (raw_is_camel(raw, len)) {
            use_raw = 1;
        } else if (!is_valid_syllable(&c)) {
            /* Gõ lặp để huỷ dấu:
               - aaa → aa, ddd → dd, uww → uw, VNI a11 → a1: giữ kết quả (người dùng chủ ý).
               - Lặp phím thanh Telex: nếu chữ gốc là từ tiếng Anh có chữ đôi (pass, class,
                 error, offset, passwd...) thì giữ chữ gốc; còn lại hiểu là huỷ dấu
                 (texxt → text, nhajj → nhaj, tesst → test). */
            if (c.literal && !c.tone_undo)
                use_raw = 0;
            else if (c.literal && c.tone_undo == 2)
                use_raw = 1; /* phím thanh lặp cách xa: tests, lists, order → chữ tiếng Anh */
            else if (c.literal)
                use_raw = raw_ascii && raw_has_english_prefix(rawbuf, len, c.undo_raw);
            else
                use_raw = 1;
        }
    }
    if (use_raw && synthetic && c.literal) use_raw = 0; /* raw dựng lại: trả về chữ gốc vô nghĩa */
    if (use_raw) {
        memcpy(out, raw, (size_t)len * sizeof(uint32_t));
        return len;
    }
    return m;
}

/* ---------------- Phím ---------------- */

static int is_word_key(const ve_engine *e, uint32_t ch) {
    if (ch >= 128) return 0;
    if (isalpha((int)ch)) return 1;
    if (e->method == VE_VNI && isdigit((int)ch)) return 1;
    return 0;
}

static void make_diff(ve_result *r, const uint32_t *old, int ol, const uint32_t *nw, int nl, uint32_t key) {
    int p = 0;
    while (p < ol && p < nl && old[p] == nw[p]) p++;
    r->backspaces = ol - p;
    r->insert_len = 0;
    for (int i = p; i < nl && r->insert_len < VE_MAX_INSERT; i++) r->insert[r->insert_len++] = nw[i];
    r->passthrough = (r->backspaces == 0 && r->insert_len == 1 && r->insert[0] == key);
}

ve_result ve_process_key(ve_engine *e, uint32_t ch) {
    ve_result r;
    memset(&r, 0, sizeof r);
    if (!is_word_key(e, ch)) {
        ve_reset(e);
        r.passthrough = 1;
        return r;
    }
    uint32_t old[MAXW * 2];
    int ol = e->out_len;
    memcpy(old, e->out, (size_t)ol * sizeof(uint32_t));

    /* Telex: từ ngoại lệ đang hiện nguyên chữ (max, test) + "z" → ép thành tiếng Việt (mã, tét).
       Phím z không được chèn. */
    if (e->method == VE_TELEX && (ch == 'z' || ch == 'Z') && e->english && !e->force_vn &&
        !e->frozen && e->raw_len > 0 && e->out_len == e->raw_len &&
        memcmp(e->out, e->raw, (size_t)e->raw_len * sizeof(uint32_t)) == 0) {
        char rawbuf[MAXW * 2 + 1];
        if (to_ascii(e->raw, e->raw_len, rawbuf, sizeof rawbuf) && dict_has(&e->dict, rawbuf)) {
            e->force_vn = 1;
            e->out_len = compute_output(e, e->raw, e->raw_len, 0, e->synthetic, e->out);
            make_diff(&r, old, ol, e->out, e->out_len, ch);
            if (r.backspaces || r.insert_len) {
                r.passthrough = 0;
                return r;
            }
            e->force_vn = 0; /* không đổi gì → coi z như phím thường */
        }
    }

    if (e->raw_len >= MAXW) {
        /* từ quá dài: không còn là tiếng Việt, chỉ chép phím */
        if (!e->frozen) {
            memcpy(e->raw, e->out, (size_t)e->out_len * sizeof(uint32_t));
            e->raw_len = e->out_len;
            e->frozen = 1;
        }
        if (e->raw_len < MAXW * 2) e->raw[e->raw_len++] = ch;
        else { r.passthrough = 1; return r; }
    } else {
        e->raw[e->raw_len++] = ch;
    }
    e->out_len = compute_output(e, e->raw, e->raw_len, e->frozen, e->synthetic, e->out);
    make_diff(&r, old, ol, e->out, e->out_len, ch);
    return r;
}

static int is_u_horn(uint32_t cp) {
    for (int u = 0; u < 2; u++)
        for (int t = 0; t < 6; t++)
            if (VTAB[u][10][t] == cp) return 1;
    return 0;
}

/* Chuyển chữ đang hiển thị về chuỗi phím chuẩn (dùng sau Backspace) */
static int text_to_raw(const ve_engine *e, const uint32_t *text, int len, uint32_t *raw, int cap) {
    int n = 0, tone = 0;
#define PUSH(x) do { if (n >= cap) return -1; raw[n++] = (uint32_t)(x); } while (0)
    for (int i = 0; i < len; i++) {
        uint32_t cp = text[i];
        if (cp < 128) { PUSH(cp); continue; }
        if (cp == 0x0110 || cp == 0x0111) {
            PUSH(cp == 0x0110 ? 'D' : 'd');
            PUSH(e->method == VE_TELEX ? 'd' : '9');
            continue;
        }
        int found = 0;
        for (int u = 0; u < 2 && !found; u++)
            for (int v = 0; v < 12 && !found; v++)
                for (int t = 0; t < 6 && !found; t++)
                    if (VTAB[u][v][t] == cp) {
                        found = 1;
                        char b = VBASE[v];
                        PUSH(u ? toupper((int)b) : b);
                        char mod = VMOD[v];
                        /* "ươ": chỉ cần "uw" + "o", normalize sẽ tự thêm móc cho o */
                        int prev_horn_u = (b == 'o' && mod == M_HORN && i > 0 && is_u_horn(text[i - 1]));
                        if (mod == M_CIRC) PUSH(e->method == VE_TELEX ? b : '6');
                        else if (mod == M_BREVE) PUSH(e->method == VE_TELEX ? 'w' : '8');
                        else if (mod == M_HORN && !prev_horn_u) PUSH(e->method == VE_TELEX ? 'w' : '7');
                        if (t) tone = t;
                    }
        if (!found) return -1;
    }
    if (tone) {
        static const char TELEX_TONES[] = {0, 's', 'f', 'r', 'x', 'j'};
        PUSH(e->method == VE_TELEX ? TELEX_TONES[tone] : '0' + tone);
    }
#undef PUSH
    return n;
}

/* Đặt chữ đang hiển thị của từ hiện tại = disp, dựng lại raw tương ứng.
   Trả 1 nếu từ còn sửa dấu được, 0 nếu phải chép nguyên (frozen). */
static int load_display(ve_engine *e, const uint32_t *disp, int dl, int keep_frozen) {
    uint32_t raw[MAXW * 2];
    int rl = (keep_frozen && e->frozen) ? -1 : text_to_raw(e, disp, dl, raw, MAXW);
    uint32_t check[MAXW * 2];
    int ok = 0;
    if (rl > 0) {
        int cl = compute_output(e, raw, rl, 0, 1, check);
        ok = (cl == dl) && memcmp(check, disp, (size_t)dl * sizeof(uint32_t)) == 0;
    }
    if (ok) {
        memcpy(e->raw, raw, (size_t)rl * sizeof(uint32_t));
        e->raw_len = rl;
        e->frozen = 0;
        e->synthetic = !(rl == dl && memcmp(raw, disp, (size_t)dl * sizeof(uint32_t)) == 0);
    } else {
        memcpy(e->raw, disp, (size_t)dl * sizeof(uint32_t));
        e->raw_len = dl;
        e->frozen = 1;
    }
    memcpy(e->out, disp, (size_t)dl * sizeof(uint32_t));
    e->out_len = dl;
    return ok;
}

void ve_backspace(ve_engine *e) {
    if (e->out_len <= 1) {
        ve_reset(e);
        return;
    }
    uint32_t disp[MAXW * 2];
    int dl = e->out_len - 1;
    memcpy(disp, e->out, (size_t)dl * sizeof(uint32_t));
    load_display(e, disp, dl, 1);
}

int ve_is_word_char(uint32_t cp) {
    if (cp < 128) return isalpha((int)cp) ? 1 : 0;
    if (cp == 0x0110 || cp == 0x0111) return 1;
    for (int u = 0; u < 2; u++)
        for (int v = 0; v < 12; v++)
            for (int t = 0; t < 6; t++)
                if (VTAB[u][v][t] == cp) return 1;
    return 0;
}

int ve_load_word(ve_engine *e, const uint32_t *text, int len) {
    ve_reset(e);
    if (len <= 0 || len >= MAXW) return 0;
    for (int i = 0; i < len; i++)
        if (!ve_is_word_char(text[i])) return 0;
    e->loaded = 1;
    int ok = load_display(e, text, len, 0);
    if (!ok) e->loaded = 0;
    return ok;
}
