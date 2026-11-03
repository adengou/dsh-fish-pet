# ============================================================
# speech.ps1 — TTS 语音朗读
# 依赖声明（自动生成，勿手改）：
#   主脚本提供: Write-Err
#   $script 变量: cfg, lastPlayedWav, mood, pauseHook, playUntil, spPlay, speakEndAt, speakOn, synth, ttsEngine, ttsHandle, ttsMode, ttsMp3, ttsPS, ttsPitch, ttsPitchEn, ttsPool, ttsProc, ttsRate, ttsRateEn, ttsRetry, ttsSegDone, ttsSegFiles, ttsSegOut, ttsSegPitch, ttsSegPlayed, ttsSegPlaying, ttsSegRate, ttsSegReq, ttsSegReqAt, ttsSegVoice, ttsSegWav, ttsSegs, ttsStatusFile, ttsText, ttsTimer, ttsVoice, ttsVoiceEn, ttsVoiceUsed
#   调用其他模块: Get-TextLang() → chat.ps1
#   被其他模块调用: Speak-Text() ← briefing.ps1; Speak-Text() ← dsh.ps1; Speak-Text() ← language.ps1
# ============================================================

# speech.ps1 · 语音朗读（TTS 流水线 / 常驻 worker / 状态回收，从主脚本拆出）

function Speak-Sapi([string]$text) {
    try {
        if ($null -eq $script:synth) {
            Add-Type -AssemblyName System.Speech
            $script:synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $zh = $script:synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like 'zh*' } | Select-Object -First 1
            if ($zh) { $script:synth.SelectVoice($zh.VoiceInfo.Name) }
            $script:synth.Rate = 1
        }
        if (-not $script:pauseHook) {
            $script:pauseHook = $true
            $script:synth.add_SpeakCompleted({
                try { Remove-Item -LiteralPath (Join-Path $DataDir 'asr.talking') -Force -ErrorAction SilentlyContinue } catch { }
                try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.pause'), (Get-Date).ToString('o')) } catch { }
            })
        }
        switch ([string]$script:mood) {
            'happy'  { $script:synth.Rate = 2;  $script:synth.Volume = 100 }
            'sad'    { $script:synth.Rate = -2; $script:synth.Volume = 82 }
            'hungry' { $script:synth.Rate = -1; $script:synth.Volume = 92 }
            'lonely' { $script:synth.Rate = -1; $script:synth.Volume = 88 }
            default  { $script:synth.Rate = 1;  $script:synth.Volume = 100 }
        }
        Write-Err ('TTS-SPEAK len=' + $text.Length + ' mood=' + $script:mood + ' rate=' + $script:synth.Rate)
        $script:synth.SpeakAsyncCancelAll()
        $script:synth.SpeakAsync($text) | Out-Null
    } catch { Write-Err ('TTS-ERR ' + $_.Exception.Message) }
}

