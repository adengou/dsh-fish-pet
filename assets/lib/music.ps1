# ============================================================
# music.ps1 — 奏乐（曲库 / 简谱合成 / MIDI 渲染 / 播放）
# 依赖声明（自动生成，勿手改）：
#   主脚本提供: Show-Bubble, Write-Err
#   $script 变量: FishAssets, musicAt, musicLib, musicOut, musicPendingLyrics, musicPlayer, musicProc, musicQueue, musicSing, musicSong, musicUntil, poemData, speakEndAt
#   被其他模块调用: Find-Poem() ← chat.ps1; Test-MusicBusy() ← chat.ps1
# ============================================================

# music.ps1 · 诗歌 / 奏乐模块（从主脚本拆出）
# 本文件在 assets\lib 下，用 $script:FishAssets 指向 assets 根目录
$script:FishAssets = Split-Path -Parent $PSScriptRoot

function Get-PoemData {
    if ($script:poemData) { return $script:poemData }
    try {
        $f = Join-Path $script:FishAssets 'data\poems.json'
        if (-not (Test-Path $f)) { Write-Err 'POEM-DATA-MISSING'; return $null }
        $script:poemData = ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json).poems
        Write-Err ('POEM-LOAD ' + $script:poemData.Count)
    } catch { Write-Err ('POEM-LOAD-ERR ' + $_.Exception.Message); $script:poemData = $null }
    return $script:poemData
}
function Find-Poem([string]$q) {
    $all = Get-PoemData
    if (-not $all -or $all.Count -eq 0) { return $null }
    foreach ($it in $all) { if ($it.title -and $q.Contains([string]$it.title)) { return $it } }
    foreach ($it in $all) { if ($it.author -and $q.Contains([string]$it.author)) { return $it } }
    return $all[(Get-Random -Maximum $all.Count)]
}

