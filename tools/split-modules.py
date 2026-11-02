"""把 fish-pet.ps1 里的绘图 / UI / 菜单三块拆成 assets/lib 模块。

策略：按行区间抽取（保留原有顺序），在原位置留下 dot-source，
避免因为移动位置导致变量初始化顺序变化。
"""
import io
import os

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(PKG, 'assets', 'fish-pet.ps1')
LIB = os.path.join(PKG, 'assets', 'lib')

# (模块名, 说明, [(起, 止), ...] 1-based 闭区间)
PLAN = [
    ('ui.ps1', '气泡与输入框（WinForms 弹窗）', [(933, 970), (994, 1055)]),
    ('menu.ps1', '右键菜单构建', [(664, 773)]),
    ('draw.ps1', '画鱼（GDI+ 逐帧绘制）', [(327, 330), (331, 365), (425, 630)]),
]

GUARD = {
    'ui.ps1': ['function Show-Input', 'function Show-Bubble'],
    'menu.ps1': ['# ---------- 菜单 ----------', '$miVersion.Enabled = $false'],
    'draw.ps1': ['function New-Solid', 'function Draw-Fish'],
}


def read_lines(path):
    return io.open(path, encoding='utf-8-sig').read().splitlines()


def main():
    lines = read_lines(MAIN)
    # 校验边界
    for name, desc, ranges in PLAN:
        for (a, b) in ranges:
            seg = '\n'.join(lines[a - 1:b])
            if 'function' not in seg and '$menu' not in seg:
                raise SystemExit('%s: %d-%d 区间看起来不对' % (name, a, b))

    # 收集要抽取的行（模块 -> [(起, 止)]），以及每个模块首次出现位置
    blocks = {}
    for name, desc, ranges in PLAN:
        blocks[name] = (desc, sorted(ranges))

    # 重建主脚本
    out = []
    i = 1
    total = len(lines)
    emitted = set()
    starts = {}
    for name, (desc, ranges) in blocks.items():
        for (a, b) in ranges:
            starts[a] = (name, desc, b)
    while i <= total:
        if i in starts:
            name, desc, b = starts[i]
            if name not in emitted:
                out.append('')
                out.append('# %s，实现在 lib\\%s' % (desc, name))
                out.append(". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\%s')" % name)
                emitted.add(name)
            i = b + 1
            continue
        out.append(lines[i - 1])
        i += 1

    # 写模块文件
    for name, (desc, ranges) in blocks.items():
        body = []
        for (a, b) in ranges:
            body.extend(lines[a - 1:b])
            body.append('')
        header = ['# ============================================================',
                  '# %s — %s' % (name, desc),
                  '# 依赖声明（自动生成，勿手改）：见 tools\\add-module-headers.py 输出',
                  '# ============================================================',
                  '']
        with io.open(os.path.join(LIB, name), 'w', encoding='utf-8-sig', newline='\r\n') as fh:
            fh.write('\n'.join(header + body).rstrip() + '\n')
        print('写出 %s（%d 行）' % (name, len(header) + len(body)))

    with io.open(MAIN, 'w', encoding='utf-8-sig', newline='\r\n') as fh:
        fh.write('\n'.join(out).rstrip() + '\n')
    print('主脚本：%d 行 → %d 行' % (total, len(out)))


if __name__ == '__main__':
    main()
