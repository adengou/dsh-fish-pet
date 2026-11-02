"""给 assets/lib/*.ps1 自动加依赖声明头。

用法：python tools/add-module-headers.py [--check]
  --check  只检查是否已有头，不写文件
"""
import io
import os
import re
import sys

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(PKG, 'assets', 'fish-pet.ps1')
LIB = os.path.join(PKG, 'assets', 'lib')
MARK = '依赖声明（自动生成，勿手改）：'

DESC = {
    'briefing.ps1': '简报 / 公文 / 文件拖拽',
    'chat.ps1': '聊天核心（提示词、请求、回复处理）',
    'dsh.ps1': '把任务转交给 DSH 助手',
    'language.ps1': '菜单与界面语言',
    'music.ps1': '奏乐（曲库 / 简谱合成 / MIDI 渲染 / 播放）',
    'reminders.ps1': '提醒与便签',
    'speech.ps1': 'TTS 语音朗读',
    'vision.ps1': '截图问答（视觉模型）',
    'vision_worker.ps1': '截图问答后台工作脚本',
}


def read(path):
    return io.open(path, encoding='utf-8-sig').read()


def functions_of(text):
    return set(m.group(1) for m in re.finditer(r'^\s*function\s+([A-Za-z0-9_\-]+)', text, re.M))


def script_vars_of(text):
    return set(m.group(1) for m in re.finditer(r'\$script:([A-Za-z0-9_]+)', text))


def build_report():
    main_text = read(MAIN)
    main_funcs = functions_of(main_text)
    mods = sorted(f for f in os.listdir(LIB) if f.endswith('.ps1'))
    texts = {n: read(os.path.join(LIB, n)) for n in mods}
    funcs = {n: functions_of(t) for n, t in texts.items()}

    out = {}
    for name in mods:
        own = funcs[name]
        others = set()
        for k, v in funcs.items():
            if k != name:
                others |= v
        # 依赖主脚本的函数
        dep_funcs = []
        for f in sorted(main_funcs):
            if f in own or f in others:
                continue
            if re.search(r'(?<![\w\-])' + re.escape(f) + r'(?![\w\-])', texts[name]):
                dep_funcs.append(f)
        # 依赖的 script 变量
        dep_vars = sorted(script_vars_of(texts[name]))
        # 调用别的模块
        calls_out = []
        for k, v in funcs.items():
            if k == name:
                continue
            for f in sorted(v):
                if f in own:
                    continue
                if re.search(r'(?<![\w\-])' + re.escape(f) + r'(?![\w\-])', texts[name]):
                    calls_out.append('%s() → %s' % (f, k))
        # 被别的模块调用
        calls_in = []
        for k, t in texts.items():
            if k == name:
                continue
            for f in sorted(own):
                if re.search(r'(?<![\w\-])' + re.escape(f) + r'(?![\w\-])', t):
                    calls_in.append('%s() ← %s' % (f, k))
        out[name] = dict(funcs=dep_funcs, vars=dep_vars,
                         out=sorted(set(calls_out)), inc=sorted(set(calls_in)))
    return out


def header_for(name, info):
    desc = DESC.get(name, '')
    lines = ['# ============================================================',
             '# %s — %s' % (name, desc),
             '# ' + MARK,
             '#   主脚本提供: %s' % (', '.join(info['funcs']) if info['funcs'] else '(无函数依赖)'),
             '#   $script 变量: %s' % (', '.join(info['vars']) if info['vars'] else '(无)')]
    if info['out']:
        lines.append('#   调用其他模块: %s' % '; '.join(info['out']))
    if info['inc']:
        lines.append('#   被其他模块调用: %s' % '; '.join(info['inc']))
    lines.append('# ============================================================')
    return '\n'.join(lines) + '\n\n'


def main():
    check_only = '--check' in sys.argv
    report = build_report()
    changed = []
    for name in sorted(report):
        path = os.path.join(LIB, name)
        text = read(path)
        if MARK in text:
            continue
        changed.append(name)
        if check_only:
            continue
        new_text = header_for(name, report[name]) + text
        with io.open(path, 'w', encoding='utf-8-sig', newline='\r\n') as fh:
            fh.write(new_text)
    if check_only:
        print('缺头文件: %s' % (', '.join(changed) if changed else '无'))
        return 0
    print('已加头: %s' % (', '.join(changed) if changed else '无'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
