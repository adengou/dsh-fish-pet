# ============================================================
# menu.ps1 — 右键菜单构建
# 依赖声明（自动生成，勿手改）：见 tools\add-module-headers.py 输出
# ============================================================

# ---------- 菜单 ----------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miFeed   = $menu.Items.Add('喂它一口')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miMusic  = New-Object System.Windows.Forms.ToolStripMenuItem('弹首曲子')
$menu.Items.Add($miMusic) | Out-Null
                    # 子项在脚本末尾（函数定义齐全之后）一次性建好，避免展开时崩溃
$miMusicStop = $menu.Items.Add('停止弹奏')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miMusicStop.Add_Click({ try { Stop-Music | Out-Null } catch { } })
$miType = $menu.Items.Add('打字说两句')
$miVoice  = $menu.Items.Add('语音朗读：开')
$miVoiceSet = New-Object System.Windows.Forms.ToolStripMenuItem('换个声音')
$menu.Items.Add($miVoiceSet) | Out-Null
$miChatLang = New-Object System.Windows.Forms.ToolStripMenuItem('聊天语言')
$langChoices = @(
    @('zh', '中文'),
    @('en', 'English'),
    @('auto', '自动模式')
)
$script:langItemMap = @{}
foreach ($lc in $langChoices) {
    $itL = New-Object System.Windows.Forms.ToolStripMenuItem($lc[1])
    $itL.Tag = $lc[0]
    $itL.CheckOnClick = $false
    $itL.Checked = ([string]$script:langMode -eq [string]$lc[0])
    $itL.Add_Click({
        param($s, $e)
        Set-LangMode ([string]$s.Tag) ([string]$s.Text)
    })
    $miChatLang.DropDownItems.Add($itL) | Out-Null
    $script:langItemMap[[string]$lc[0]] = $itL
}
$menu.Items.Add($miChatLang) | Out-Null

# 界面语言：只影响右键菜单文字，不动聊天语言
$miUiLang = New-Object System.Windows.Forms.ToolStripMenuItem('界面语言')
$uiChoices = @(
    @('zh', '中文'),
    @('en', 'English')
)
$script:uiItemMap = @{}
foreach ($uc in $uiChoices) {
    $itU = New-Object System.Windows.Forms.ToolStripMenuItem($uc[1])
    $itU.Tag = $uc[0]
    $itU.CheckOnClick = $false
    $itU.Checked = ([string]$script:uiLang -eq [string]$uc[0])
    $itU.Add_Click({
        param($s, $e)
        Set-UiLang ([string]$s.Tag) ([string]$s.Text)
    })
    $miUiLang.DropDownItems.Add($itU) | Out-Null
    $script:uiItemMap[[string]$uc[0]] = $itU
}
$menu.Items.Add($miUiLang) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$voiceChoices = @(
    @('zh-CN-XiaoyiNeural', '活泼少女·晓伊'),
    @('zh-CN-XiaoxiaoNeural', '温柔姐姐·晓晓'),
    @('zh-CN-liaoning-XiaobeiNeural', '东北话·小北'),
    @('zh-CN-shaanxi-XiaoniNeural', '陕西话·小妮'),
    @('zh-CN-YunxiNeural', '阳光男声·云希'),
    @('zh-CN-YunxiaNeural', '可爱男声·云夏')
)
$script:voiceItemMap = @{}
foreach ($vc in $voiceChoices) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem(($vc[1] + '（' + $vc[0] + '）'))
    $it.Tag = $vc[0]
    $it.CheckOnClick = $false
    $it.Checked = ([string]$script:ttsVoice -eq [string]$vc[0])
    $it.Add_Click({ 
        param($s, $e)
        $script:voicePickTag = [string]$s.Tag
        $script:voicePickLabel = [string]$s.Text
        Set-TtsVoice $script:voicePickTag $script:voicePickLabel
    })
    $miVoiceSet.DropDownItems.Add($it) | Out-Null
    $script:voiceItemMap[[string]$vc[0]] = $it
}
$miWake   = $menu.Items.Add('语音待命：开')
$miChat   = $menu.Items.Add('语音聊天：开')
$miBalance = $menu.Items.Add('余额：--')
$miPause  = $menu.Items.Add('停下歇会儿')
$miHome   = $menu.Items.Add('回到右下角')
$miBigger = $menu.Items.Add('长大一点')
$miSmall  = $menu.Items.Add('变小一点')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miBriefing = $menu.Items.Add('今日简报：开')
$miBriefNow = $menu.Items.Add('现在简报一次')
$miBriefRecent = New-Object System.Windows.Forms.ToolStripMenuItem('最近简报')
$menu.Items.Add($miBriefRecent) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miDictate = $menu.Items.Add('口述公文：开始')
$miDsh = $menu.Items.Add('交给 DSH 助手…')
$miRemind = $menu.Items.Add('加个提醒…')
$miRemindList = $menu.Items.Add('提醒清单…')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miCulture = New-Object System.Windows.Forms.ToolStripMenuItem('文化气')
$menu.Items.Add($miCulture) | Out-Null
$miCulStory = $miCulture.DropDownItems.Add('讲个故事')
$miCulStory.Add_Click({ try { Start-Story '' | Out-Null } catch { } })
$miCulAllusion = $miCulture.DropDownItems.Add('讲个典故')
$miCulAllusion.Add_Click({ try { Invoke-CultureAllusion | Out-Null } catch { } })
$miCulCouplet = $miCulture.DropDownItems.Add('出个对联')
$miCulCouplet.Add_Click({ try { Invoke-CultureCouplet | Out-Null } catch { } })
$miClear  = $menu.Items.Add('清除记忆…')
$miQuit   = $menu.Items.Add('让它游走（退出）')

# 菜单最下面显示版本号（灰色不可点）
$script:petVersion = 'dev'
try {
    # 菜单在 lib\ 下，package.json 在插件根目录：逐级往上找
    $cands = @()
    $d1 = Split-Path -Parent $PSScriptRoot                 # assets
    $d2 = if ($d1) { Split-Path -Parent $d1 } else { '' }  # 插件根
    if ($d1) { $cands += (Join-Path $d1 'package.json') }
    if ($d2) { $cands += (Join-Path $d2 'package.json') }
    foreach ($c in $cands) {
        if ($c -and (Test-Path $c)) {
            $script:petVersion = [string](Get-Content $c -Raw -Encoding UTF8 | ConvertFrom-Json).version
            break
        }
    }
} catch { }
if (-not $script:petVersion) { $script:petVersion = 'dev' }
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miFishFood = $menu.Items.Add('鱼粮账本')
$miGrowth = $menu.Items.Add('成长：--')
$miGrowth.Enabled = $false
$miVersion = $menu.Items.Add('版本：v' + $script:petVersion)
$miVersion.Enabled = $false
