r"""MIDI 渲染器：读标准 MIDI 文件，混合渲染成 WAV。

用法：
  python midi_render.py --midi song.mid --out out.wav [--gain 0.8] [--max-seconds 300]

纯标准库实现（SMF format 0/1，支持 note on/off、tempo、多声道混音）。
音准来自 MIDI 本身，不存在“听写不准”的问题。
"""
import argparse
import math
import os
import struct
import sys
import wave

SR = 44100


def read_vlq(data, pos):
    val = 0
    while True:
        b = data[pos]
        pos += 1
        val = (val << 7) | (b & 0x7F)
        if not (b & 0x80):
            return val, pos


def parse_midi(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    if data[:4] != b'MThd':
        raise ValueError('not a midi file')
    hlen = struct.unpack('>I', data[4:8])[0]
    fmt, ntrk, division = struct.unpack('>HHH', data[8:14])
    pos = 8 + hlen
    tracks = []
    for _ in range(ntrk):
        if data[pos:pos + 4] != b'MTrk':
            break
        tlen = struct.unpack('>I', data[pos + 4:pos + 8])[0]
        tdata = data[pos + 8:pos + 8 + tlen]
        pos += 8 + tlen
        tracks.append(tdata)

    # 合并所有轨道的 note 事件，按绝对 tick 排序
    events = []          # (tick, order, kind, channel, note, velocity)
    tempos = []          # (tick, us_per_quarter)
    for tr in tracks:
        p = 0
        tick = 0
        running = None
        while p < len(tr):
            delta, p = read_vlq(tr, p)
            tick += delta
            if p >= len(tr):
                break
            b = tr[p]
            if b == 0xFF:                       # meta
                p += 1
                mtype = tr[p]
                p += 1
                mlen, p = read_vlq(tr, p)
                if mtype == 0x51 and mlen == 3:
                    us = (tr[p] << 16) | (tr[p + 1] << 8) | tr[p + 2]
                    tempos.append((tick, us))
                p += mlen
                continue
            if b in (0xF0, 0xF7):               # sysex
                p += 1
                mlen, p = read_vlq(tr, p)
                p += mlen
                continue
            if b & 0x80:
                status = b
                p += 1
                running = status
            else:
                status = running
                if status is None:
                    p += 1
                    continue
            hi = status & 0xF0
            ch = status & 0x0F
            if hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
                d1 = tr[p]
                d2 = tr[p + 1]
                p += 2
                if hi == 0x90 and d2 > 0:
                    events.append((tick, 1, 'on', ch, d1, d2))
                elif hi == 0x80 or (hi == 0x90 and d2 == 0):
                    events.append((tick, 2, 'off', ch, d1, 0))
            elif hi in (0xC0, 0xD0):
                p += 1
            else:
                p += 1
    events.sort(key=lambda e: (e[0], e[1]))
    tempos.sort()
    return events, tempos, division, fmt


def build_notes(events, tempos, division):
    """把事件流转成 (start_sec, dur_sec, midi_note, velocity) 列表"""
    if not tempos:
        tempos = [(0, 500000)]
    if tempos[0][0] != 0:
        tempos.insert(0, (0, 500000))

    def sec_at(tick):
        sec = 0.0
        prev_tick, prev_us = 0, tempos[0][1]
        for t, us in tempos:
            if t <= tick:
                sec += (t - prev_tick) / division * (prev_us / 1e6)
                prev_tick, prev_us = t, us
            else:
                break
        sec += (tick - prev_tick) / division * (prev_us / 1e6)
        return sec

    active = {}
    notes = []
    for tick, _order, kind, ch, note, vel in events:
        key = (ch, note)
        if kind == 'on':
            active[key] = (tick, vel)
        else:
            if key in active:
                st, v = active.pop(key)
                if tick > st:
                    notes.append((sec_at(st), sec_at(tick) - sec_at(st), note, v))
    return notes


def midi_to_freq(n):
    return 440.0 * (2 ** ((n - 69) / 12.0))


def render(notes, out_path, gain=0.8, max_seconds=300.0):
    if not notes:
        raise ValueError('no notes')
    end = min(max_seconds, max(n[0] + n[1] for n in notes) + 0.5)
    total = int(end * SR) + 1
    buf = [0.0] * total
    for start, dur, note, vel in notes:
        s0 = int(start * SR)
        n = int(min(dur, 8.0) * SR)
        if s0 >= total or n <= 0:
            continue
        freq = midi_to_freq(note)
        amp = (vel / 127.0) * 0.22
        attack = max(1, int(SR * 0.006))
        release = max(1, int(SR * 0.09))
        step = freq / SR
        phase = 0.0
        for i in range(n):
            idx = s0 + i
            if idx >= total:
                break
            phase += step
            if phase >= 1.0:
                phase -= 1.0
            tri = 4 * abs(phase - 0.5) - 1
            sine = math.sin(2 * math.pi * phase)
            v = 0.78 * tri + 0.22 * sine
            env = 1.0
            if i < attack:
                env = i / attack
            elif i > n - release:
                env = max(0.0, (n - i) / release)
            buf[idx] += v * env * amp

    peak = max(1e-6, max(abs(x) for x in buf))
    scale = (gain / peak) if peak > gain else 1.0
    frames = bytearray(total * 2)
    for i, x in enumerate(buf):
        v = int(max(-1.0, min(1.0, x * scale)) * 32767)
        frames[2 * i] = v & 0xFF
        frames[2 * i + 1] = (v >> 8) & 0xFF
    tmp = out_path + '.part'
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    os.replace(tmp, out_path)
    return len(frames) / 2.0 / SR


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--midi', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--gain', type=float, default=0.8)
    ap.add_argument('--max-seconds', type=float, default=300.0)
    args = ap.parse_args()

    try:
        events, tempos, division, fmt = parse_midi(args.midi)
        notes = build_notes(events, tempos, division)
        dur = render(notes, args.out, args.gain, args.max_seconds)
    except Exception as exc:
        sys.stderr.write('MIDI-ERR %s\n' % exc)
        return 3
    print('OK %s %.1f notes=%d fmt=%d' % (args.out, dur, len(notes), fmt))
    return 0


if __name__ == '__main__':
    sys.exit(main())