function Play-TtsFile([string]$mp3, [string]$voice) {
    try {
        # WPF MediaPlayer 在 WinForms 消息循环里不会加载（Position 恒 0），改用 ffmpeg 转 WAV + SoundPlayer
        # 已经是 WAV（worker 转好的）就直接播，省掉主线程里的 ffmpeg 转换
        if ([IO.Path]::GetExtension($mp3) -ieq '.wav' -and (Test-Path $mp3)) {
            try {
                try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.talking'), '1') } catch { }
                if ($null -eq $script:spPlay) { $script:spPlay = New-Object System.Media.SoundPlayer }
                # 上一段 wav 已播完，此时可以安全删除（Windows 下正在用的文件删不掉）
                try { if ($script:lastPlayedWav -and $script:lastPlayedWav -ne $mp3 -and (Test-Path $script:lastPlayedWav)) { Remove-Item -LiteralPath $script:lastPlayedWav -Force -ErrorAction SilentlyContinue } } catch { }
                $script:lastPlayedWav = $mp3
                $script:spPlay.SoundLocation = $mp3
                $script:spPlay.Play()
                $dur = [Math]::Max(0.8, (Get-Item $mp3).Length / 44100.0)
                $script:playUntil = (Get-Date).AddSeconds($dur + 1.5)
                $script:speakEndAt = $script:playUntil
                Write-Err ('TTS-WAV voice=' + $voice + ' file=' + (Get-Item $mp3).Length + ' dur=' + [Math]::Round($dur, 1) + ' direct=1')
                # 播放的是 WAV，对应的 mp3 已经没用，顺手删掉
                try { $mp3sib = [IO.Path]::ChangeExtension($mp3, '.mp3'); if ($mp3sib -ne $mp3 -and (Test-Path $mp3sib)) { Remove-Item -LiteralPath $mp3sib -Force -ErrorAction SilentlyContinue } } catch { }
                return $true
            } catch { Write-Err ('TTS-PLAY-ERR ' + $_.Exception.Message) }
        }
        $ff = [string]$script:cfg.tts.ffmpeg
        if (-not $ff) { $ff = (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue).Source }
        if (-not $ff) { Write-Err 'TTS-NO-FFMPEG'; return $false }
        $wav = Join-Path $DataDir ('tts-play-' + [guid]::NewGuid().ToString('N') + '.wav')
        $log = Join-Path $DataDir 'tts-conv.log'
        try {
            Start-Process -FilePath $ff -ArgumentList @('-y','-loglevel','error','-i',$mp3,'-af','volume=0.75','-ar','22050','-ac','1',$wav) -WindowStyle Hidden -Wait -RedirectStandardError $log | Out-Null
        } catch { Write-Err ('TTS-CONV-ERR ' + $_.Exception.Message) }
        if ((Test-Path $wav) -and (Get-Item $wav).Length -gt 1000) {
            # 每次播放都强制重新上“正在说话”的锁：TTS 重试/失败分支可能已经把锁清掉了
            try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.talking'), '1') } catch { }
            if ($null -eq $script:spPlay) { $script:spPlay = New-Object System.Media.SoundPlayer }
            $script:spPlay.SoundLocation = $wav
            $script:spPlay.Play()
            $dur = [Math]::Max(0.8, (Get-Item $wav).Length / 44100.0)
            # 多留 1.5 秒：SoundPlayer 实际出声比调用晚，留够尾巴，避免自己的声音被耳朵拾成回环
            $script:playUntil = (Get-Date).AddSeconds($dur + 1.5)
            $script:speakEndAt = $script:playUntil
            Write-Err ('TTS-WAV voice=' + $voice + ' file=' + (Get-Item $wav).Length + ' dur=' + [Math]::Round($dur, 1))
            return $true
        } else {
            Write-Err ('TTS-CONV-FAIL ' + $mp3)
            return $false
        }
        try { Get-ChildItem $DataDir -Filter 'tts-play-*.wav' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-3) } | Remove-Item -Force -ErrorAction SilentlyContinue } catch { }
    } catch { Write-Err ('TTS-PLAY-ERR ' + $_.Exception.Message) }
}

# 把回复拆成 1~3 段，边合成边播，缩短"开口等待"
function Split-TtsSegments([string]$text) {
    if (-not $text) { return @() }
    # 短回复整段合成：分段播放时每段都要重新 Open 播放器，段间会有可听见的停顿（英语尤其明显）
    if ($text.Length -le 140) { return @($text) }
    $parts = @($text -split '(?<=[。！？!?；;…\.\r\n])' | Where-Object { $_.Trim() })
    if ($parts.Count -le 1) { return @($text) }
    # 第一段尽量短（先开口），后面合并成最多 2 段
    $first = $parts[0].Trim()
    $rest = ''
    for ($i = 1; $i -lt $parts.Count; $i++) { $rest = $rest + $parts[$i] }
    $rest = $rest.Trim()
    if (-not $rest) { return @($text) }
    if ($rest.Length -le 26) { return ,@($first, $rest) }
    # 剩余拆成两半
    $mid = [Math]::Floor($rest.Length / 2)
    $cut = $rest.LastIndexOfAny([char[]]@('，', ',', '；', '、', ' ', '。', '.'), $mid)
    if ($cut -lt 8) { $cut = $mid }
    $a = $rest.Substring(0, $cut + 1).Trim()
    $b = $rest.Substring($cut + 1).Trim()
    if (-not $b) { return ,@($first, $a) }
    return ,@($first, $a, $b)
}

