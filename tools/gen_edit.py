import re, sys, unicodedata
sys.path.insert(0, 'tools')
from gen_typings import decompose
TONE_MARKS = '̣́̀̉̃'
words = sorted(set(w for line in open('tools/corpus_vi.txt', encoding='utf-8') for w in re.findall(r'[^\W\d_]+', line)))
def strip(w, marks):
    return unicodedata.normalize('NFC', ''.join(c for c in unicodedata.normalize('NFD', w) if c not in marks))
for w in words:
    letters, tone = decompose(w)
    if tone:  # có sẵn chữ không dấu thanh, gõ thêm dấu thanh
        print(f"{strip(w, TONE_MARKS)}\t{'sfrxj'[tone-1]}\t{w}")

# Đổi dấu sai → đúng, và xoá dấu bằng z
T = list(TONE_MARKS)
for w in words:
    letters, tone = decompose(w)
    if not tone: continue
    i = next(k for k, ch in enumerate(w) if any(m in unicodedata.normalize('NFD', ch) for m in T))
    plain_ch = strip(w[i], TONE_MARKS)
    other = T[tone % 5]
    wrong = w[:i] + unicodedata.normalize('NFC', unicodedata.normalize('NFD', plain_ch) + other) + w[i+1:]
    print(f"{wrong}\t{'sfrxj'[tone-1]}\t{w}")
    print(f"{w}\tz\t{strip(w, TONE_MARKS)}")
