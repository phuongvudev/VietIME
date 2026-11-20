// Từ điển ngoại lệ mặc định: từ tiếng Anh / từ khoá lập trình mà khi gõ Telex
// sẽ vô tình thành một âm tiết tiếng Việt hợp lệ (vd "max" → "mã", "test" → "tét").
// Danh sách được sinh bằng tools/gen_words.sh (từ tools/candidates.txt), đã bỏ các
// từ mà chữ tiếng Việt tương ứng quá phổ biến (sẽ, cả, có, còn, thể, ơn...).
// Chỉ nên bật kiểm tra từ điển cho app lập trình (xem InputController).
#include <stddef.h>

const char *const ve_builtin_english_words[] = {
    "air", "arm", "as", "away", "bar", "best", "born", "box", "buf", "bus",
    "cast", "char", "chore", "chown", "core", "cost", "deep", "def", "defer", "dir",
    "docs", "door", "down", "dust", "eof", "gas", "has", "her", "here", "hex",
    "his", "horse", "host", "how", "if", "ire", "is", "keep", "last", "law",
    "lax", "lets", "life", "lips", "list", "loop", "lose", "low", "maps", "max",
    "meet", "mix", "more", "most", "must", "noon", "nor", "nose", "now", "oar",
    "of", "or", "ore", "orm", "queue", "raw", "ref", "refs", "res", "reset",
    "resp", "rest", "rise", "roof", "room", "root", "rose", "row", "rows", "saw",
    "sax", "see", "seen", "sets", "soon", "sys", "tar", "tax", "taxi", "tee",
    "term", "test", "tex", "this", "tire", "too", "town", "tree", "trust", "turn",
    "two", "use", "user", "users", "var", "vars", "vow", "war", "was", "wax",
    "won", "worm", "wrong", "xor", "yes",
    "data", "goto", "mongo", "sense",
    NULL};
