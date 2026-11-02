# ============================================================
# language.ps1 — 菜单与界面语言
# 依赖声明（自动生成，勿手改）：
#   主脚本提供: Show-Bubble, Write-Err
#   $script 变量: autoOn, cfg, chatOn, langItemMap, langItemsFresh, langMode, paused, speakOn, ttsVoice, uiItemMap, uiLang, voiceItemMap
#   调用其他模块: Speak-Text() → speech.ps1
# ============================================================

# language.ps1 · 右键菜单语言 / 界面语言 / 音色切换（从主脚本拆出）

# 右键菜单文字随语言切换（中文 / English）
function Set-MenuItemText($item, [string]$text) {
    try { if ($null -ne $item) { $item.Text = $text } } catch { }
}
function Update-MenuLang {
    try {
        $en = ([string]$script:uiLang -eq 'en')
        if ($en) {
            Set-MenuItemText $miFeed 'Feed me'
            Set-MenuItemText $miType 'Type a message'
            Set-MenuItemText $miVoice $(if ($script:speakOn) { 'Voice reading: on' } else { 'Voice reading: off' })
            Set-MenuItemText $miVoiceSet 'Change voice'
            Set-MenuItemText $miChatLang 'Chat language'
            Set-MenuItemText $miUiLang 'UI language'
            try { $script:langItemMap['zh'].Text = 'Chinese'; $script:langItemMap['en'].Text = 'English'; $script:langItemMap['auto'].Text = 'Auto' } catch { }
            try { $script:uiItemMap['zh'].Text = 'Chinese'; $script:uiItemMap['en'].Text = 'English' } catch { }
            Set-MenuItemText $miWake $(if ($script:autoOn) { 'Voice standby: on' } else { 'Voice standby: off' })
            Set-MenuItemText $miChat $(if ($script:chatOn) { 'Voice chat: on' } else { 'Voice chat: off' })
            Set-MenuItemText $miPause $(if ($script:paused) { 'Resume' } else { 'Rest a while' })
            Set-MenuItemText $miHome 'Back to corner'
            Set-MenuItemText $miBigger 'Grow bigger'
            Set-MenuItemText $miSmall 'Shrink'
            Set-MenuItemText $miBriefing $(if ($script:cfg.briefing.enabled) { 'Daily briefing: on' } else { 'Daily briefing: off' })
            Set-MenuItemText $miBriefNow 'Brief me now'
            Set-MenuItemText $miBriefRecent 'Recent briefings'
            Set-MenuItemText $miRemind 'Add a reminder...'
            Set-MenuItemText $miRemindList 'Reminders...'
            Set-MenuItemText $miClear 'Clear memory...'
            Set-MenuItemText $miQuit 'Swim away (exit)'
        } else {
            Set-MenuItemText $miFeed '喂它一口'
            Set-MenuItemText $miType '打字说两句'
            Set-MenuItemText $miVoice $(if ($script:speakOn) { '语音朗读：开' } else { '语音朗读：关' })
            Set-MenuItemText $miVoiceSet '换个声音'
            Set-MenuItemText $miChatLang '聊天语言'
            Set-MenuItemText $miUiLang '界面语言'
            try { $script:langItemMap['zh'].Text = '中文'; $script:langItemMap['en'].Text = 'English'; $script:langItemMap['auto'].Text = '自动模式' } catch { }
            try { $script:uiItemMap['zh'].Text = '中文'; $script:uiItemMap['en'].Text = 'English' } catch { }
            Set-MenuItemText $miWake $(if ($script:autoOn) { '语音待命：开' } else { '语音待命：关' })
            Set-MenuItemText $miChat $(if ($script:chatOn) { '语音聊天：开' } else { '语音聊天：关（省 token）' })
            Set-MenuItemText $miPause $(if ($script:paused) { '继续游' } else { '停下歇会儿' })
            Set-MenuItemText $miHome '回到右下角'
            Set-MenuItemText $miBigger '长大一点'
            Set-MenuItemText $miSmall '变小一点'
            Set-MenuItemText $miBriefing $(if ($script:cfg.briefing.enabled) { '今日简报：开' } else { '今日简报：关' })
            Set-MenuItemText $miBriefNow '现在简报一次'
            Set-MenuItemText $miBriefRecent '最近简报'
            Set-MenuItemText $miRemind '加个提醒…'
            Set-MenuItemText $miRemindList '提醒清单…'
            Set-MenuItemText $miClear '清除记忆…'
            Set-MenuItemText $miQuit '让它游走（退出）'
        }
        Set-MenuItemText $miBalance $(if ($en) { 'Balance: --' } else { '余额：--' })
        try { if ($menu) { $menu.Refresh() } } catch { }
        Write-Err ('LANG-UI ui=' + [string]$script:uiLang + ' chat=' + [string]$script:langMode + ' feed=' + $miFeed.Text + ' pause=' + $miPause.Text + ' balance=' + $miBalance.Text)
    } catch { }
}

