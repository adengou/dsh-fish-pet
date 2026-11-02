# briefing.ps1 · 每日简报 / 文件拖拽 / 语音备忘 / 口述公文（从主脚本拆出）


# ---------- 今日简报（天气 + 今日提醒，交给鱼自己组织） ----------
function Get-WeatherLine {
    $code = '101301301'
    try { if ($script:cfg.briefing.cityCode) { $code = [string]$script:cfg.briefing.cityCode } } catch { }
    try {
        $r = Invoke-RestMethod -Uri ('http://t.weather.itboy.net/api/weather/city/' + $code) -TimeoutSec 10
        $f = $r.data.forecast[0]
        $line = '今天' + $f.high + '/' + $f.low + '，' + $f.type + '，' + $f.fx + $f.fl
        if ($f.notice) { $line = $line + '。' + $f.notice }
        return $line
    } catch { }
    try {
        $r2 = Invoke-RestMethod -Uri 'https://api.open-meteo.com/v1/forecast?latitude=21.4733&longitude=109.1193&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=Asia%2FShanghai&forecast_days=1' -TimeoutSec 12
        return ('今天 ' + $r2.daily.temperature_2m_min[0] + '~' + $r2.daily.temperature_2m_max[0] + ' 度，降水概率 ' + $r2.daily.precipitation_probability_max[0] + '%')
    } catch { }
    return ''
}

function Get-TodayNotes {
    $lines = @()
    try {
        $arr = @(Load-Notes)
        $today = (Get-Date).ToString('yyyy-MM-dd')
        foreach ($n in $arr) {
            $dueStr = [string]$n.due
            if (-not $dueStr) { continue }
            try {
                $d = [datetime]::Parse($dueStr)
                if ($d.ToString('yyyy-MM-dd') -eq $today) { $lines += [string]$n.text }
            } catch { }
        }
    } catch { }
    return $lines
}

function Get-SessionDigest {
    $lines = @()
    try {
        $digestScript = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'session-digest.mjs'
        if (-not (Test-Path $digestScript)) { return $lines }
        $json = & node $digestScript 'today' 2>$null
        $jsonText = (@($json) -join '')
        if ($jsonText) {
            $parsed = $null
            try { $parsed = ConvertFrom-Json -InputObject $jsonText } catch { $parsed = $null }
            $arr = @()
            if ($parsed) { $arr = @($parsed) }
            foreach ($s in $arr) {
                $t = [string]$s.title
                $ms = ''
                try { if ($s.msgs) { $ms = (@($s.msgs | Where-Object { $_ }) -join '；') } } catch { }
                $line = $t
                if ($ms) { $line = $line + '（最近做的事：' + $ms + '）' }
                if ($line) { $lines += $line }
            }
            $lines = @($lines | Select-Object -Unique)
        }
    } catch { Write-Err ('DIGEST-ERR ' + $_.Exception.Message) }
    return $lines
}

