"""按主人提供的简谱录入《友谊天长地久》（1=F，3/4）。

谱面（图片 scores\\youyi.png，逐小节）：
  5̲ | 1 - 1 | 1 - 3 | 2 - 1 | 2 - 3 | 1 - 1 | 3 - 5 |
  6 - - | 6 - 6 | 5 - 3 | 3 - 1 | 2 - 1 | 2 - 3 | 1 - 6 | 6 - 5 |
  1 - - | 1 - 6 | 5 - 3 | 3 - 1 | 2 - 1 | 2 - 6 | 5 - 3 |
  3 - 5 | 6 - - | 6 - 1̇ | 5 - 3 | 3 - 1 |
  2 - 1 | 2 - 3 | 1 - 6 | 6 - 5 | 1 - - | 1
"""
import io
import json
import os

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(PKG, 'assets', 'data', 'melodies.json')

# 1=F：1=F4 2=G4 3=A4 5=C5 6=D5；低音5=C4；高音1̇=F5
BARS = [
    [['F4', 2], ['F4', 1]],      # 1 - 1
    [['F4', 2], ['A4', 1]],      # 1 - 3
    [['G4', 2], ['F4', 1]],      # 2 - 1
    [['G4', 2], ['A4', 1]],      # 2 - 3
    [['F4', 2], ['F4', 1]],      # 1 - 1
    [['A4', 2], ['C5', 1]],      # 3 - 5
    [['D5', 3]],                 # 6 - -
    [['D5', 2], ['D5', 1]],      # 6 - 6
    [['C5', 2], ['A4', 1]],      # 5 - 3
    [['A4', 2], ['F4', 1]],      # 3 - 1
    [['G4', 2], ['F4', 1]],      # 2 - 1
    [['G4', 2], ['A4', 1]],      # 2 - 3
    [['F4', 2], ['D5', 1]],      # 1 - 6
    [['D5', 2], ['C5', 1]],      # 6 - 5
    [['F4', 3]],                 # 1 - -
    [['F4', 2], ['D5', 1]],      # 1 - 6
    [['C5', 2], ['A4', 1]],      # 5 - 3
    [['A4', 2], ['F4', 1]],      # 3 - 1
    [['G4', 2], ['F4', 1]],      # 2 - 1
    [['G4', 2], ['D5', 1]],      # 2 - 6
    [['C5', 2], ['A4', 1]],      # 5 - 3
    [['A4', 2], ['C5', 1]],      # 3 - 5
    [['D5', 3]],                 # 6 - -
    [['D5', 2], ['F5', 1]],      # 6 - 1̇
    [['C5', 2], ['A4', 1]],      # 5 - 3
    [['A4', 2], ['F4', 1]],      # 3 - 1
    [['G4', 2], ['F4', 1]],      # 2 - 1
    [['G4', 2], ['A4', 1]],      # 2 - 3
    [['F4', 2], ['D5', 1]],      # 1 - 6
    [['D5', 2], ['C5', 1]],      # 6 - 5
    [['F4', 3]],                 # 1 - -
    [['F4', 1]],                 # 1（终止）
]

for i, bar in enumerate(BARS):
    s = sum(x[1] for x in bar)
    if i == len(BARS) - 1:
        # 末小节是单拍收尾（谱面最后单独一个「1」）
        if s > 3:
            raise SystemExit('末小节超过 3 拍：%r 合计 %s' % (bar, s))
        continue
    if abs(s - 3) > 1e-9:
        raise SystemExit('第 %d 小节不是 3 拍：%r 合计 %s' % (i + 1, bar, s))

notes = [['C4', 1.0]]  # 弱起低音 5
for bar in BARS:
    for n, d in bar:
        notes.append([n, float(d)])

total = sum(x[1] for x in notes)
song = {
    'name': '友谊天长地久',
    'aliases': ['auld', '友谊'],
    'bpm': 100,
    'lyrics': '怎能忘记旧日朋友，心中能不怀想',
    'notes': notes,
    'source': '简谱（主人提供，1=F，3/4；scores\\youyi.png 逐小节录入）',
}

d = json.load(io.open(P, encoding='utf-8'))
d['songs'] = [s for s in d['songs'] if s['name'] not in ('友谊天长地久', '友谊地久天长')]
d['songs'].append(song)
json.dump(d, io.open(P, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print('小节 %d 个，音符 %d 个，总拍 %.0f，bpm %d，时长 %.1f 秒'
      % (len(BARS), len(notes), total, song['bpm'], total * 60.0 / song['bpm']))
print('曲库 %d 首: %s' % (len(d['songs']), ' / '.join(s['name'] for s in d['songs'])))
