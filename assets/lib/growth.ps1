# growth.ps1 · 成长系统（科学算法版）
# 设计原则：
#   1) 每天有经验上限（防刷级）：单日最多 20 点
#   2) 多互动覆盖：聊天/夸奖/喂食/讲故事/陪伴各有上限，光聊天长不快
#   3) 连续陪伴有加成：每天首次互动 +2，连续 7 天 +10
#   4) 长期导向：到"家人"需约 2000 点（按每天 15 点约 4 个月）
#   5) 等级 = 阶段序号（Lv1~Lv5）

$script:growth = $null
$script:growthPath = Join-Path $DataDir 'growth.json'

# 阶段：经验下限 / 名称 / 给 LLM 的语气描述
$script:GROWTH_STAGES = @(
    @{ exp = 0;    name = '初识'; desc = '刚认识主人不久，客气、好奇、话不多，偶尔怯生生的' },
    @{ exp = 200;  name = '熟悉'; desc = '和主人熟了，自然、调皮，会接话、会开玩笑' },
    @{ exp = 800;  name = '亲密'; desc = '和主人很亲，爱撒娇、护着主人，会主动关心' },
    @{ exp = 2500;  name = '知心'; desc = '懂主人了，有默契，能看出主人心情，说话贴心' },
    @{ exp = 5000; name = '家人'; desc = '像家人一样，无话不谈，亲近自然，会念叨主人' }
)

# 每日上限（防刷级）：总上限 + 各来源上限
$script:GROWTH_DAILY_CAP = 12
$script:GROWTH_SOURCE_CAP = @{ chat = 5; praise = 6; feed = 6; story = 4; company = 6 }

