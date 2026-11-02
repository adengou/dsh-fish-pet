"""ABC 谱 -> 桌宠 melodies.json 条目。

只处理单声部旋律（V:1），支持：
  - 音高 A-G a-g 与 ' , 八度标记
  - 临时升降 ^ _ = 与调号的降号表
  - 时值数字、/2 等
  - z 休止、| 小节线、|: :| 反复记号（反复只演奏一遍）
  - 和弦 [..] 取最高音
用法：
  python tools/abc_to_melody.py <abc文件> --name 曲名 --bpm 100 [--seconds 60]
"""
import io
import json
import re
import sys

STEP = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

# 调号：给出该调需要降/升的音级（按简谱习惯）
KEY_ACC = {
    'C': {}, 'G': {'F': 1}, 'D': {'F': 1, 'C': 1}, 'A': {'F': 1, 'C': 1, 'G': 1},
    'E': {'F': 1, 'C': 1, 'G': 1, 'D': 1}, 'F': {'B': -1},
    'Bb': {'B': -1, 'E': -1}, 'Eb': {'B': -1, 'E': -1, 'A': -1},
    'Am': {}, 'Em': {'F': 1}, 'Dm': {'B': -1}, 'Gm': {'B': -1, 'E': -1},
    'Cm': {'B': -1, 'E': -1, 'A': -1},
    'Cmix': {'B': -1}, 'Gmix': {}, 'Dmix': {'F': 1},
}


def key_accidentals(key: str):
    k = key.strip()
    # 去掉结尾的 exp/clef 描述，如 "K:Gm clef=treble"
    k = k.split()[0] if k.split() else k
    for name in sorted(KEY_ACC, key=len, reverse=True):
        if k.startswith(name):
            return dict(KEY_ACC[name])
    return {}


def parse_abc(text: str):
    """返回 (notes, units_per_quarter)。notes: [(midi, beats)]"""
    lines = text.replace('\r', '').split('\n')
    fields = {}
    body_lines = []
    voice = None
    for raw in lines:
        line = raw.strip()
        if re.match(r'^[A-Za-z]:', line) and len(line) >= 2 and line[1] == ':':
            f = line[0].upper()
            val = line[2:].strip()
            if f == 'V':
                voice = val.split()[0] if val else '1'
                continue
            fields.setdefault(f, val)
            continue
        if not line or line.startswith('%'):
            continue
        if voice is not None and voice != '1':
            continue          # 只取第一声部
        body_lines.append(line)

    body = ' '.join(body_lines)
    # 去掉注释与多余标记
    body = re.sub(r'%.*', '', body)
    # 去掉 "G" / "Am" 这类和弦标记
    body = re.sub(r'"[^"]*"', ' ', body)
    # 展开附点节奏：X(n)>Y(m) → X(n*3/2) Y(m/2)；< 相反
    def _dot(m):
        a, da, b, db = m.group(1), m.group(2), m.group(3), m.group(4)
        va = float(da) if da else 1.0
        vb = float(db) if db else 1.0
        if m.group(0).find('>') >= 0:
            va, vb = va * 1.5, vb * 0.5
        else:
            va, vb = va * 0.5, vb * 1.5
        return '%s%s %s%s' % (a, _fmtnum(va), b, _fmtnum(vb))
    body = re.sub(r"([A-Ga-g][',]*)(\d*)>([A-Ga-g][',]*)(\d*)", _dot, body)
    body = re.sub(r"([A-Ga-g][',]*)(\d*)<([A-Ga-g][',]*)(\d*)", _dot, body)

    L = fields.get('L', '1/8')
    if '/' in L:
        num, den = L.split('/')
        lval = float(num) / float(den)
    else:
        lval = 1.0 / float(L)
    units_per_quarter = 1.0 / lval / 4.0
    if units_per_quarter <= 0:
        units_per_quarter = 1.0

    key = fields.get('K', 'C')
    keyacc = key_accidentals(key)

    notes = []
    i = 0
    n = len(body)
    cur_acc = {}
    while i < n:
        c = body[i]
        if c in '|:[]{}':
            if c == '|':
                cur_acc = {}
            i += 1
            continue
        if c in ' \t':
            i += 1
            continue
        if c in 'zZxX':
            i += 1
            dur, i = read_dur(body, i, lval)
            notes.append((0, dur / units_per_quarter))
            continue
        acc = None
        if c in '^_=':
            acc = 1 if c == '^' else (-1 if c == '_' else 0)
            i += 1
            if i < n and body[i] == c:      # 双升降
                acc *= 2
                i += 1
        if i >= n:
            break
        letter = body[i]
        if letter.isalpha() and letter.upper() in STEP and letter in 'ABCDEFGabcdefg':
            base = letter.upper()
            octv = 4 if letter.isupper() else 5
            i += 1
            # 八度标记
            while i < n and body[i] in "',":
                if body[i] == "'":
                    octv += 1
                else:
                    octv -= 1
                i += 1
            dur, i = read_dur(body, i, lval)
            semis = STEP[base]
            if acc is None:
                semis += keyacc.get(base, 0)
            else:
                semis += acc
                cur_acc[base] = acc
            m = (octv + 1) * 12 + semis
            notes.append((m, dur / units_per_quarter))
            continue
        if c == '[':
            # 和弦：取最高音
            j = body.find(']', i)
            if j < 0:
                i += 1
                continue
            chord = body[i + 1:j]
            tones = re.findall(r'([\^_=]*)([A-Ga-g])', chord)
            best = None
            for a, lt in tones:
                octv = 4 if lt.isupper() else 5
                s = STEP[lt.upper()]
                acc2 = 0
                for ch in a:
                    acc2 += 1 if ch == '^' else (-1 if ch == '_' else 0)
                s += acc2 if a else keyacc.get(lt.upper(), 0)
                m = (octv + 1) * 12 + s
                if best is None or m > best:
                    best = m
            i = j + 1
            dur, i = read_dur(body, i, lval)
            if best is not None:
                notes.append((best, dur / units_per_quarter))
            continue
        i += 1
    return notes, units_per_quarter