function Start-TtsPipeline([string]$text, [string]$voice, [string]$rate, [string]$pitch) {
    $segs = Split-TtsSegments $text
    $script:ttsSegs = @($segs)
    $script:ttsSegVoice = $voice
    $script:ttsSegRate = $rate
    $script:ttsSegPitch = $pitch
    $script:ttsSegFiles = @()
    $script:ttsSegDone = @()
    $script:ttsSegPlayed = @()
    $script:ttsSegReq = @()
    $script:ttsSegWav = @()
    $script:ttsSegOut = @()
    $script:ttsSegReqAt = @()
    for ($i = 0; $i -lt $script:ttsSegs.Count; $i++) {
        $script:ttsSegFiles += (Join-Path $env:TEMP ('fish-tts-' + [guid]::NewGuid().ToString('N') + '.mp3'))
        $script:ttsSegWav += [IO.Path]::ChangeExtension($script:ttsSegFiles[$script:ttsSegFiles.Count - 1], '.wav')
        $script:ttsSegOut += ''
        $script:ttsSegDone += $false
        $script:ttsSegPlayed += $false
        $script:ttsSegReq += ''
        $script:ttsSegReqAt += [datetime]::MinValue
    }
    $script:ttsSegPlaying = -1
    $script:ttsRetry = @{}
    Write-Err ('TTS-PIPE segs=' + $script:ttsSegs.Count + ' len=' + $text.Length)
    $script:ttsTimer.Start()
}

