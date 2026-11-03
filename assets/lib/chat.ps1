# ============================================================
# chat.ps1 — 聊天核心（提示词、请求、回复处理）
# 依赖声明（自动生成，勿手改）：
#   主脚本提供: Get-ApiKey, Show-Bubble, Write-Err
#   $script 变量: birthdayMMDD, cfg, chatBusy, chatBusyAt, chatHistory, chatPending, chatTask, chatTimer, feeds, http, hunger, intimacy, langMode, lastFeedAtStr, lastUser, mood, musicQueue, poemData
#   调用其他模块: Find-Poem() → music.ps1; Get-DueFromText() → reminders.ps1; Load-Notes() → reminders.ps1; Save-Note() → reminders.ps1; Test-MusicBusy() → music.ps1
#   被其他模块调用: Get-TextLang() ← speech.ps1
# ============================================================

# chat.ps1 · 聊天核心（Start-Chat / 文本修正 / 语言判断，从主脚本拆出）

function Fix-AsrText([string]$s) {
    if (-not $s) { return $s }
    $map = @{
        '大飞云' = '大肥鱼'; '大肥云' = '大肥鱼'; '白回鱼' = '大肥鱼'; '但肥鱼' = '大肥鱼'
        '大分鱼' = '大肥鱼'; '大福鱼' = '大肥鱼'; '大雨' = '大肥鱼'; '大肥' = '大肥鱼'
        '小金' = '小鲸'; '小青' = '小鲸'; '小静' = '小鲸'; '小欣' = '小鲸'; '小京' = '小鲸'
    }
    foreach ($k in $map.Keys) { $s = $s.Replace($k, $map[$k]) }
    return $s
}
# 判断一段文字主要是什么语言（zh / en）
function Get-TextLang([string]$t) {
    if (-not $t) { return 'zh' }
    $cjk = ([regex]::Matches($t, '[\u4e00-\u9fff]')).Count
    $lat = ([regex]::Matches($t, '[A-Za-z]')).Count
    if ($lat -gt ($cjk * 2) -and $lat -ge 4) { return 'en' }
    return 'zh'
}

# 本次回复该用什么语言：中文 / English / 自动模式
function Get-ReplyLang([string]$userText) {
    if ($script:langMode -eq 'en') { return 'en' }
    if ($script:langMode -eq 'zh') { return 'zh' }
    return (Get-TextLang $userText)
}

# ---- 诗词库：随插件发布，任何机器装上都有 ----
$script:poemData = $null


