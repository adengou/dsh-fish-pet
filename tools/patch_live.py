"""把 live.ps1 接入主脚本：dot-source + 菜单项 + 主循环调用。

运行：python tools/patch_live.py
"""
import io
import os

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(PKG, 'assets', 'fish-pet.ps1')
MENU = os.path.join(PKG, 'assets', 'lib', 'menu.ps1')


def read(p):
    return io.open(p, encoding='utf-8-sig').read()


def write(p, t):
    io.open(p, 'w', encoding='utf-8-sig', newline='\r\n').write(t)


def patch_main():
    t = read(MAIN)
    if 'lib\\live.ps1' in t:
        print('main: 已接入过')
    else:
        anchor = ". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\dsh.ps1')"
        if anchor not in t:
            print('main: 未找到 dsh.ps1 的 dot-source 锚点')
        else:
            t = t.replace(
                anchor,
                anchor + "\r\n\r\n# 直播模式（舞台背景 + 节目单），实现在 lib\\live.ps1\r\n"
                        ". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\live.ps1')")
            print('main: 已加 live.ps1 的 dot-source')
    # 主循环里调用 Update-Live：插在“弹完了，处理排队中的请求”之前
    if 'Update-Live' not in t:
        anchor2 = '        # 弹完了，处理排队中的请求'
        if anchor2 in t:
            t = t.replace(anchor2,
                          '        # 直播模式：节目单调度\r\n        try { Update-Live } catch { }\r\n\r\n' + anchor2)
            print('main: 已加 Update-Live 调用')
        else:
            print('main: 未找到主循环锚点')
    write(MAIN, t)


def patch_menu():
    t = read(MENU)
    if 'miLive' in t:
        print('menu: 已存在直播菜单项')
        return
    anchor = "$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null\r\n# 菜单最下面显示版本号"
    anchor2 = "$miClear  = $menu.Items.Add('清除记忆…')"
    if anchor2 not in t:
        anchor2 = "$miClear"
        if anchor2 not in t:
            print('menu: 未找到清除记忆锚点')
            return
    add = ("$miLive   = $menu.Items.Add('直播模式：关')\r\n"
           "$miLive.Add_Click({\r\n"
           "    try {\r\n"
           "        if ($script:liveOn) { Stop-Live | Out-Null; $miLive.Text = '直播模式：关' }\r\n"
           "        else { Start-Live | Out-Null; $miLive.Text = '直播模式：开' }\r\n"
           "    } catch { }\r\n"
           "})\r\n")
    t = t.replace(anchor2, add + anchor2, 1)
    print('menu: 已插入「直播模式」菜单项')
    write(MENU, t)


if __name__ == '__main__':
    patch_main()
    patch_menu()
