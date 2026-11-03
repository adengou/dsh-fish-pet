# story.ps1 · 说书模块：选回目、整回连播、用鱼自己的话讲（带进度记忆）
# 依赖主脚本：$DataDir / Show-Bubble / Speak-Text / Write-Err / Get-ApiKey / $script:cfg

# 各书作者（开场白报书名-作者-回目）
$script:STORY_AUTHORS = @{
    '聊斋志异' = '蒲松龄'; '三国演义' = '罗贯中'; '西游记' = '吴承恩'; '水浒传' = '施耐庵'
    '红楼梦' = '曹雪芹'; '儒林外史' = '吴敬梓'; '镜花缘' = '李汝珍'; '三言二拍' = '冯梦龙、凌濛初'
    '官场现形记' = '李宝嘉'; '老残游记' = '刘鹗'; '世说新语' = '刘义庆'; '封神演义' = '许仲琳'
    '东周列国志' = '冯梦龙'; '隋唐演义' = '褚人获'; '说岳全传' = '钱彩'; '杨家将演义' = '熊大木'
    '三侠五义' = '石玉昆'; '喻世明言' = '冯梦龙'; '警世通言' = '冯梦龙'; '醒世恒言' = '冯梦龙'; '初刻拍案惊奇' = '凌濛初'; '二刻拍案惊奇' = '凌濛初'
}

$script:storyChunks = $null
$script:storyIndex = 0
$script:storyProgress = $null
$script:storyProgressPath = Join-Path $DataDir 'story_progress.json'
$script:storyQueue = @()     # 当前回目待播的段
$script:storyQueueBook = ''
$script:storyQueueTitle = ''
$script:storyUntil = $null

