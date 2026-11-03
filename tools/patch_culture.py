"""把 culture.ps1 接入：dot-source + 菜单 + 语音意图。

运行：python tools/patch_culture.py
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
    if 'lib\\culture.ps1' in t:
        print('main: 已接入')
    else:
        anchor = ". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\story.ps1')"
        if anchor in t:
            t = t.replace(
                anchor,
                anchor + "\r\n\r\n# 文化气（讲典故 / 对名句），实现在 lib\\culture.ps1\r\n"
                        ". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\culture.ps1')")
            print('main: 已加 dot-source（story 之后）')
        else:
            anchor2 = ". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\dsh.ps1')"
            t = t.replace(
                anchor2,
                anchor2 + "\r\n\r\n# 文化气，实现在 lib\\culture.ps1\r\n"
                         ". (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\\culture.ps1')")
            print('main: 已加 dot-source（dsh 之后）')
    # 语音意图：放在音乐意图之前，命中就 break
    if 'CULTURE-INTENT' not in t:
        anchor3 = "                    if ($text -match '弹|演奏|唱首|唱个|来首曲子|music|play') {"
        if anchor3 in t:
            block = (
                "                    # 文化气：讲典故 / 对名句\n"
                "                    if ($text -match '典故|讲个故事里的事|说说典故') {\n"
                "                        Invoke-CultureAllusion | Out-Null\n"
                "                        Write-Err 'CULTURE-INTENT allusion'\n"
                "                        break\n"
                "                    }\n"
                "                    if ($text -match '对联|对个对子|出个上联') {\n"
                "                        Invoke-CultureCouplet | Out-Null\n"
                "                        Write-Err 'CULTURE-INTENT couplet'\n"
                "                        break\n"
                "                    }\n"
            )
            t = t.replace(anchor3, block + anchor3, 1)
            print('main: 已加语音意图')
        else:
            print('main: 未找到意图锚点')
    write(MAIN, t)


def patch_menu():
    t = read(MENU)
    if 'miCulture' in t:
        print('menu: 已存在')
        return
    anchor = "$miLive   = $menu.Items.Add('直播模式：关')"
    add = (
        "$miCulture = New-Object System.Windows.Forms.ToolStripMenuItem('文化气')\n"
        "$menu.Items.Add($miCulture) | Out-Null\n"
        "$miCulAllusion = $miCulture.DropDownItems.Add('讲个典故')\n"
        "$miCulAllusion.Add_Click({ try { Invoke-CultureAllusion | Out-Null } catch { } })\n"
        "$miCulCouplet = $miCulture.DropDownItems.Add('出个对联')\n"
        "$miCulCouplet.Add_Click({ try { Invoke-CultureCouplet | Out-Null } catch { } })\n"
    )
    if anchor in t:
        t = t.replace(anchor, add + anchor, 1)
        print('menu: 已插入「文化气」子菜单（直播项前）')
    else:
        anchor2 = "$miClear"
        if anchor2 in t:
            t = t.replace(anchor2, add + anchor2, 1)
            print('menu: 已插入「文化气」子菜单（清除记忆前）')
        else:
            print('menu: 未找到锚点')
            return
    write(MENU, t)


if __name__ == '__main__':
    patch_main()
    patch_menu()