function Request-TtsSegment([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:ttsSegs.Count) { return }
    if ($script:ttsSegReq[$idx]) { return }
    try {
        $reqId = '{0:D2}{1}' -f $idx, ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $reqFile = Join-Path $env:TEMP ('fish-tts-req-' + $reqId + '.json')
        $reqObj = @{
            id = $reqId
            text = $script:ttsSegs[$idx]
            voice = $script:ttsSegVoice
            rate = $script:ttsSegRate
            pitch = $script:ttsSegPitch
            out = $script:ttsSegFiles[$idx]
            wav = $(if ($script:ttsSegWav -and $script:ttsSegWav.Count -gt $idx) { $script:ttsSegWav[$idx] } else { $null })
            status = $script:ttsStatusFile
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($reqFile, $reqObj, (New-Object Text.UTF8Encoding($false)))
        $script:ttsProc.StandardInput.WriteLine('@' + $reqFile)
        $script:ttsProc.StandardInput.Flush()
        $script:ttsSegReq[$idx] = $reqId
        if ($null -eq $script:ttsSegReqAt) { $script:ttsSegReqAt = @() }
        while ($script:ttsSegReqAt.Count -le $idx) { $script:ttsSegReqAt += [datetime]::MinValue }
        $script:ttsSegReqAt[$idx] = Get-Date
        Write-Err ('TTS-REQ idx=' + $idx + ' id=' + $reqId)
    } catch { Write-Err ('TTS-REQ-ERR ' + $_.Exception.Message) }
}

function Complete-TtsSegment {
    try {
        $cur = $script:ttsSegPlaying
        if ($cur -ge 0 -and $cur -lt $script:ttsSegPlayed.Count) { $script:ttsSegPlayed[$cur] = $true }
        $script:ttsSegPlaying = -1
        $script:speakEndAt = (Get-Date)
    } catch { }
}

# 启动常驻 TTS 进程（复用连接，比每次启动 python 快一倍）
function Start-TtsWorker {
    try {
        if ($script:ttsProc -and -not $script:ttsProc.HasExited) { return $true }
        $workerPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'tts_worker.py'
        if (-not (Test-Path $workerPath)) { Write-Err 'TTS-WORKER-MISSING'; return $false }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        # 把配置里的 ffmpeg 路径传给 worker（worker 用它转码；没配就自己找 PATH）
        try {
            $ffCfg = [string]$script:cfg.tts.ffmpeg
            if (-not $ffCfg) { $ffCfg = (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue).Source }
            if ($ffCfg) { $psi.EnvironmentVariables['DSH_FISH_FFMPEG'] = $ffCfg }
        } catch { }
        $psi.FileName = 'python'
        $psi.Arguments = '"' + $workerPath + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.CreateNoWindow = $true
        $script:ttsProc = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 350
        if ($script:ttsProc.HasExited) { Write-Err 'TTS-WORKER-DIED'; return $false }
        $script:ttsStatusFile = Join-Path $env:TEMP 'fish-tts-status.txt'
        Write-Err ('TTS-WORKER-START pid=' + $script:ttsProc.Id)
        return $true
    } catch { Write-Err ('TTS-WORKER-ERR ' + $_.Exception.Message); return $false }
}

function Speak-Text([string]$text) {
    if (-not $script:speakOn) { return }
    # 断网兜底：最近一次 edge 合成失败后 60 秒内直接用本机语音
    if ($script:ttsOffline -and $script:ttsOfflineAt -and ((Get-Date) - $script:ttsOfflineAt).TotalSeconds -lt 60) {
        try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.talking'), '1') } catch { }
        try { Speak-Sapi $text; Write-Err ('TTS-SAPI-OFFLINE len=' + $text.Length) } catch { }
        return
    }
    $talkFile = Join-Path $DataDir 'asr.talking'
    try { [IO.File]::WriteAllText($talkFile, '1') } catch { }
    if ($script:ttsEngine -eq 'edge') {
        try {
            $spkLang = Get-TextLang $text
            if ($spkLang -eq 'en') { $vUse = $script:ttsVoiceEn; $rUse = $script:ttsRateEn; $pUse = $script:ttsPitchEn } else { $vUse = $script:ttsVoice; $rUse = $script:ttsRate; $pUse = $script:ttsPitch }
            if (Start-TtsWorker) {
                $script:ttsMode = 'worker'
                $script:ttsVoiceUsed = $vUse
                $script:ttsText = $text
                Start-TtsPipeline $text $vUse $rUse $pUse
                return
            }
            # 常驻进程起不来：退回后台线程整段合成
            if ($null -eq $script:ttsPool) {
                $script:ttsPool = [runspacefactory]::CreateRunspacePool(1, 2)
                $script:ttsPool.Open()
            }
            $mp3 = Join-Path $env:TEMP ('fish-tts-' + [guid]::NewGuid().ToString('N') + '.mp3')
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $script:ttsPool
            [void]$ps.AddScript({
                param($exe, $voice, $rate, $pitch, $txt, $out)
                & $exe -m edge_tts --voice $voice ('--rate=' + $rate) ('--pitch=' + $pitch) '--text' $txt '--write-media' $out 2>$null | Out-Null
            }).AddArgument('python').AddArgument($vUse).AddArgument($rUse).AddArgument($pUse).AddArgument($text).AddArgument($mp3)
            $script:ttsPS = $ps
            $script:ttsHandle = $ps.BeginInvoke()
            $script:ttsMode = 'thread'
            $script:ttsMp3 = $mp3
            $script:ttsVoiceUsed = $vUse
            $script:ttsText = $text
            $script:ttsTimer.Start()
            Write-Err ('TTS-EDGE-START len=' + $text.Length + ' voice=' + $vUse + ' mode=thread')
            return
        } catch { Write-Err ('TTS-EDGE-ERR ' + $_.Exception.Message) }
    }
    Speak-Sapi $text
}

# 从状态文件里取某请求的结果：只认以换行结尾的完整行，避免并发追加时读到半行
function Get-TtsStatusHit([string]$rid) {
    try {
        $path = $script:ttsStatusFile
        if (-not $path -or -not (Test-Path $path)) { return $null }
        $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $all = $sr.ReadToEnd()
        } finally { try { $sr.Dispose() } catch { }; $fs.Dispose() }
        if (-not $all) { return $null }
        $parts = $all -split "`n"
        $tail = $parts[$parts.Count - 1]
        if ($tail -ne '') { $parts = $parts[0..($parts.Count - 2)] }   # 末尾没有换行 → 丢弃可能是半行的那条
        $ping = $parts | Where-Object { $_ -and $_.StartsWith($rid + ' ') } | Select-Object -Last 1
        if ($ping) { return $ping.TrimEnd("`r") }
        return $null
    } catch { return $null }
}

