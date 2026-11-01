r"""把乐谱合成成 WAV，供桌面鱼播放。

用法：
  python music_gen.py --song 小星星 --out C:\temp\music.wav [--library melodies.json] [--list]

实现：三角波 + ADSR 简化包络，单声道 22050Hz，纯标准库，无第三方依赖。
"""
import argparse
import json
import math
import os
import struct
import sys
import wave

SR = 44100
NOTE_BASE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def note_to_freq(name):
    """C5 -> 523.25Hz；支持 C#5 / Db5"""
    if not name or name[0] in ('R', 'r'):
        return 0.0
    n = name.strip()
    step = NOTE_BASE.get(n[0].upper())
    if step is None:
        return 0.0
    idx = 1
    if len(n) > 1 and n[1] in '#b':
        step += 1 if n[1] == '#' else -1
        idx = 2
    octave = int(n[idx:]) if len(n) > idx else 4
    midi = (octave + 1) * 12 + step
    return 440.0 * (2 ** ((midi - 69) / 12.0))


def render_note(freq, ms, vol=0.32):
    '''带衰减包络与轻揉弦的音色：长音不会像风琴一样平拖'''
    n = int(SR * ms / 1000)
    if n <= 0:
        return b''
    if freq <= 0:
        return b'\x00\x00' * n
    buf = bytearray(n * 2)
    attack = max(1, int(SR * 0.008))
    release = max(1, int(SR * 0.09))
    sustain = 0.55           # 衰减到 55% 后维持
    decay_end = max(1, int(n * 0.45))
    vib_rate = 5.2           # 揉弦 5.2Hz
    vib_depth = 0.0045       # 音高抖动 0.45%
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + vib_depth * math.sin(2 * math.pi * vib_rate * t))
        phase += f / SR
        if phase >= 1.0:
            phase -= 1.0
        tri = 4 * abs(phase - 0.5) - 1
        sine = math.sin(2 * math.pi * phase)
        mix = 0.75 * tri + 0.25 * sine
        if i < attack:
            env = i / attack
        else:
            d = min(1.0, (i - attack) / float(decay_end))
            env = 1.0 - (1.0 - sustain) * d
        if i > n - release:
            env *= max(0.0, (n - i) / float(release))
        v = int(vol * env * mix * 32767)
        v = max(-32767, min(32767, v))
        buf[2 * i] = v & 0xFF
        buf[2 * i + 1] = (v >> 8) & 0xFF
    return bytes(buf)


def load_library(path):
    with open(path, 'r', encoding='utf-8') as fh:
        return json.load(fh)


def find_song(lib, query):
    q = (query or '').strip().lower()
    for s in lib.get('songs', []):
        if s['name'].lower() == q or q in s['name'].lower():
            return s
        for a in s.get('aliases', []):
            if a.lower() == q or q in a.lower():
                return s
    return None


def synth(song, out_path):
    bpm = float(song.get('bpm') or 120)
    beat_ms = 60000.0 / bpm
    gap_ms = 6
    chunks = []
    for item in song.get('notes', []):
        if not item:
            continue
        name = item[0]
        beats = float(item[1]) if len(item) > 1 else 1.0
        ms = beat_ms * beats
        if ms > 1200:
            ms = ms * 0.85
        chunks.append(render_note(note_to_freq(name), ms))
        chunks.append(b'\x00\x00' * int(SR * gap_ms / 1000))
    data = b''.join(chunks)
    tmp = out_path + '.part'
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    os.replace(tmp, out_path)
    return len(data) / 2.0 / SR


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--song')
    ap.add_argument('--out')
    ap.add_argument('--library')
    ap.add_argument('--list', action='store_true')
    args = ap.parse_args()

    lib_path = args.library or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'melodies.json')
    try:
        lib = load_library(lib_path)
    except Exception as exc:
        sys.stderr.write('LIB-ERR %s\n' % exc)
        return 2

    if args.list:
        for s in lib.get('songs', []):
            print(s['name'])
        return 0

    if not args.song or not args.out:
        sys.stderr.write('usage: --song NAME --out FILE\n')
        return 2

    song = find_song(lib, args.song)
    if not song:
        sys.stderr.write('SONG-NOT-FOUND %s\n' % args.song)
        return 3

    try:
        dur = synth(song, args.out)
    except Exception as exc:
        sys.stderr.write('SYNTH-ERR %s\n' % exc)
        return 4
    print('OK %s %.1f' % (args.out, dur))
    return 0


if __name__ == '__main__':
    sys.exit(main())