# ---------- 弹琴：乐谱合成 WAV 后播放 ----------
$script:musicLib = $null
function Get-MusicLib {
    if ($script:musicLib) { return $script:musicLib }
    try {
        $f = Join-Path $script:FishAssets 'data\melodies.json'
        if (-not (Test-Path $f)) { return $null }
        $script:musicLib = ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json).songs

        # 目录里的 MIDI 也算曲目：data\midi\*.mid，文件名即曲名
        try {
            foreach ($dir2 in @((Join-Path $script:FishAssets 'data\midi'), (Join-Path $DataDir 'midi'))) {
                if (Test-Path $dir2) {
                    foreach ($mf in (Get-ChildItem $dir2 -Filter '*.mid' -File -ErrorAction SilentlyContinue)) {
                        $script:musicLib = @($script:musicLib) + @([pscustomobject]@{ name = $mf.BaseName; aliases = @(); bpm = 0; lyrics = '''' ; midi = $mf.FullName })
                    }
                }
            }
        } catch { }
        # 本机自定义曲目（主人自己加的，不进公开仓库）：data\melodies.local.json
        try {
             $lf = Join-Path $DataDir 'melodies.local.json'
            if (-not (Test-Path $lf)) { $lf = Join-Path $script:FishAssets 'data\melodies.local.json' }
            if (Test-Path $lf) {
                $extra = ([IO.File]::ReadAllText($lf, [Text.Encoding]::UTF8) | ConvertFrom-Json).songs
                if ($extra) { $script:musicLib = @($script:musicLib) + @($extra) }
            }
        } catch { }
    } catch { $script:musicLib = $null }
    return $script:musicLib
}
function Find-Song([string]$q) {
    $all = Get-MusicLib
    if (-not $all) { return $null }
    foreach ($s in $all) {
        if ($q -and $q.Contains([string]$s.name)) { return $s }
        foreach ($a in @($s.aliases)) { if ($a -and $q.Contains([string]$a)) { return $s } }
    }
    return $null
}
function Start-Music([string]$songName) {
    $lib = Get-MusicLib
    if (-not $lib -or $lib.Count -eq 0) { Show-Bubble '(music library missing)'; return $false }
    $song = Find-Song $songName
    if (-not $song) { return $false }
    $gen = Join-Path $script:FishAssets 'music_gen.py'
    if (-not (Test-Path $gen)) { Show-Bubble '(music generator missing)'; return $false }
    $out = Join-Path $env:TEMP ('fish-music-' + [guid]::NewGuid().ToString('N') + '.wav')
    try {
        # 有 MIDI 就用 MIDI 渲染（音准来自 MIDI 本身），否则用内置简谱合成
        if ($song.midi -and (Test-Path ([string]$song.midi))) {
            $mr = Join-Path $script:FishAssets 'midi_render.py'
            $arg = '"' + $mr + '" --midi "' + [string]$song.midi + '" --out "' + $out + '"'
        } else {
            $arg = '"' + $gen + '" --song "' + [string]$song.name + '" --out "' + $out + '" --library "' + (Join-Path $script:FishAssets 'data\melodies.json') + '"'
        }
        $script:musicProc = Start-Process -FilePath 'python' -ArgumentList $arg -WindowStyle Hidden -PassThru
        $script:musicOut = $out
        $script:musicAt = Get-Date
        $script:musicSong = $song
        $script:musicSing = ($songName -match '唱')
        Show-Bubble ('弹首《' + $song.name + '》给主人听～')
        Write-Err ('MUSIC-GEN ' + $song.name + ' pid=' + $script:musicProc.Id)
        return $true
    } catch { Write-Err ('MUSIC-ERR ' + $_.Exception.Message); return $false }
}
function Finish-Music {
    try {
        $out = $script:musicOut
        if (-not $out -or -not (Test-Path $out)) { $script:musicOut = $null; return }
        $len = (Get-Item $out).Length
        if ($len -lt 60000) { return }
        if ($null -eq $script:musicPlayer) { $script:musicPlayer = New-Object System.Media.SoundPlayer }
        $script:musicPlayer.SoundLocation = $out
        $script:musicPlayer.Play()
        $dur = $len / 88200.0
        $script:musicUntil = (Get-Date).AddSeconds($dur + 1.0)
        $script:speakEndAt = $script:musicUntil
        try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.talking'), '1') } catch { }
        if ($script:musicSong -and $script:musicSong.lyrics) { Show-Bubble ([string]$script:musicSong.lyrics) }
        Write-Err ('MUSIC-PLAY ' + $(if ($script:musicSong) { $script:musicSong.name } else { '?' }) + ' dur=' + [Math]::Round($dur, 1))
        # 唱模式：旋律播完再念歌词，避免两个声音叠在一起
        if ($script:musicSing -and $script:musicSong -and $script:musicSong.lyrics) { $script:musicPendingLyrics = [string]$script:musicSong.lyrics }
        $script:musicOut = $null
        $script:musicProc = $null
    } catch { Write-Err ('MUSIC-PLAY-ERR ' + $_.Exception.Message) }
}

function Stop-Music {
    try {
        if ($script:musicPlayer) { $script:musicPlayer.Stop() }
        if ($script:musicProc -and -not $script:musicProc.HasExited) { try { $script:musicProc.Kill() } catch { } }
        $script:musicOut = $null
        $script:musicProc = $null
        $script:musicUntil = $null
        $script:musicPendingLyrics = $null
        $script:speakEndAt = (Get-Date)
        Write-Err 'MUSIC-STOP'
        Show-Bubble '好嘛，人家不弹了～'
        return $true
    } catch { return $false }
}

function Test-MusicBusy {
    try {
        if ($script:musicProc -and -not $script:musicProc.HasExited) { return $true }
        if ($script:musicUntil -and (Get-Date) -lt $script:musicUntil) { return $true }
    } catch { }
    return $false
}
$script:musicQueue = @()   # 弹奏期间收到的对话，弹完再处理
function Request-Music([string]$songName) {
    # 正在弹或正在合成时，排队而不是打断
    if (Test-MusicBusy) {
        $script:musicQueue = @($script:musicQueue) + @($songName)
        Show-Bubble '这首还没弹完，排后面去～'
        Write-Err ('MUSIC-DEFER ' + $songName)
        return $true
    }
    return (Start-Music $songName)
}

