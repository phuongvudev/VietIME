// VietEngine — lõi bộ gõ tiếng Việt (Telex / VNI)
// Thiết kế cho InputMethodKit chế độ "thay chữ trực tiếp":
// mỗi phím trả về "xoá N ký tự cuối, chèn chuỗi S".
#ifndef VIET_ENGINE_H
#define VIET_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    VE_TELEX = 0,
    VE_VNI = 1
} ve_method;

#define VE_MAX_INSERT 96

typedef struct {
    /// 1 = app tự chèn phím vừa gõ (bộ gõ không can thiệp) → trả false cho IMK.
    int passthrough;
    /// Số ký tự cần xoá ngay trước con trỏ.
    int backspaces;
    /// Chuỗi cần chèn (Unicode scalar).
    int insert_len;
    uint32_t insert[VE_MAX_INSERT];
} ve_result;

typedef struct ve_engine ve_engine;

ve_engine *ve_new(void);
void ve_free(ve_engine *e);

// ----- Tuỳ chọn -----
void ve_set_method(ve_engine *e, ve_method m);
/// 1 = đặt dấu kiểu mới (hoà, thuỷ), 0 = kiểu cũ (hòa, thủy). Mặc định 1.
void ve_set_modern_tone(ve_engine *e, int on);
/// Tự khôi phục chữ gốc khi không phải âm tiết tiếng Việt hợp lệ. Mặc định 1.
void ve_set_auto_restore(ve_engine *e, int on);
/// Giữ nguyên các từ tiếng Anh / từ khoá lập trình trong từ điển. Mặc định 1.
void ve_set_english_check(ve_engine *e, int on);
/// Cho phép bỏ dấu mũ / đ cách xa (vd "tana" → "tân"). Mặc định 0 (an toàn khi gõ code).
void ve_set_free_marking(ve_engine *e, int on);
/// Telex: "w" đứng riêng → "ư". Mặc định 1.
void ve_set_w_standalone(ve_engine *e, int on);

/// Thêm một từ (ASCII) vào từ điển ngoại lệ. Trả 1 nếu thêm được.
int ve_add_english_word(ve_engine *e, const char *word);
/// Xoá một từ khỏi từ điển ngoại lệ. Trả 1 nếu có xoá.
int ve_remove_english_word(ve_engine *e, const char *word);
/// Kiểm tra một từ có trong từ điển ngoại lệ không.
int ve_has_english_word(const ve_engine *e, const char *word);

// ----- Xử lý phím -----
/// Xử lý một ký tự vừa gõ (không có Cmd/Ctrl/Option).
/// Telex + từ điển bật: gõ "z" ngay sau một từ ngoại lệ (vd "max") sẽ ép bỏ dấu ("mã").
/// Ký tự không thuộc từ (khoảng trắng, dấu câu, Telex: chữ số...) sẽ kết thúc từ hiện tại
/// và trả passthrough = 1.
ve_result ve_process_key(ve_engine *e, uint32_t ch);

/// Gọi khi người dùng nhấn Backspace. App tự xoá 1 ký tự; engine chỉ cập nhật trạng thái.
void ve_backspace(ve_engine *e);

/// Kết thúc từ hiện tại (đổi con trỏ, click chuột, Enter, Tab, mũi tên, đổi app...).
void ve_reset(ve_engine *e);

/// Nạp một từ đã có sẵn trong văn bản (vd con trỏ đặt ngay sau "việt") làm từ hiện tại,
/// để phím tiếp theo sửa dấu cho nó ("s" → "viết"). Trả 1 nếu sửa dấu được,
/// 0 nếu từ không hợp lệ / quá dài (khi đó engine trống hoặc chỉ chép phím).
int ve_load_word(ve_engine *e, const uint32_t *text, int len);

/// Ký tự có thuộc một từ không (chữ cái Latin, nguyên âm có dấu, đ).
int ve_is_word_char(uint32_t cp);

/// Chữ đang hiển thị của từ hiện tại (để đối chiếu với text trước con trỏ).
/// Trả số ký tự đã ghi (tối đa cap).
int ve_current_word(const ve_engine *e, uint32_t *out, int cap);

// ----- Ngữ cảnh khi gõ code -----
typedef enum {
    VE_CTX_CODE = 0,    /* đang ở code: nên bật từ điển ngoại lệ */
    VE_CTX_COMMENT = 1, /* comment (//, #, --, block, HTML) hoặc dòng Markdown */
    VE_CTX_STRING = 2   /* trong chuỗi '...', "...", `...`, 3 dấu nháy */
} ve_context;

/// Đoán ngữ cảnh tại con trỏ từ đoạn text ngay trước con trỏ (nên lấy vài nghìn ký tự).
ve_context ve_detect_context(const uint32_t *text_before_cursor, int len);

#ifdef __cplusplus
}
#endif

#endif