# 流水线调度：边合成边播
$script:ttsTimer = New-Object System.Windows.Forms.Timer
$script:ttsTimer.Interval = 90
$script:ttsTimer.Add_Tick({
    # ---- 常驻进程 + 分段流水线 ----
    if ($script:ttsMode -eq 'worker' -and $script:ttsSegs.Count -gt 0) {
        # 1) 扫状态文件，标记完成的分段
        for ($i = 0; $i -lt $script:ttsSegs.Count; $i++) {
            if ($script:ttsSegDone[$i] -or -not $script:ttsSegReq[$i]) { continue }
            $rid = $script:ttsSegReq[$i]
            try {
                $hit = Get-TtsStatusHit $rid
            } catch { $hit = $null }
            # 请求丢失检测：6 秒还没有任何状态记录，按失败处理（会走下面的重试）
            # 超时按文本长度动态给：短句 8 秒，长句最多 30 秒（worker 端并发排队也要算进去）
            $pendingN = 0
            for ($q3 = 0; $q3 -lt $script:ttsSegReq.Count; $q3++) { if ($script:ttsSegReq[$q3] -and -not $script:ttsSegDone[$q3]) { $pendingN++ } }
            # 超时 = 基础 8 秒 + 文本长度 + 队列里每个未完成请求 2 秒（并发排队也要算进去）
            $waitSec = 12 + [Math]::Min(30, [int]($script:ttsSegs[$i].Length * 0.08)) + ($pendingN * 3)
            if (-not $hit -and $script:ttsSegReqAt -and $script:ttsSegReqAt.Count -gt $i -and $script:ttsSegReqAt[$i] -and ((Get-Date) - $script:ttsSegReqAt[$i]).TotalSeconds -gt $waitSec) {
                Write-Err ('TTS-SEG-TIMEOUT idx=' + $i)
                $hit = 'TIMEOUT'
            }
            if ($hit) {
                if ($hit -like ('*' + $rid + ' OK*')) {
                    # worker 返回的是转好的 WAV 路径；解析出来直接播放，主程序不再调 ffmpeg
                    $script:ttsSegOut[$i] = ($hit -replace ('^' + [regex]::Escape($rid) + ' OK '), '').Trim()
                    # worker 已读完请求文件，删掉避免累积（压测里 460+ 个残留）
                    try { Remove-Item -LiteralPath (Join-Path $env:TEMP ('fish-tts-req-' + $rid + '.json')) -Force -ErrorAction SilentlyContinue } catch { }
                    $script:ttsSegDone[$i] = $true
                    $script:ttsOffline = $false
                }
                else {
                    Write-Err ('TTS-SEG-FAIL idx=' + $i)
                    # 合成失败也要立刻放开“正在说话”的锁，否则耳朵会被挡住整整一个看门狗周期
                    $script:speakEndAt = (Get-Date)
                    if ($null -eq $script:ttsRetry) { $script:ttsRetry = @{} }
                    if (-not $script:ttsRetry[[string]$i]) {
                        # 失败自动重试一次：换新请求 id 再合成
                        $script:ttsRetry[[string]$i] = 1
                        # 换全新的输出文件：旧请求可能还在跑，共用同一路径会互相覆盖
                        $script:ttsSegFiles[$i] = Join-Path $env:TEMP ('fish-tts-' + [guid]::NewGuid().ToString('N') + '.mp3')
                        $script:ttsSegWav[$i] = [IO.Path]::ChangeExtension($script:ttsSegFiles[$i], '.wav')
                        $script:ttsSegOut[$i] = ''
                        $script:ttsSegReq[$i] = ''
                        $script:ttsSegDone[$i] = $false
                    } else {
                        $script:ttsSegDone[$i] = $true
                        # 断网/edge 不可用：用本机语音把这段念出来，别让鱼哑巴
                        $segText = [string]$script:ttsSegs[$i]
                        if ($segText) {
                            try { Speak-Sapi $segText; Write-Err ('TTS-SAPI-FALLBACK len=' + $segText.Length) } catch { }
                        }
                        $script:ttsOffline = $true
                        $script:ttsOfflineAt = Get-Date
                    }
                }
            }
        }
        # 2) 没有在播 → 找下一段
        if ($script:ttsSegPlaying -lt 0) {
            $next = -1
            for ($i = 0; $i -lt $script:ttsSegs.Count; $i++) { if (-not $script:ttsSegPlayed[$i]) { $next = $i; break } }
            if ($next -lt 0) {
                $script:ttsTimer.Stop()
                $script:ttsSegs = @()
                return
            }
            if ($script:ttsSegDone[$next]) {
                $file = if ($script:ttsSegOut -and $script:ttsSegOut.Count -gt $next -and $script:ttsSegOut[$next]) { $script:ttsSegOut[$next] } else { $script:ttsSegFiles[$next] }
                if ((Test-Path $file) -and (Get-Item $file).Length -gt 800) {
                    $script:ttsSegPlaying = $next
                    $ok = Play-TtsFile $file $script:ttsVoiceUsed
                    # playback failure must reset the pipeline, otherwise TTS stays busy forever
                    if (-not $ok) { Complete-TtsSegment }
                } else {
                    $script:ttsSegPlayed[$next] = $true
                }
            } elseif (-not $script:ttsSegReq[$next]) {
                Request-TtsSegment $next
                # 并发预取：一次把后面 2 段也发出去，worker 会并行合成
                for ($q = 1; $q -le 2; $q++) {
                    $nq = $next + $q
                    if ($nq -lt $script:ttsSegs.Count -and -not $script:ttsSegDone[$nq] -and -not $script:ttsSegReq[$nq]) { Request-TtsSegment $nq }
                }
            }
        } else {
            # 3) 正在播：到点视为播完（SoundPlayer 无结束事件），再预取下一段
            if ((-not $script:playUntil) -or ((Get-Date) -ge $script:playUntil)) {
                Complete-TtsSegment
            } else {
                # 播放中继续往后预取 2 段（worker 最多 4 路并发，够用）
                for ($q2 = 1; $q2 -le 2; $q2++) {
                    $nx = $script:ttsSegPlaying + $q2
                    if ($nx -lt $script:ttsSegs.Count -and -not $script:ttsSegDone[$nx] -and -not $script:ttsSegReq[$nx]) { Request-TtsSegment $nx }
                }
            }
        }
        return
    }
    # ---- 后台线程整段模式 ----
    if ($null -eq $script:ttsHandle) { $script:ttsTimer.Stop(); return }
    if (-not $script:ttsHandle.IsCompleted) { return }
    $script:ttsTimer.Stop()
    $ps = $script:ttsPS; $h = $script:ttsHandle; $mp3 = $script:ttsMp3; $v = $script:ttsVoiceUsed; $tx = $script:ttsText
    $script:ttsHandle = $null; $script:ttsPS = $null
    try { [void]$ps.EndInvoke($h) } catch { Write-Err ('TTS-JOIN-ERR ' + $_.Exception.Message) }
    try { $ps.Dispose() } catch { }
    try {
        if ((Test-Path $mp3) -and (Get-Item $mp3).Length -gt 2000) { Play-TtsFile $mp3 $v }
        else { Speak-Sapi $tx }
    } catch { Write-Err ('TTS-DONE-ERR ' + $_.Exception.Message) }
})