function Load-Growth {
    if ($null -ne $script:growth) { return }
    $script:growth = @{
        exp = 0
        dayExp = 0
        dayKey = (Get-Date).ToString('yyyy-MM-dd')
        streak = 0
        lastActive = ''
        lastTick = (Get-Date).ToString('o')
    }
    try {
        if (Test-Path $script:growthPath) {
            $obj = [IO.File]::ReadAllText($script:growthPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($obj) {
                if ($null -ne $obj.exp) { $script:growth.exp = [int]$obj.exp }
                if ($null -ne $obj.dayExp) { $script:growth.dayExp = [int]$obj.dayExp }
                if ($obj.dayKey) { $script:growth.dayKey = [string]$obj.dayKey }
                if ($null -ne $obj.streak) { $script:growth.streak = [int]$obj.streak }
                if ($obj.lastActive) { $script:growth.lastActive = [string]$obj.lastActive }
                if ($obj.lastTick) { $script:growth.lastTick = [string]$obj.lastTick }
            }
        }
    } catch { }
    # 跨天重置单日经验
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($script:growth.dayKey -ne $today) {
        $script:growth.dayExp = 0
        $script:growth.dayKey = $today
    }
}

function Save-Growth {
    try {
        $json = $script:growth | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($script:growthPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Get-GrowthStage {
    Load-Growth
    $exp = [int]$script:growth.exp
    $idx = 0
    for ($i = 0; $i -lt $script:GROWTH_STAGES.Count; $i++) {
        if ($exp -ge [int]$script:GROWTH_STAGES[$i].exp) { $idx = $i }
    }
    $nextExp = 0
    if ($idx + 1 -lt $script:GROWTH_STAGES.Count) { $nextExp = [int]$script:GROWTH_STAGES[$idx + 1].exp }
    return @{
        index = $idx
        level = $idx + 1
        name = [string]$script:GROWTH_STAGES[$idx].name
        desc = [string]$script:GROWTH_STAGES[$idx].desc
        exp = $exp
        nextExp = $nextExp
    }
}

# 加经验（按来源 + 单日上限 + 连续陪伴加成）
function Add-Growth([int]$amount, [string]$reason) {
    try {
        if ($amount -le 0) { return }
        Load-Growth
        $before = Get-GrowthStage
        $today = (Get-Date).ToString('yyyy-MM-dd')

        # 连续互动：今天第一次互动，算连续天数
        if ($script:growth.lastActive -ne $today) {
            $yesterday = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
            if ($script:growth.lastActive -eq $yesterday) { $script:growth.streak = [int]$script:growth.streak + 1 }
            else { $script:growth.streak = 1 }
            $script:growth.lastActive = $today
            # 首次互动奖励
            $amount += 1
            # 连续 7 天奖励
            if ($script:growth.streak -ge 7 -and ($script:growth.streak % 7) -eq 0) { $amount += 5 }
        }

        # 单日总上限
        $room = [int]$script:GROWTH_DAILY_CAP - [int]$script:growth.dayExp
        if ($room -le 0) {
            Save-Growth
            Write-Err ('GROWTH-CAP-DAY ' + $reason + ' exp=' + $script:growth.exp)
            return
        }
        if ($amount -gt $room) { $amount = $room }

        # 来源单日上限（按来源类型粗分）
        $srcCap = 3
        try { if ($script:GROWTH_SOURCE_CAP.ContainsKey($reason)) { $srcCap = [int]$script:GROWTH_SOURCE_CAP[$reason] } } catch { }
        $srcKey = 'src_' + $reason
        if ($null -eq $script:growth[$srcKey]) { $script:growth[$srcKey] = 0 }
        # 来源跨天重置
        if ($script:growth['srcDay'] -ne $today) {
            foreach ($k in @($script:growth.Keys)) { if ([string]$k -like 'src_*') { $script:growth.Remove($k) } }
            $script:growth['srcDay'] = $today
        }
        $srcRoom = $srcCap - [int]$script:growth[$srcKey]
        if ($srcRoom -le 0) {
            Save-Growth
            Write-Err ('GROWTH-CAP-SRC ' + $reason + ' exp=' + $script:growth.exp)
            return
        }
        if ($amount -gt $srcRoom) { $amount = $srcRoom }

        $script:growth[$srcKey] = [int]$script:growth[$srcKey] + $amount
        $script:growth.dayExp = [int]$script:growth.dayExp + $amount
        $script:growth.exp = [int]$script:growth.exp + $amount
        Save-Growth

        $after = Get-GrowthStage
        if ($after.index -gt $before.index) {
            $msg = '主人，本鲸又长大一点啦——现在是「' + $after.name + '」阶段。'
            Show-Bubble $msg
            try { Speak-Text $msg } catch { }
            Write-Err ('GROWTH-UP ' + $before.name + ' -> ' + $after.name + ' exp=' + $script:growth.exp)
        } else {
            Write-Err ('GROWTH +' + $amount + ' ' + $reason + ' exp=' + $script:growth.exp + ' day=' + $script:growth.dayExp)
        }
    } catch { }
}

# 陪伴时间：每满 1 小时 +1（算 company 来源，受每日上限）
function Invoke-GrowthTick {
    try {
        Load-Growth
        $last = $null
        try { $last = [datetime]::Parse($script:growth.lastTick) } catch { }
        if ($null -eq $last) {
            $script:growth.lastTick = (Get-Date).ToString('o')
            Save-Growth
            return
        }
        if (((Get-Date) - $last).TotalHours -ge 1) {
            $hours = [Math]::Min(8, [int][Math]::Floor(((Get-Date) - $last).TotalHours))
            $script:growth.lastTick = (Get-Date).ToString('o')
            Save-Growth
            Add-Growth $hours 'company'
        }
    } catch { }
}

# 菜单/冒泡显示：成长：Lv3 亲密（450/900）
function Get-GrowthText {
    $st = Get-GrowthStage
    $lv = 'Lv' + [int]$st.level
    if ($st.nextExp -gt 0) {
        return '成长：' + $lv + ' ' + $st.name + '（' + $st.exp + '/' + $st.nextExp + '）'
    }
    return '成长：' + $lv + ' ' + $st.name + '（满级）'
}