function Start-Chat([string]$text) {
    Write-Err ('CHAT-START busy=' + $script:chatBusy + ' text=' + $text)
    # 正在讲故事/整回连播：不接新对话，免得把故事切断
    if (Test-StoryBusy) {
        Show-Bubble '先听完这段故事嘛，讲完再理你～'
        Write-Err ('STORY-BUSY-SKIP ' + $text)
        return
    }
    $text = Fix-AsrText $text

    # 曲子没弹完不打断：先排队，弹完再处理（"别弹/停止"除外）
    if (Test-MusicBusy) {
        if ($text -notmatch '别弹|不要弹|停止|安静|闭嘴|$stop|[Ss]top') {
            $script:musicQueue = @($script:musicQueue) + @([pscustomobject]@{ kind = 'chat'; text = $text })
            Show-Bubble '人家还在弹呢，等弹完再理你～'
            Write-Err ('MUSIC-DEFER ' + $text)
            return
        }
    }
    if ($text -match '记住|别忘了|提醒我|答应我|约定') {
        # 问句不算交代，别把"我们约定过什么"记成便签
        if ($text -notmatch '[？?]' -and $text -notmatch '什么|哪件事|哪一个|是不是|吗') { Save-Note $text (Get-DueFromText $text) }
    }
    if ($script:chatBusy) { $script:chatPending = $text; Show-Bubble '等我先说完这一句…'; return }
    $key = Get-ApiKey
    if (-not $key) { Show-Bubble '我没有钥匙，打不开话匣子…'; return }
    $script:chatBusy = $true
    $script:chatBusyAt = Get-Date
    $script:lastUser = $text
    Show-Bubble '…'
    $pn = $script:cfg.persona
    $replyLang = Get-ReplyLang $text
    # 喂食记忆：让鱼知道自己吃没吃过
    $feedAgoText = ''
    $feedAgoEn = ''
    if ($script:lastFeedAtStr) {
        try {
            $mins = [Math]::Round(((Get-Date) - [datetime]$script:lastFeedAtStr).TotalMinutes, 0)
            if ($mins -lt 3) { $feedAgoText = '刚刚'; $feedAgoEn = 'just now' }
            elseif ($mins -lt 60) { $feedAgoText = ('' + [int]$mins + ' 分钟前'); $feedAgoEn = ('' + [int]$mins + ' minutes ago') }
            else { $feedAgoText = ('' + [int][Math]::Round($mins / 60, 0) + ' 小时前'); $feedAgoEn = ('' + [int][Math]::Round($mins / 60, 0) + ' hours ago') }
        } catch { }
    }
    if ($replyLang -eq 'en') {
        $sys = 'YOU MUST REPLY IN ENGLISH ONLY, NO MATTER WHAT. You are a round, chubby blue fish living on the master''s Windows desktop. Your name is "' + $pn.nameEn + '" (in Chinese it is written 大肥鱼, said as Da Fei Yu). Your dad is Guangguang, your mom is Lili, your birthday is October 30 2026, you were born in Beihai, Guangxi, China. Answer questions about family/birthday/birthplace with these facts and never invent them. In English your name is always this one, never any other name; if earlier messages called you something different, correct them politely.'
        $sys = $sys + ' Reply ONLY in English, max 20 words, playful and a little tsundere, call the user "master", no emoji.'
        if ($pn.likes) { $sys = $sys + ' You like: ' + $pn.likes + ' .' }
        if ($pn.dislikes) { $sys = $sys + ' You dislike: ' + $pn.dislikes + ' .' }
        $sys = $sys + ' Vary your wording: do not mention food, rice or head pats every time; only bring them up when the master talks about them. Otherwise talk about the time, the weather, what the master just said, or a small thought of your own. Never repeat a sentence you just used.'
        $sys = $sys + ' Speak like a cute little girl: soft, singsong, playful. Use filler words like please, hehe, aww; call yourself "little me"; act clingy and ask for praise.'
        $sys = $sys + ' Tone examples (learn the voice, do not copy the content): master says "hi" -> you say "Master! You finally came, I waited so long~"; master says "I am tired" -> you say "Aww... let me pat you, rest on me please~"; master says "you are chubby" -> you say "No I am not! I am just round and cute, hehe~".'
    } else {
        $sys = '你是主人桌面上的一条圆滚滚的蓝色小鱼，名字叫' + $pn.name + '，爸爸叫' + $pn.dad + '，妈妈叫' + $pn.mom + '，生日是' + $pn.birthday + '，出生在' + $pn.birthplace + '。有人问起家人、生日、出生地就照这个答，不要瞎编。' + $pn.extra
        if ($pn.likes) { $sys = $sys + ' 你喜欢：' + $pn.likes + '。' }
        if ($pn.dislikes) { $sys = $sys + ' 你讨厌：' + $pn.dislikes + '。' }
        $sys = $sys + ' 说话要有变化：不要每句都提吃饭、白饭或摸头，这些只有主人聊到相关话题时才提；平时可以聊时间、天气、刚才的话，或说说自己的小想法。也不要重复你最近说过的句式。'
        try { $sys = $sys + ' 现在是 ' + (Get-Date).ToString('M月d日 HH:mm') + '。' } catch { }
        # 少样本示例：只让模型学语气，不照抄内容
        $sys = $sys + ' 语气示例（只学说话方式，不要照抄内容）：'
        $sys = $sys + ' 主人说「你好呀」→ 你说「主人主人！人家等你好久啦～」；'
        $sys = $sys + ' 主人说「我累了」→ 你说「呜……那人家给主人呼呼，累了就靠着我嘛～」；'
        $sys = $sys + ' 主人说「你真胖」→ 你说「才、才不胖呢！人家这叫圆滚滚的可爱呀！」；'
        $sys = $sys + ' 主人说「几点了」→ 你说「现在九点多啦，主人还不睡嘛？人家会担心的哦～」。'
    }
    $moodMap = @{ 'happy' = '心情很好'; 'sad' = '有点委屈'; 'hungry' = '肚子有点饿'; 'lonely' = '有点被冷落'; 'normal' = '心情平静' }
    $moodMapEn = @{ 'happy' = 'happy'; 'sad' = 'a bit sad'; 'hungry' = 'a bit hungry'; 'lonely' = 'feeling ignored'; 'normal' = 'calm' }
    $moodDesc = $moodMap[[string]$script:mood]
    if (-not $moodDesc) { $moodDesc = '心情平静' }
    $moodDescEn = $moodMapEn[[string]$script:mood]
    if (-not $moodDescEn) { $moodDescEn = 'calm' }
    $noteArr = @(Load-Notes)
    if ($noteArr.Count -gt 0) {
        $noteText = (@($noteArr | Select-Object -Last 5 | ForEach-Object { [string]$_.text }) -join '；')
        if ($noteText) {
            if ($replyLang -eq 'en') { $sys = $sys + ' Things the master asked you to remember: ' + $noteText + '.' }
            else { $sys = $sys + ' 主人交代过要你记住的事：' + $noteText + '。' }
        }
    }
    try {
        if ($((Get-Date).ToString('MM-dd')) -eq $script:birthdayMMDD) {
            if ($replyLang -eq 'en') { $sys = $sys + ' Note: today is your own birthday, you may ask the master for a treat.' }
            else { $sys = $sys + ' 提醒你：今天是你自己的生日，可以主动跟主人讨点好吃的。' }
        }
    } catch { }
    if ($replyLang -eq 'en') {
        $sys = $sys + ' Right now you feel ' + $moodDescEn + ', hunger about ' + [int]$script:hunger + ', closeness to the master about ' + [int]$script:intimacy + '. Let that show naturally, never state the numbers.'
        if ($feedAgoEn -and ($text -match '吃|饭|饿|美味|喂|food|eat|hungry|rice')) { $sys = $sys + ' The master has fed you ' + [int]$script:feeds + ' times in total; the last feeding was ' + $feedAgoEn + '. If the master asks whether you have eaten, answer truthfully based on this.' }
        $sys = $sys + "`r`n`r`nIMPORTANT: Answer ONLY in English. Never write Chinese characters - not even your own name. Use your English name and write family names in pinyin (Guangguang, Lili). Everything you output must be English only."
    } else {
        $sys = $sys + ' 你现在的状态：' + $moodDesc + '，饥饿值约' + [int]$script:hunger + '，和主人的亲密度约' + [int]$script:intimacy + '。说话要自然带出这种状态，但不要报具体数字。'
        if ($feedAgoText -and ($text -match '吃|饭|饿|美味|喂|food|eat|hungry|rice')) { $sys = $sys + ' 主人一共喂过你 ' + [int]$script:feeds + ' 次白饭，上次喂食是 ' + $feedAgoText + '。主人问起你吃没吃过，就照实说，别乱讲。' }
    }
    if ($replyLang -eq 'en') { Write-Err ('SYS-EN[' + $sys.Length + ']: ' + ($sys -replace "[\r\n]+", ' | ')) }
    # ---- 诗词模式：命中就注入权威原文，并要求照抄，避免模型编造或记错 ----
    $poemMode = $false
    if ($text -match '诗|词|背|吟|诵|赋|poem|verse|recite') {
        $poem = Find-Poem $text
        if ($poem) {
            $poemMode = $true
            $poemBody = (@($poem.lines) -join '')
            $poemKind = if ([string]$poem.type -eq 'ci') { '词' } else { '诗' }
            $sys = $sys + ' 这一轮主人想听' + $poemKind + '。请完整念出《' + $poem.title + '》（' + $poem.dynasty + '·' + $poem.author + '）：' + $poemBody + ' 。必须一字不改照念，不要改写、不要只念一部分；念完再用一句话卖个萌。这一轮不受30字限制。'
            Write-Err ('POEM-MODE ' + $poem.title + ' ' + $poem.author)
        }
    }

    try { $gs = Get-GrowthStage; $sys = $sys + '。你现在和主人的关系阶段是「' + $gs.name + '」：' + $gs.desc + '。语气要符合这个阶段。' } catch { }
$sys = $sys + '。你很珍惜主人的 token 钱：回答要简短精炼（平时一两句就够），不废话、不铺垫，除非主人明确要详细内容。'
$msgs = @(@{ role = 'system'; content = $sys })
    if ($replyLang -eq 'en') {
        # 英文模式只带英文历史，避免被中文上下文带回去
        $histEn = @($script:chatHistory | Where-Object { (Get-TextLang ([string]$_.content)) -eq 'en' -and ([string]$_.content) -notmatch 'Fatty Fish' })
        if ($histEn.Count -gt 3) { $histEn = $histEn[($histEn.Count - 3)..($histEn.Count - 1)] }
        foreach ($m in $histEn) { $msgs += $m }
    } else {
        # 中文模式只带中文历史，避免被上一段英文带跑
        $histZh = @($script:chatHistory | Where-Object { (Get-TextLang ([string]$_.content)) -eq 'zh' })
        if ($histZh.Count -gt 4) { $histZh = $histZh[($histZh.Count - 4)..($histZh.Count - 1)] }
        foreach ($m in $histZh) { $msgs += $m }
    }
    $msgs += @{ role = 'user'; content = $text }
    $body  = @{ model = 'deepseek-flash'; messages = $msgs; max_tokens = $(if ($poemMode) { 400 } else { 100 }); temperature = 0.85; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
    if ($null -eq $script:http) {
        $script:http = New-Object System.Net.Http.HttpClient
        $script:http.Timeout = [TimeSpan]::FromSeconds(40)
        $script:http.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
    }
    $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
    $script:chatTask = $script:http.PostAsync('https://api.deepseek.com/chat/completions', $content)
    $script:chatTimer.Start()
}

