# Sinh nhiều kiểu gõ Telex/VNI cho mỗi từ tiếng Việt trong corpus.
import sys, re, unicodedata
TONES = {'́': ('s', '1'), '̀': ('f', '2'), '̉': ('r', '3'), '̃': ('x', '4'), '̣': ('j', '5')}
MODS = {'̂': 'circ', '̆': 'breve', '̛': 'horn'}
VOW = set('aeiouyAEIOUY')

def decompose(word):
    """→ list of (base, mod, upper), tone_key_index (0..5)"""
    letters, tone = [], 0
    for ch in word:
        if ch in 'đĐ':
            letters.append(['d', 'stroke', ch.isupper()]); continue
        d = unicodedata.normalize('NFD', ch)
        base, mod = d[0], None
        for m in d[1:]:
            if m in TONES: tone = list(TONES).index(m) + 1
            elif m in MODS: mod = MODS[m]
        letters.append([base.lower(), mod, base.isupper()])
    return letters, tone

def key(b, up): return b.upper() if up else b

def telex(letters, tone, style):
    tk = 'sfrxj'[tone - 1] if tone else ''
    out = []
    # vị trí nguyên âm cuối cùng của nhóm nguyên âm
    vidx = [i for i, l in enumerate(letters) if l[0] in 'aeiouy']
    last_v = vidx[-1] if vidx else -1
    tail_mods = []
    for i, (b, m, up) in enumerate(letters):
        out.append(key(b, up))
        mk = ''
        if m == 'circ': mk = b
        elif m in ('breve', 'horn'): mk = 'w'
        elif m == 'stroke': mk = 'd'
        if style in ('std', 'tone_early'):
            if m == 'horn' and b == 'o' and i > 0 and letters[i-1][1] == 'horn' and letters[i-1][0] == 'u':
                mk = ''  # "uwo" tự thành ươ
            out.append(mk)
        elif style == 'mods_end':
            if m == 'stroke': out.append(mk)       # dd phải liền
            elif mk and mk not in tail_mods: tail_mods.append(mk)
        if style == 'tone_early' and i == last_v and tk:
            out.append(tk)
    if style == 'mods_end': out += tail_mods
    if style != 'tone_early': out.append(tk)
    return ''.join(out)

def vni(letters, tone):
    out = []
    for b, m, up in letters:
        out.append(key(b, up))
        if m == 'circ': out.append('6')
        elif m == 'breve': out.append('8')
        elif m == 'horn': out.append('7')
        elif m == 'stroke': out.append('9')
    if tone: out.append(str(tone))
    return ''.join(out).replace('u7o7', 'u7o7')

def main():
  mode = sys.argv[1]
  words = set()
  for line in open(sys.argv[2], encoding='utf-8'):
      for w in re.findall(r'[^\W\d_]+', line):
          words.add(w)
  for w in sorted(words):
      letters, tone = decompose(w)
      if mode == 'vni':
          print(f'{vni(letters, tone)}\t{w}')
      else:
          print(f'{telex(letters, tone, mode)}\t{w}')


if __name__ == '__main__':
    main()