# fishfood.ps1 · 鱼粮账本：统计 Token 消耗、估算花费，让鱼心疼鱼粮
# 依赖主脚本：$DataDir / Show-Bubble / Speak-Text / Write-Err / $script:cfg

$script:fishfood = $null
$script:fishfoodPath = Join-Path $DataDir 'fishfood.json'

# 估算单价（元/百万 token，按公开价粗略估算，仅作参考）
$script:FF_PRICE_IN = 0.5
$script:FF_PRICE_OUT = 2.0

function Load-FishFood {
    if ($null -ne $script:fishfood) { return }
    $script:fishfood = @{
        date = (Get-Date).ToString('yyyy-MM-dd')
        chatTokens = 0
        storyTokens = 0
        month = (Get-Date).ToString('yyyy-MM')
        monthTokens = 0
    }
    try {
        if (Test-Path $script:fishfoodPath) {
            $obj = [IO.File]::ReadAllText($script:fishfoodPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($obj) {
                if ($obj.date) { $script:fishfood.date = [string]$obj.date }
                if ($null -ne $obj.chatTokens) { $script:fishfood.chatTokens = [int]$obj.chatTokens }
                if ($null -ne $obj.storyTokens) { $script:fishfood.storyTokens = [int]$obj.storyTokens }
                if ($obj.month) { $script:fishfood.month = [string]$obj.month }
                if ($null -ne $obj.monthTokens) { $script:fishfood.monthTokens = [int]$obj.monthTokens }
            }
        }
    } catch { }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $thisMonth = (Get-Date).ToString('yyyy-MM')
    if ($script:fishfood.date -ne $today) {
        $script:fishfood.date = $today
        $script:fishfood.chatTokens = 0
        $script:fishfood.storyTokens = 0
    }
    if ($script:fishfood.month -ne $thisMonth) {
        $script:fishfood.month = $thisMonth
        $script:fishfood.monthTokens = 0
    }
}

function Save-FishFood {
    try {
        $json = $script:fishfood | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($script:fishfoodPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

# 记录一次 API 用量（chat/story）
function Add-FishFoodTokens([string]$kind, [int]$inTokens, [int]$outTokens) {
    try {
        if ($inTokens -le 0 -and $outTokens -le 0) { return }
        Load-FishFood
        $total = $inTokens + $outTokens
        if ($kind -eq 'story') { $script:fishfood.storyTokens = [int]$script:fishfood.storyTokens + $total }
        else { $script:fishfood.chatTokens = [int]$script:fishfood.chatTokens + $total }
        $script:fishfood.monthTokens = [int]$script:fishfood.monthTokens + $total
        Save-FishFood
        Write-Err ('FISHFOOD +' + $total + ' ' + $kind + ' today=' + ($script:fishfood.chatTokens + $script:fishfood.storyTokens))
    } catch { }
}

# 今日/本月花费估算
function Get-FishFoodCost([int]$inTokens, [int]$outTokens) {
    return [Math]::Round(($inTokens / 1000000.0) * $script:FF_PRICE_IN + ($outTokens / 1000000.0) * $script:FF_PRICE_OUT, 4)
}

# 账本文本（冒泡/菜单用）
function Get-FishFoodText([string]$scope) {
    Load-FishFood
    $todayTotal = [int]$script:fishfood.chatTokens + [int]$script:fishfood.storyTokens
    if ($scope -eq 'month') {
        $cost = Get-FishFoodCost ([int]$script:fishfood.monthTokens * 0.7) ([int]$script:fishfood.monthTokens * 0.3)
        return '这个月本鱼吃了 ' + $script:fishfood.monthTokens + ' tokens，约 ¥' + $cost + '。'
    }
    $cost = Get-FishFoodCost ([int]$script:fishfood.chatTokens) ([int]$script:fishfood.storyTokens)
    return '今天本鱼吃了 ' + $todayTotal + ' tokens（聊天 ' + $script:fishfood.chatTokens + '、说书 ' + $script:fishfood.storyTokens + '），约 ¥' + $cost + '。'
}

# 报账（菜单/语音触发）
function Show-FishFood {
    $text = Get-FishFoodText 'today'
    Show-Bubble $text
    try { Speak-Text $text } catch { }
    Write-Err ('FISHFOOD-REPORT ' + $text)
}

# 鱼心疼鱼粮：按消耗给一句话（聊天/故事时偶尔说）
function Get-FishFoodMood {
    Load-FishFood
    $todayTotal = [int]$script:fishfood.chatTokens + [int]$script:fishfood.storyTokens
    if ($todayTotal -ge 50000) { return '（小声嘀咕）主人，今天鱼粮吃得多，少吃点吧，本鱼心疼……' }
    if ($todayTotal -ge 20000) { return '（悄悄说）鱼粮来之不易，少吃点，本鱼记住啦。' }
    return ''
}
