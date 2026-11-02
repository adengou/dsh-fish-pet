"""录入《片片相思赋予谁》第一页（晓依演唱版，1=♭E，4/4，♩=78）。

谱源：主人提供的高清吉他谱+简谱（scores\\pianpian_guitar.png，第 1 页）。

逐小节（简谱，加点=低八度，♭2=降 2）：
  1  3 5 6 1 7 6 5
  2  6 - - 0
  3  3 5 6 1 6 5 2
  4  3 - - 0
  5  6 1 2 3 2 1
  6  ♭2 - - 0
  7  7 7 7 2 1 7 6
  8  6 - - 0
  9  3 5 6 1 7 6 5
 10  6 - - 0
 11  3 5 6 1 6 5 2
 12  3 - - 0
 13  6 1 2 3 2 1
 14  ♭2 - - 0
 15  7 7 7 1 2 3 1
 16  6 - - 0
"""
import io
import json
import os

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(PKG, 'assets', 'data', 'melodies.json')

# 1=♭E：1=Eb4 2=F4 3=G4 4=Ab4 5=Bb4 6=C5 7=D5
# 低八度（谱面下加点）：1̲=Eb3 2̲=F3 3̲=G3 4̲=Ab3 5̲=Bb3 6̲=C4 7̲=D4
# ♭2̲ = Fb3 = E3
BARS = [
    [['G3', .5], ['Bb3', .5], ['C4', .5], ['Eb3', .5], ['D4', 1], ['C4', .5], ['Bb3', .5]],
    [['C4', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['G3', .5], ['Bb3', .5], ['C4', .5], ['Eb3', .5], ['C4', 1], ['Bb3', .5], ['F3', .5]],
    [['G3', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['C4', .5], ['Eb3', .5], ['F3', .5], ['G3', .5], ['F3', 1], ['Eb3', 1]],
    [['E3', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['D4', .5], ['D4', .5], ['D4', .5], ['F3', .5], ['Eb3', 1], ['D4', .5], ['C4', .5]],
    [['C4', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['G3', .5], ['Bb3', .5], ['C4', .5], ['Eb3', .5], ['D4', 1], ['C4', .5], ['Bb3', .5]],
    [['C4', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['G3', .5], ['Bb3', .5], ['C4', .5], ['Eb3', .5], ['C4', 1], ['Bb3', .5], ['F3', .5]],
    [['G3', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['C4', .5], ['Eb3', .5], ['F3', .5], ['G3', .5], ['F3', 1], ['Eb3', 1]],
    [['E3', 1], ['R', 1], ['R', 1], ['R', 1]],
    [['D4', .5], ['D4', .5], ['D4', .5], ['Eb3', .5], ['F3', .5], ['G3', .5], ['Eb3', 1]],
    [['C4', 1], ['R', 1], ['R', 1], ['R', 1]],
]

for i, bar in enumerate(BARS):
    s = sum(x[1] for x in bar)
    if abs(s - 4) > 1e-9:
        raise SystemExit('第 %d 小节不是 4 拍：%r 合计 %s' % (i + 1, bar, s))

notes = []
for bar in BARS:
    for n, d in bar:
        notes.append([n, float(d)])

total = sum(x[1] for x in notes)
song = {
    'name': '片片相思赋予谁',
    'aliases': ['pianpian', '相思赋予谁'],
    'bpm': 78,
    'lyrics': '柳叶低垂落花飞，漫天花雨绽妩媚',
    'notes': notes,
    'source': '简谱（主人提供高清谱第 1 页，1=♭E，4/4，♩=78）',
}

d = json.load(io.open(P, encoding='utf-8'))
d['songs'] = [s for s in d['songs'] if s['name'] != song['name']]
d['songs'].append(song)
json.dump(d, io.open(P, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print('小节 %d，音符 %d，总拍 %.0f，bpm %d，时长 %.1f 秒'
      % (len(BARS), len(notes), total, song['bpm'], total * 60.0 / song['bpm']))
print('曲库 %d 首: %s' % (len(d['songs']), ' / '.join(s['name'] for s in d['songs'])))
