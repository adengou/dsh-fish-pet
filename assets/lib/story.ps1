# story.ps1 · 说书模块：读切片、选段、用鱼自己的话讲出来
# 依赖主脚本：$DataDir / Show-Bubble / Speak-Text / Write-Err / Get-ApiKey / $script:cfg

$script:storyChunks = $null
$script:storyIndex = 0

# 读取故事切片（缓存）
function Load-StoryChunks {
    if ($script:storyChunks) { return $script:storyChunks }
    try {
        $f = Join-Path $DataDir 'story_chunks.json'
        if (-not (Test-Path $f)) { $f = Join-Path (Split-Path -Parent $PSCommandPath) '..\data\story\liaozhai_chunks.json' }
        if (-not (Test-Path $f)) { return $null }
        $arr = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $script:storyChunks = @($arr)
    } catch { $script:storyChunks = $null }
    return $script:storyChunks
}

# 取下一个片段（连载用）
function Get-NextStoryChunk {
    $chunks = Load-StoryChunks
    if (-not $chunks -or $chunks.Count -eq 0) { return $null }
    if ($script:storyIndex -ge 0 -and $script:storyIndex -lt $chunks.Count) {
        $cur = $chunks[$script:storyIndex]
        if ($cur.piece -lt $cur.total -and ($script:storyIndex + 1) -lt $chunks.Count) {
            $next = $chunks[$script:storyIndex + 1]
            if ($next.title -eq $cur.title) {
                $script:storyIndex += 1
                return $next
            }
        }
    }
    $script:storyIndex = Get-Random -Maximum $chunks.Count
    return $chunks[$script:storyIndex]
}

# 用鱼自己的话把原文讲出来（忠于原文，不编造）
function Invoke-StoryLlm([string]$title, [string]$original) {
    try {
        $key = Get-ApiKey
        if (-not $key) { return $null }
        if ($null -eq $script:storyHttp) {
            $script:storyHttp = New-Object System.Net.Http.HttpClient
            $script:storyHttp.Timeout = [TimeSpan]::FromSeconds(40)
        }
        $sys = '你是桌面宠物"大肥鱼"，一只会讲故事的小鲸鱼。主人点了聊斋里的《' + $title + '》，你要用说书的口吻把这一段讲给主人听：' +
               '① 忠于原文情节，不添油加醋、不编造原文没有的人物和情节；' +
               '② 用自己的口语讲（话说、且说、不料、谁知、这一下可好），有起伏、有悬念；' +
               '③ 称呼"主人"，语气俏皮、微微傲娇；' +
               '④ 200 字左右，结尾留个扣子（欲知后事如何……）；' +
               '⑤ 不要用表情符号，不要报书名和"原文"，直接开讲。'
        $body = @{
            model = 'deepseek-flash'
            messages = @(
                @{ role = 'system'; content = $sys },
                @{ role = 'user'; content = ('原文：' + $original) }
            )
            max_tokens = 600
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
        if ($reply) { return $reply.Trim() }
    } catch { Write-Err ('STORY-LLM-ERR ' + $_.Exception.Message) }
    return $null
}

# 讲一段故事（鱼自己的话）
function Start-Story([string]$hint) {
    try {
        $chunks = Load-StoryChunks
        if (-not $chunks -or $chunks.Count -eq 0) {
            Show-Bubble '我还没学会讲故事呢，让主人先给我装点书～'
            return
        }
        $pick = $null
        if ($hint -match '继续|接着|然后|下一段') {
            $pick = Get-NextStoryChunk
        } else {
            $hit = $null
            foreach ($c in $chunks) {
                if ($hint -and $hint.Contains([string]$c.title)) { $hit = $c; break }
            }
            if ($hit) {
                $script:storyIndex = [array]::IndexOf($chunks, $hit)
                $pick = $hit
            } else {
                $script:storyIndex = Get-Random -Maximum $chunks.Count
                $pick = $chunks[$script:storyIndex]
            }
        }
        if (-not $pick) { Show-Bubble '想不起来讲哪段了…'; return }
        $title = [string]$pick.title
        $piece = [int]$pick.piece
        $total = [int]$pick.total
        $original = [string]$pick.text
        Show-Bubble ('让我组织一下怎么说《' + $title + '》…')
        $spoken = Invoke-StoryLlm $title $original
        if (-not $spoken) { $spoken = $original }
        $intro = if ($piece -eq 1) { '话说，主人今天点了一段聊斋——' + $title + '。' } else { '接着上回，聊斋——' + $title + '。' }
        $tail = if ($piece -lt $total) { '' } else { '这段故事，就讲到这里。' }
        $full = $intro + $spoken + $tail
        $storyRate = '-15%'
        try { if ($script:cfg.story -and $script:cfg.story.rate) { $storyRate = [string]$script:cfg.story.rate } } catch { }
        Show-Bubble ('讲一段：' + $title + '（' + $piece + '/' + $total + '）')
        Speak-Text $full $storyRate
        Write-Err ('STORY ' + $title + ' piece=' + $piece + '/' + $total + ' llm=' + [bool]$spoken)
    } catch { Write-Err ('STORY-ERR ' + $_.Exception.Message) }
}
