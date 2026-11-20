# Các bài kiểm tra mở rộng trên corpus — in ra file "phím<TAB>mong đợi" theo từng nhóm.
import sys, random, re, unicodedata
sys.path.insert(0, 'tools')
from gen_typings import decompose, telex  # noqa
random.seed(7)
words = sorted(set(w for line in open('tools/corpus_vi.txt', encoding='utf-8') for w in re.findall(r'[^\W\d_]+', line)))
group = sys.argv[1]

def random_order(w):
    """Phím dấu thanh chèn ở vị trí ngẫu nhiên sau nguyên âm đầu tiên; dấu mũ/móc giữ liền."""
    letters, tone = decompose(w)
    base = telex(letters, 0, 'std')
    if not tone: return base
    tk = 'sfrxj'[tone - 1]
    first_v = next(i for i, ch in enumerate(base) if ch.lower() in 'aeiouy')
    pos = random.randint(first_v + 1, len(base))
    return base[:pos] + tk + base[pos:]

for w in words:
    letters, tone = decompose(w)
    if group == 'upper':
        print(f'{telex(letters, tone, "std").upper()}\t{w.upper()}')
    elif group == 'random':
        for _ in range(3): print(f'{random_order(w)}\t{w}')
    elif group == 'backspace':
        k = telex(letters, tone, 'std')
        # gõ hết, xoá 1 ký tự hiển thị, gõ lại phím cuối cùng tạo ra ký tự đó (chỉ với từ có phụ âm cuối)
        if len(w) >= 3 and w[-1].lower() in 'cmnpt' and not k.endswith(tuple('sfrxj')):
            print(f'{k}<{w[-1]}\t{w}')