function Invoke-BriefingLlm([string]$material) {
    try {
        $key = Get-ApiKey
        if (-not $key) { return $null }
        if ($null -eq $script:briefHttp) {
            $script:briefHttp = New-Object System.Net.Http.HttpClient
            $script:briefHttp.Timeout = [TimeSpan]::FromSeconds(25)
        }
        $sys = '你是桌面宠物"大肥鱼"，向主人播报今日简报：用两三句话（80字以内），先概括今天在 DSH 里做的主要工作（挑 2~4 件主要的说，从会话标题和最近做的事归纳，别漏掉当前窗口做的事），再带一句天气或待办。语气俏皮、微微傲娇，称呼"主人"，不要表情符号，不要罗列格式。'
        $body = @{ model = 'deepseek-flash'; messages = @(@{ role = 'system'; content = $sys }, @{ role = 'user'; content = $material }); max_tokens = 220; temperature = 0.8; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
        $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $req.Content = $content
        $resp = $script:briefHttp.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $reply = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        if ($reply) { return $reply.Trim() }
    } catch { Write-Err ('BRIEF-LLM-ERR ' + $_.Exception.Message) }
    return $null
}

# ---------- 文件拖拽：拖到鱼身上，读摘要 ----------
function Invoke-SummaryLlm([string]$fileName, [string]$text) {
    try {
        $key = Get-ApiKey
        if (-not $key) { return $null }
        if ($null -eq $script:sumHttp) {
            $script:sumHttp = New-Object System.Net.Http.HttpClient
            $script:sumHttp.Timeout = [TimeSpan]::FromSeconds(45)
        }
        $sys = '用一两句话（60字内）向主人概括这份文件的主要内容，中文口语化，不要报文件名和字数。'
        $body = @{ model = 'deepseek-flash'; messages = @(@{ role = 'system'; content = $sys }, @{ role = 'user'; content = ('文件名：' + $fileName + "`n正文：`n" + $text) }); max_tokens = 150; temperature = 0.3; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
        $c = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $req.Content = $c
        $resp = $script:sumHttp.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $reply = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        if ($reply) { return $reply.Trim() }
    } catch { Write-Err ('SUM-ERR ' + $_.Exception.Message) }
    return $null
}

function Handle-DroppedFile([string]$path) {
    try {
        if (-not (Test-Path $path)) { return }
        $ext = [IO.Path]::GetExtension($path).ToLower()
        $name = [IO.Path]::GetFileName($path)
        Show-Bubble ('看看：' + $name)
        if ($ext -in @('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp')) {
            $ans = Invoke-VisionLlm $path $name
            if (-not $ans) { $ans = '这张图我看不太清' }
            Show-Bubble $ans
            Speak-Text $ans
            return
        }
        $py = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'read_file.py'
        if (-not (Test-Path $py)) { Show-Bubble '缺读取脚本'; return }
        $json = & python $py $path 2>$null
        $obj = $null
        try { $obj = $json | ConvertFrom-Json } catch { }
        if (-not $obj -or -not $obj.ok -or -not $obj.text) { Show-Bubble ('这个文件我读不出内容：' + $name); return }
        $text = [string]$obj.text
        if ($text.Length -gt 8000) { $text = $text.Substring(0, 8000) }
        $ans = Invoke-SummaryLlm $name $text
        if (-not $ans) { $ans = '这个文件我读不出重点' }
        Show-Bubble $ans
        Speak-Text $ans
        Write-Err ('DROP-RECV name=' + $name + ' chars=' + $text.Length)
    } catch { Write-Err ('DROP-FILE-ERR ' + $_.Exception.Message) }
}

# ---------- 语音备忘：从口述里解析时间并建提醒 ----------
function Create-ReminderFromText([string]$text) {
    try {
        $key = Get-ApiKey
        if (-not $key) { Show-Bubble '没有密钥，记不了提醒'; return }
        if ($null -eq $script:remHttp) {
            $script:remHttp = New-Object System.Net.Http.HttpClient
            $script:remHttp.Timeout = [TimeSpan]::FromSeconds(30)
        }
        $nowStr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss dddd')
        $sys = '把主人的话解析成一条提醒。当前时间：' + $nowStr + '。输出 JSON：{"due":"YYYY-MM-DDTHH:mm:ss","text":"提醒内容"}。due 是提醒时间（按当前时间推算，例如"下午三点"=今天15:00，已过则明天15:00）；话里没有明确时间时 due 留空字符串。text 是简短提醒内容（20字内）。只输出 JSON。'
        $body = @{ model = 'deepseek-flash'; messages = @(@{ role = 'system'; content = $sys }, @{ role = 'user'; content = $text }); max_tokens = 120; temperature = 0.2; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
        $c = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $req.Content = $c
        $resp = $script:remHttp.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $reply = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        if (-not $reply) { return }
        $clean = $reply -replace '(?s)^\s*```(?:json)?\s*', '' -replace '(?s)\s*```\s*$', ''
        $obj = $null
        try { $obj = $clean | ConvertFrom-Json } catch { }
        if (-not $obj) { return }
        $due = [string]$obj.due
        $what = [string]$obj.text
        if (-not $what) { $what = $text }
        if (-not $due) {
            Show-Bubble ('记下了：' + $what + '（没说时间）')
            Speak-Text ('记下了，' + $what)
            return
        }
        $arr = @(Load-Notes)
        $arr += [ordered]@{ text = $what; due = $due; fired = $false }
        [IO.File]::WriteAllText($script:notesPath, (ConvertTo-Json -InputObject @($arr) -Depth 4), (New-Object Text.UTF8Encoding($false)))
        $dt = $null
        try { $dt = [datetime]::Parse($due) } catch { }
        $when = if ($dt) { $dt.ToString('MM月dd日 HH:mm') } else { $due }
        Show-Bubble ('好的，' + $when + '提醒你：' + $what)
        Speak-Text ('好的，' + $when + '提醒你：' + $what)
        Write-Err ('REMIND-ADD due=' + $due + ' text=' + $what)
    } catch { Write-Err ('REMIND-ERR ' + $_.Exception.Message) }
}

# ---------- 口述公文：把口述整理成公文并导出 Word ----------
function Generate-Gongwen([string]$raw) {
    try {
        $key = Get-ApiKey
        if (-not $key) { Show-Bubble '没有 DeepSeek 密钥，写不了'; return }
        if ($null -eq $script:gongwenHttp) {
            $script:gongwenHttp = New-Object System.Net.Http.HttpClient
            $script:gongwenHttp.Timeout = [TimeSpan]::FromSeconds(60)
        }
        $sys = '你是机关公文写作助手。把主人的口述**改写成**一份规范中文公文，不是复述：1) 起一个准确、可用的标题；2) 提炼口述要点，按逻辑分层（一、二、三……），每层先写主旨句再展开；3) 语言庄重、简洁、书面化，去掉口语、重复和语气词；4) 只能使用口述中的事实、数字、单位，严禁编造或用套话填充没有的信息；5) 口述信息少时，就写得短而实，不要硬凑。只输出 JSON：{"title":"标题","paragraphs":["段落1","段落2"]}，不要其他文字。'
        $body = @{ model = 'deepseek-flash'; messages = @(@{ role = 'system'; content = $sys }, @{ role = 'user'; content = $raw }); max_tokens = 900; temperature = 0.5; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
        $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $req.Content = $content
        $resp = $script:gongwenHttp.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $reply = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        if (-not $reply) { Show-Bubble '模型没返回内容'; return }
        $clean = $reply -replace '(?s)^\s*```(?:json)?\s*', '' -replace '(?s)\s*```\s*$', ''
        $obj = $null
        try { $obj = $clean | ConvertFrom-Json } catch { }
        if (-not $obj) { Show-Bubble '整理结果解析失败'; return }
        $title = [string]$obj.title
        $paras = @($obj.paragraphs | Where-Object { $_ })
        if ($paras.Count -eq 0) { Show-Bubble '整理结果为空'; return }
        $base = Split-Path (Get-BriefingDir) -Parent
        $dir = Join-Path $base '公文'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $out = Join-Path $dir ('公文-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.docx')
        $py = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'docx_export.py'
        $payload = @{ title = $title; paragraphs = $paras } | ConvertTo-Json -Depth 5 -Compress
        $pf = Join-Path $DataDir 'gongwen-payload.json'
        [IO.File]::WriteAllText($pf, $payload, (New-Object Text.UTF8Encoding($false)))
        & python $py $pf $out 2>$null | Out-Null
        if (Test-Path $out) {
            Show-Bubble ('写好了：' + $out)
            Speak-Text '公文写好了，主人看看'
            Write-Err ('GONGWEN saved=' + $out)
        } else { Show-Bubble 'Word 生成失败' }
    } catch { Write-Err ('GONGWEN-ERR ' + $_.Exception.Message); Show-Bubble '写的时候出错了' }
}

function Get-BriefingDir {
    $dir = ''
    try { $dir = [string]$script:cfg.briefing.dir } catch { }
    if (-not $dir) { $dir = 'F:\桌宠' }
    if (-not (Test-Path $dir)) { try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { } }
    return $dir
}

function Show-Briefing {
    try {
        $material = @()
        $digest = @(Get-SessionDigest)
        if ($digest.Count -gt 0) { $material += ('今天在 DSH 里做的工作（会话标题）：' + ($digest -join '；')) }
        $w = Get-WeatherLine
        if ($w) { $material += ('天气：' + $w) }
        $notes = @(Get-TodayNotes)
        if ($notes.Count -gt 0) { $material += ('今天要办的事：' + ($notes -join '；')) } else { $material += '今天没有待办提醒。' }
        $txt = Invoke-BriefingLlm (($material -join "`n") + "`n请用一句话播报给主人。")
        if (-not $txt) { $txt = '主人早呀，' + ($material -join '。') }
        Show-Bubble $txt
        Speak-Text $txt
        Write-Err ('BRIEFING done len=' + $txt.Length)
        # 按日期存一份 DOCX 到 桌面\每日简报，方便以后查阅
        try {
            $briefDir = Get-BriefingDir
            if (-not (Test-Path $briefDir)) { New-Item -ItemType Directory -Force -Path $briefDir | Out-Null }
            $docxOut = Join-Path $briefDir ('工作简报-' + (Get-Date).ToString('yyyy-MM-dd') + '.docx')
            $pyScript = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'briefing_docx.py'
            if (Test-Path $pyScript) {
                $payload = @{
                    date = (Get-Date).ToString('yyyy-MM-dd')
                    sessions = @($digest)
                    weather = [string]$w
                    notes = @($notes)
                    speech = $txt
                } | ConvertTo-Json -Depth 5 -Compress
                $payloadFile = Join-Path $DataDir 'briefing-payload.json'
                [IO.File]::WriteAllText($payloadFile, $payload, (New-Object Text.UTF8Encoding($false)))
                & python $pyScript $payloadFile $docxOut 2>$null | Out-Null
                if (Test-Path $docxOut) { Write-Err ('BRIEF-DOCX ' + $docxOut) }
            }
        } catch { Write-Err ('BRIEF-DOCX-ERR ' + $_.Exception.Message) }
    } catch { Write-Err ('BRIEF-ERR ' + $_.Exception.Message) }
}

# 最近 5 天简报：每次打开菜单前重建子项，点一下用默认程序（WPS）打开
function Update-RecentBriefs {
    try {
        if ($null -eq $miBriefRecent) { return }
        $miBriefRecent.DropDownItems.Clear()
        $dir = Get-BriefingDir
        $files = @()
        if (Test-Path $dir) { $files = @(Get-ChildItem $dir -Filter '工作简报-*.docx' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5) }
        if ($files.Count -eq 0) {
            $none = $miBriefRecent.DropDownItems.Add('（还没有简报）')
            $none.Enabled = $false
            return
        }
        foreach ($f in $files) {
            $label = [string]$f.BaseName
            if ($label -match '工作简报-(.+)') { $label = $Matches[1] }
            $it = $miBriefRecent.DropDownItems.Add($label)
            $it.Tag = [string]$f.FullName
            $it.Add_Click({
                param($s, $e)
                try { Start-Process -FilePath ([string]$s.Tag) } catch { Write-Err ('BRIEF-OPEN-ERR ' + $_.Exception.Message) }
            })
        }
    } catch { }
}