def read_dur(s, i, lval):
    """读时值，返回 (以 L 为单位的长度, 新位置)"""
    n = len(s)
    start = i
    num = ''
    while i < n and s[i].isdigit():
        num += s[i]
        i += 1
    div = ''
    if i < n and s[i] == '/':
        i += 1
        while i < n and s[i].isdigit():
            div += s[i]
            i += 1
        if not div:
            div = '2'
    if num == '' and div == '':
        return 1.0, i
    length = float(num) if num else 1.0
    if div:
        length = length / float(div)
    return length, i


def _fmtnum(v):
    """把浮点时值写回 abc 数字形式（2.0 -> '2'，0.5 -> '/2'）"""
    if v <= 0:
        return '1'
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    # 形如 1.5 -> '3/2'
    num = int(round(v * 2))
    return '%d/2' % num

def note_name(midi):
    return '%s%d' % (NAMES[midi % 12], midi // 12 - 1)


def to_melody(notes, bpm, seconds=None, transpose=0):
    out = []
    total = 0.0
    for m, beats in notes:
        if beats <= 0:
            continue
        if seconds and total * 60.0 / bpm >= seconds:
            break
        if m <= 0:
            out.append(['R', round(beats, 3)])
        else:
            out.append([note_name(m + transpose), round(beats, 3)])
        total += beats
    return out, total


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    name = 'abc-song'
    bpm = 100
    seconds = None
    transpose = 0
    for k in range(2, len(sys.argv) - 1):
        if sys.argv[k] == '--name':
            name = sys.argv[k + 1]
        elif sys.argv[k] == '--bpm':
            bpm = int(sys.argv[k + 1])
        elif sys.argv[k] == '--seconds':
            seconds = float(sys.argv[k + 1])
        elif sys.argv[k] == '--transpose':
            transpose = int(sys.argv[k + 1])
    text = io.open(path, encoding='utf-8-sig', errors='replace').read()
    notes, upq = parse_abc(text)
    melody, total = to_melody(notes, bpm, seconds, transpose)
    dur = total * 60.0 / bpm
    print('曲名: %s  音符 %d 个  总拍 %.1f  时长 %.1f 秒' % (name, len(melody), total, dur))
    print('前 12 音: %s' % ' '.join(x[0] for x in melody[:12]))
    result = {'name': name, 'bpm': bpm, 'notes': melody}
    print(json.dumps(result, ensure_ascii=False)[:400] + '...')
    out = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else None
    if out:
        with io.open(out, 'w', encoding='utf-8') as fh:
            json.dump(result, fh, ensure_ascii=False, indent=1)
        print('已写出: %s' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