# 切换朗读音色（立即生效并写入 config.json）
# 切换中英文聊天模式（立即生效并写入 config.json）
function Set-LangMode([string]$mode, [string]$label) {
    Write-Err ('LANG-SET mode=' + $mode + ' label=' + $label)
    try {
        $script:langMode = $mode
        try {
            $cfg = Join-Path $DataDir 'config.json'
            if (Test-Path $cfg) {
                $j = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.persona) { $j | Add-Member -NotePropertyName persona -NotePropertyValue ([ordered]@{ lang = $mode }) }
                elseif ($j.persona.PSObject.Properties.Name -notcontains 'lang') { $j.persona | Add-Member -NotePropertyName lang -NotePropertyValue $mode }
                else { $j.persona.lang = $mode }
                [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        # 更新子菜单的勾选状态（同时只勾一个）
        try {
            if ($script:langItemMap) {
                foreach ($k in @($script:langItemMap.Keys)) { $script:langItemMap[$k].Checked = ([string]$k -eq [string]$mode) }
                $script:langItemsFresh = $true
            }
        } catch { }
        if ($mode -eq 'en') { Show-Bubble 'Language: English' }
        elseif ($mode -eq 'auto') { Show-Bubble '语言：自动模式' }
        else { Show-Bubble ('语言：' + $label) }
    } catch { Write-Err 'LANG-SET-ERR' }
}

# 切换界面语言（只影响右键菜单文字，不动聊天语言）
function Set-UiLang([string]$mode, [string]$label) {
    try {
        $script:uiLang = $mode
        try {
            $cfg = Join-Path $DataDir 'config.json'
            if (Test-Path $cfg) {
                $j = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.ui) { $j | Add-Member -NotePropertyName ui -NotePropertyValue ([ordered]@{ lang = $mode }) }
                elseif ($j.ui.PSObject.Properties.Name -notcontains 'lang') { $j.ui | Add-Member -NotePropertyName lang -NotePropertyValue $mode }
                else { $j.ui.lang = $mode }
                [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        try {
            if ($script:uiItemMap) {
                foreach ($k in @($script:uiItemMap.Keys)) { $script:uiItemMap[$k].Checked = ([string]$k -eq [string]$mode) }
            }
        } catch { }
        Update-MenuLang
        Write-Err ('UI-LANG mode=' + $mode)
    } catch { }
}

# 启动时按当前界面语言设置一遍菜单文字
try { Update-MenuLang } catch { }

function Set-TtsVoice([string]$voice, [string]$label) {
    try {
        $script:ttsVoice = $voice
        try {
            $cfg = Join-Path $DataDir 'config.json'
            if (Test-Path $cfg) {
                $j = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.tts) { $j | Add-Member -NotePropertyName tts -NotePropertyValue ([ordered]@{ engine = 'edge'; voice = $voice; rate = '+12%'; pitch = '+10Hz' }) }
                $j.tts.voice = $voice
                [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        Show-Bubble ('声音换成：' + $label)
        try {
            if ($script:voiceItemMap) {
                foreach ($k in @($script:voiceItemMap.Keys)) { $script:voiceItemMap[$k].Checked = ([string]$k -eq [string]$voice) }
            }
        } catch { }
        Speak-Text ('主人你好呀，我是大肥鱼，现在用的是' + $label + '的声音')
    } catch { Write-Err 'VOICE-SET-ERR' }
}
