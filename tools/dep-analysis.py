"""扫描 assets/lib/*.ps1，分析每个模块对主脚本的隐式依赖。

用法：python tools/dep-analysis.py
输出：每个模块 -> 需要主脚本提供哪些函数 / 哪些 $script: 变量
"""
import io
import os
import re
import sys

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(PKG, 'assets', 'fish-pet.ps1')
LIB = os.path.join(PKG, 'assets', 'lib')


def read(path):
    return io.open(path, encoding='utf-8-sig').read()


def functions_of(text):
    return set(m.group(1) for m in re.finditer(r'^\s*function\s+([A-Za-z0-9_\-]+)', text, re.M))


def script_vars_of(text):
    return set(m.group(1) for m in re.finditer(r'\$script:([A-Za-z0-9_]+)', text))


def main():
    main_text = read(MAIN)
    main_funcs = functions_of(main_text)
    mods = sorted(f for f in os.listdir(LIB) if f.endswith('.ps1'))

    mod_funcs = {}
    for name in mods:
        mod_funcs[name] = functions_of(read(os.path.join(LIB, name)))

    other_defined = {}
    for name in mods:
        others = set()
        for k, v in mod_funcs.items():
            if k != name:
                others |= v
        other_defined[name] = others

    print('主脚本: %d 行, 定义 %d 个函数' % (len(main_text.splitlines()), len(main_funcs)))
    print()
    report = {}
    for name in mods:
        text = read(os.path.join(LIB, name))
        own = mod_funcs[name]
        # 主脚本提供、本模块没定义、被本模块调用的函数
        needed_funcs = []
        for f in sorted(main_funcs):
            if f in own or f in other_defined[name]:
                continue
            if re.search(r'(?<![\w\-])' + re.escape(f) + r'(?![\w\-])', text):
                needed_funcs.append(f)
        # $script: 变量
        vars_used = sorted(script_vars_of(text) - script_vars_of(''))
        report[name] = (needed_funcs, vars_used)
        print('%-20s %3d 行' % (name, len(text.splitlines())))
        print('  依赖函数: %s' % (', '.join(needed_funcs) if needed_funcs else '(无)'))
        print('  script 变量: %s' % (', '.join(vars_used) if vars_used else '(无)'))

    # 交叉依赖：模块 A 调用模块 B 的函数
    print()
    print('模块间调用:')
    cross = False
    for name in mods:
        text = read(os.path.join(LIB, name))
        own = mod_funcs[name]
        called = []
        for k, v in mod_funcs.items():
            if k == name:
                continue
            for f in sorted(v):
                if f in own:
                    continue
                if re.search(r'(?<![\w\-])' + re.escape(f) + r'(?![\w\-])', text):
                    called.append('%s() -> %s' % (f, k))
        if called:
            cross = True
            print('  %s: %s' % (name, ', '.join(sorted(set(called)))))
    if not cross:
        print('  (无)')


if __name__ == '__main__':
    sys.exit(main())