# ---------- 进度记忆 ----------
function Load-StoryProgress {
    if ($null -ne $script:storyProgress) { return }
    $script:storyProgress = @{}
    try {
        if (Test-Path $script:storyProgressPath) {
            $obj = [IO.File]::ReadAllText($script:storyProgressPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($obj) {
                foreach ($p in $obj.PSObject.Properties) {
                    if ($p.Value) { $script:storyProgress[$p.Name] = $true }
                }
            }
        }
    } catch { }
}

function Save-StoryProgress {
    try {
        $hash = @{}
        foreach ($k in @($script:storyProgress.Keys)) { $hash[[string]$k] = $true }
        $json = $hash | ConvertTo-Json -Compress
        if ($json -eq 'null') { $json = '{}' }
        [IO.File]::WriteAllText($script:storyProgressPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Get-StoryKey($chunk) {
    return ([string]$chunk.book + '|' + [string]$chunk.title + '|' + [string]$chunk.piece)
}

# ---------- 切片加载 ----------
function Load-StoryChunks {
    if ($script:storyChunks) { return $script:storyChunks }
    $all = @()
    $seen = @{}
    try {
        $dirs = @(
            (Join-Path (Split-Path -Parent $PSCommandPath) '..\data\story'),
            $DataDir
        )
        foreach ($dir in $dirs) {
            if (-not (Test-Path $dir)) { continue }
            foreach ($f in (Get-ChildItem $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                try {
                    $arr = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
                    foreach ($c in @($arr)) {
                        $key = [string]$c.book + '|' + [string]$c.title + '|' + [string]$c.piece
                        if (-not $seen.ContainsKey($key)) {
                            $seen[$key] = $true
                            $all += $c
                        }
                    }
                } catch { }
            }
        }
    } catch { }
    $script:storyChunks = $all
    return $all
}

# ---------- 改写（鱼自己的话，成人评书腔） ----------
# 说书改写缓存：讲过的段直接复用，不再花 token
$script:storyCachePath = Join-Path $DataDir 'story_cache.json'
$script:storyCache = $null
$script:storyCacheDirty = $false

function Get-StoryCacheKey([string]$bookName, [string]$title, [string]$original) {
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($bookName + '|' + $title + '|' + $original)
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash($bytes)
        $sha.Dispose()
        return ([BitConverter]::ToString($hash) -replace '-', '').Substring(0, 16)
    } catch { return ($bookName + '|' + $title + '|' + [string]$original.Length) }
}

function Load-StoryCache {
    if ($null -ne $script:storyCache) { return }
    $script:storyCache = @{}
    try {
        if (Test-Path $script:storyCachePath) {
            $obj = [IO.File]::ReadAllText($script:storyCachePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($obj) {
                foreach ($p in $obj.PSObject.Properties) { $script:storyCache[$p.Name] = [string]$p.Value }
            }
        }
    } catch { }
}

function Save-StoryCache {
    try {
        if (-not $script:storyCacheDirty) { return }
        $obj = @{}
        foreach ($k in $script:storyCache.Keys) { $obj[[string]$k] = [string]$script:storyCache[$k] }
        $json = $obj | ConvertTo-Json -Compress
        if ($json -eq 'null') { $json = '{}' }
        [IO.File]::WriteAllText($script:storyCachePath, $json, (New-Object Text.UTF8Encoding($false)))
        $script:storyCacheDirty = $false
    } catch { }
}

function Invoke-StoryLlm([string]$bookName, [string]$title, [string]$original, [string]$prev = '', [bool]$isLast = $false) {
    try {
        $key = Get-ApiKey
        # 缓存命中：讲过的段直接复用，不花 token
        try { Load-StoryCache; $ck0 = Get-StoryCacheKey $bookName $title $original; if ($script:storyCache.ContainsKey($ck0)) { Write-Err ('STORY-CACHE-HIT ' + $title); return [string]$script:storyCache[$ck0] } } catch { }
        if (-not $key) { return $null }
        if ($null -eq $script:storyHttp) {
            $script:storyHttp = New-Object System.Net.Http.HttpClient
            $script:storyHttp.Timeout = [TimeSpan]::FromSeconds(60)
        }
        try { $gs = Get-GrowthStage; $sys = '（你现在和主人的关系阶段是「' + $gs.name + '」：' + $gs.desc + '。讲故事时可以带上这个阶段的语气。）' } catch { }
        $sys = '你是一位说书人，用成人评书的腔调讲' + $bookName + '里的《' + $title + '》，讲给主人听：' +
               '① 忠于原文情节，不添油加醋、不编造原文没有的人物和情节；' +
               '② 用评书口吻（列位看官、不料、谁知、这一下可好），语气稳重、有韵味、有起伏；不要用【话说】【且说】【话说主人】开头（已经报过书名了），直接讲正文，不要卖萌、不要撒娇、不要用网络用语；' +
               '③ 称呼"主人"；' +
               '④ 用 300-500 字把这一段故事**完整讲完**：必须交代结局（如"后来……""从此……"），不能讲一半就停、不能省略结尾；' + $(if ($isLast) { '这是本回的结尾，自然收尾，不要说"且听下回分解"；' } else { '后面还有下文，结尾可以留个悬念；' }) +
               '⑤ 不要用表情符号，不要报书名和"原文"，直接开讲。'
        $body = @{
            model = 'deepseek-flash'
            messages = @(
                @{ role = 'system'; content = $sys },
                @{ role = 'user'; content = $(if ($prev) { '上次讲到：' + $prev + "`n" + '这次接着原文讲：' + $original } else { '原文：' + $original }) }
            )
            max_tokens = 1200
            temperature = 0.7
            thinking = @{ type = 'disabled' }
        } | ConvertTo-Json -Depth 6
        $c = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $req.Content = $c
        $resp = $script:storyHttp.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $reply = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        # 鱼粮账本：记录说书消耗
        try { $u = ($jsonText | ConvertFrom-Json).usage; if ($u) { Add-FishFoodTokens 'story' ([int]$u.prompt_tokens) ([int]$u.completion_tokens) } } catch { }
        if ($reply) {
            $trimmed = $reply.Trim()
            try { Load-StoryCache; $ck = Get-StoryCacheKey $bookName $title $original; $script:storyCache[$ck] = $trimmed; $script:storyCacheDirty = $true; Save-StoryCache } catch { }
            return $trimmed
        }
    } catch { Write-Err ('STORY-LLM-ERR ' + $_.Exception.Message) }
    return $null
}

# ---------- 播一段 ----------
function Speak-StoryChunk($pick, [bool]$isFirst) {
    try {
        $bookName = [string]$pick.book
        if (-not $bookName) { $bookName = '故事' }
        $title = [string]$pick.title
        $piece = [int]$pick.piece
        $total = [int]$pick.total
        $isLast = ($piece -ge $total)
        $original = [string]$pick.text
        $prev = ''
        try { $prev = [string]$script:storyLastSpoken } catch { }
        $spoken = Invoke-StoryLlm $bookName $title $original $prev $isLast
        if ($spoken) { $script:storyLastSpoken = $spoken }
        if (-not $spoken) { $spoken = $original }
        $authorName = ''
        try { if ($script:STORY_AUTHORS.ContainsKey($bookName)) { $authorName = [string]$script:STORY_AUTHORS[$bookName] } } catch { }
        $authorPart = if ($authorName) { '，' + $authorName + '著' } else { '' }
        $cleanTitle = $title -replace '正文\s*', ''
        if ($isFirst) {
            $intro = '话说，今天给主人讲一段《' + $bookName + '》' + $authorPart + '，' + $cleanTitle + '。'
        } else {
            $intro = ''
        }
        $tail = if ($isLast) { '这一回，就讲到这里。' } else { '' }
        $full = $intro + $spoken + $tail
        Show-Bubble ('讲一段：' + $title + '（' + $piece + '/' + $total + '）')
        $storyRate = '-15%'
        try { if ($script:cfg.story -and $script:cfg.story.rate) { $storyRate = [string]$script:cfg.story.rate } } catch { }
        $estSec = [Math]::Max(30, [int]($full.Length * 0.45))
        $script:storyUntil = (Get-Date).AddSeconds($estSec)
        Speak-Text $full $storyRate
        $script:storyProgress[(Get-StoryKey $pick)] = $true
        Save-StoryProgress
        Write-Err ('STORY ' + $bookName + ' | ' + $title + ' piece=' + $piece + '/' + $total + ' llm=' + [bool]$spoken)
        try { Add-Growth 1 'story' } catch { }
    } catch { Write-Err ('STORY-SPEAK-ERR ' + $_.Exception.Message) }
}

# ---------- 主 tick 调用：整回连播 ----------
function Invoke-StoryQueueTick {
    try {
        if ($script:storyQueue.Count -eq 0) { return }
        if (Test-Path (Join-Path $DataDir 'asr.talking')) { return }   # 还在说
        # 播放中（speakEndAt 未到）不续播，避免两段叠在一起
        if ($script:speakEndAt -and ((Get-Date) -lt $script:speakEndAt)) { return }
        # TTS 队列里还有没播完的段：等它全播完再续（否则会把本段后面的句子掐掉）
        try { if ($script:ttsSegs -and $script:ttsSegs.Count -gt 0) { return } } catch { }
        # 节流：每 2 秒最多续一次
        $now = Get-Date
        if ($script:storyLastTick -and ($now - $script:storyLastTick).TotalSeconds -lt 2) { return }
        $script:storyLastTick = $now
        $next = $script:storyQueue[0]
        $script:storyQueue = @($script:storyQueue | Select-Object -Skip 1)
        Speak-StoryChunk $next $false
    } catch { }
}

# ---------- 开始讲 ----------
function Start-Story([string]$hint) {
    try {
        $chunks = Load-StoryChunks
        if (-not $chunks -or $chunks.Count -eq 0) {
            Show-Bubble '我还没学会讲故事呢，让主人先给我装点书～'
            return
        }
        Load-StoryProgress
        $pick = $null
        if ($hint -match '继续|接着|然后|下一段') {
            # 继续：优先队列，其次随机没讲过的
            if ($script:storyQueue.Count -gt 0) {
                $next = $script:storyQueue[0]
                $script:storyQueue = @($script:storyQueue | Select-Object -Skip 1)
                Speak-StoryChunk $next $false
                return
            }
            $allFresh = @($chunks | Where-Object { -not $script:storyProgress.ContainsKey((Get-StoryKey $_)) })
            if ($allFresh.Count -eq 0) { $script:storyProgress = @{}; $allFresh = $chunks }
            $pick = $allFresh[(Get-Random -Maximum $allFresh.Count)]
        } else {
            $matches = @()
            foreach ($c in $chunks) {
                if (-not $hint) { continue }
                if ($hint.Contains([string]$c.title) -or ($c.book -and $hint.Contains([string]$c.book))) {
                    $matches += $c
                    continue
                }
                $short = [string]$c.book
                if ($short.Length -gt 2) { $short = $short.Substring(0, 2) }
                if ($short -and $hint.Contains($short)) { $matches += $c }
            }
            if ($matches.Count -gt 0) {
                $fresh = @($matches | Where-Object { -not $script:storyProgress.ContainsKey((Get-StoryKey $_)) })
                if ($fresh.Count -eq 0) {
                    # 这本都讲过了：清掉这本书的进度，从头再来
                    $books = @{}
                    foreach ($m in $matches) { $books[[string]$m.book] = $true }
                    $keys = @($script:storyProgress.Keys)
                    foreach ($k in $keys) {
                        foreach ($b in $books.Keys) {
                            if ([string]$k -like ($b + '|*')) { $script:storyProgress.Remove($k) }
                        }
                    }
                    $fresh = $matches
                    Write-Err 'STORY-RESET book-progress'
                }
                # 优先从某一回的第一段开始（整回讲）
                $firstPieces = @($fresh | Where-Object { [int]$_.piece -eq 1 })
                if ($firstPieces.Count -gt 0) { $pick = $firstPieces[(Get-Random -Maximum $firstPieces.Count)] }
                else { $pick = $fresh[(Get-Random -Maximum $fresh.Count)] }
            } else {
                $allFresh = @($chunks | Where-Object { -not $script:storyProgress.ContainsKey((Get-StoryKey $_)) })
                if ($allFresh.Count -eq 0) { $script:storyProgress = @{}; $allFresh = $chunks }
                # 优先从某回第一段开始，保证整回完整
                $freshFirst = @($allFresh | Where-Object { [int]$_.piece -eq 1 })
                if ($freshFirst.Count -gt 0) { $pick = $freshFirst[(Get-Random -Maximum $freshFirst.Count)] }
                else { $pick = $allFresh[(Get-Random -Maximum $allFresh.Count)] }
            }
        }
        if (-not $pick) { Show-Bubble '想不起来讲哪段了…'; return }
        # 换书：清掉上一本的衔接上下文
        $pickBook = [string]$pick.book
        if ($script:storyBook -ne $pickBook) {
            $script:storyLastSpoken = ''
            $script:storyBook = $pickBook
            Write-Err ('STORY-BOOK-SWITCH ' + $pickBook)
        }
        # 建立整回队列：同书、同回目、piece 从当前段到结尾
        $q = @($chunks | Where-Object {
            [string]$_.book -eq $pickBook -and [string]$_.title -eq [string]$pick.title -and [int]$_.piece -ge [int]$pick.piece
        } | Sort-Object { [int]$_.piece })
        $script:storyQueue = $q
        $script:storyQueueBook = $pickBook
        $script:storyQueueTitle = [string]$pick.title
        # 播第一段（从队列里取）
        $first = $script:storyQueue[0]
        $script:storyQueue = @($script:storyQueue | Select-Object -Skip 1)
        Speak-StoryChunk $first $true
    } catch { Write-Err ('STORY-ERR ' + $_.Exception.Message) }
}
