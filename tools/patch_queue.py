"""一次性补丁：把排队队列改成带类型（chat / music）并按类型分派。

运行：python tools/patch_queue.py
"""
import io
import os

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAT = os.path.join(PKG, 'assets', 'lib', 'chat.ps1')
MAIN = os.path.join(PKG, 'assets', 'fish-pet.ps1')

BLOCK = [
    '        # 弹完了，处理排队中的请求（按类型分派：点歌 / 聊天）',
    '        if ($script:musicQueue.Count -gt 0 -and -not (Test-MusicBusy) -and -not $script:chatBusy) {',
    '            $item = $script:musicQueue[0]',
    '            $script:musicQueue = @($script:musicQueue | Select-Object -Skip 1)',
    "            $kind = 'chat'; $txt = ''",
    '            if ($item -is [string]) { $txt = $item }',
    '            else { $kind = [string]$item.kind; $txt = [string]$item.text }',
    '            if (-not $kind) { $kind = \'chat\' }',
    "            Write-Err ('MUSIC-RESUME ' + $kind + ' ' + $txt)",
    "            if ($kind -eq 'music') { try { Start-Music $txt | Out-Null } catch { } }",
    '            else { try { Start-Chat $txt } catch { } }',
    '        }',
]


def patch_chat():
    t = io.open(CHAT, encoding='utf-8-sig').read()
    old = "            $script:musicQueue = @($script:musicQueue) + @($text)"
    new = ("            $script:musicQueue = @($script:musicQueue) + "
           "@([pscustomobject]@{ kind = 'chat'; text = $text })")
    if old not in t:
        print('chat.ps1: 入队行未找到（可能已改过）')
        return
    t = t.replace(old, new)
    io.open(CHAT, 'w', encoding='utf-8-sig', newline='\r\n').write(t)
    print('chat.ps1: 入队已带类型')


def patch_main():
    lines = io.open(MAIN, encoding='utf-8-sig').read().splitlines()
    start = None
    for i, ln in enumerate(lines):
        if '弹完了，处理排队中的对话' in ln or '弹完了，处理排队中的请求' in ln:
            start = i
            break
    if start is None:
        print('fish-pet.ps1: 未找到 drain 块（可能已改过）')
        return
    end = start
    while end < len(lines) and 'Start-Chat $nextText' not in lines[end] and 'Start-Chat $txt' not in lines[end]:
        end += 1
    close = end
    while close < len(lines) and lines[close].strip() != '}':
        close += 1
    lines[start:close + 1] = BLOCK
    io.open(MAIN, 'w', encoding='utf-8-sig', newline='\r\n').write('\n'.join(lines) + '\n')
    print('fish-pet.ps1: 出队分派已改（替换 %d 行）' % (close - start + 1))


if __name__ == '__main__':
    patch_chat()
    patch_main()
