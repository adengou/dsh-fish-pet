# ============================================================
# live.ps1 — 直播模式（舞台背景 + 节目单调度）
# 依赖（主脚本提供）：Show-Bubble / Speak-Text / Get-MusicLib / Start-Music / Test-MusicBusy
#   $script: cfg / liveOn / liveNextAt / liveStage
# ============================================================

function Start-LiveStage {
    # 全屏舞台背景：给 OBS 做屏幕捕获用，省得处理分层窗口透明
    try {
        if ($script:liveStage) { return $true }
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'
        $f.StartPosition = 'Manual'
        $f.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $f.BackColor = [System.Drawing.Color]::FromArgb(18, 26, 44)
        $f.TopMost = $false
        $f.ShowInTaskbar = $false
        $f.DoubleBuffered = $true
        $f.Add_Paint({
            param($s, $e)
            try {
                $g = $e.Graphics
                $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
                $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
                    [System.Drawing.Color]::FromArgb(18, 26, 44),
                    [System.Drawing.Color]::FromArgb(40, 60, 96),
                    45)
                $g.FillRectangle($brush, 0, 0, $w, $h)
                $brush.Dispose()
                $font = New-Object System.Drawing.Font('Microsoft YaHei', 20)
                $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 150, 200))
                $g.DrawString('大肥鱼 · 直播间', $font, $tb, [int]($w / 2 - 110), [int]($h - 90))
                $font.Dispose(); $tb.Dispose()
            } catch { }
        })
        $f.Show()
        # 压到最底层，让鱼在上面
        $f.SendToBack()
        $script:liveStage = $f
        Write-Err 'LIVE-STAGE-ON'
        return $true
    } catch { Write-Err ('LIVE-STAGE-ERR ' + $_.Exception.Message); return $false }
}

function Stop-LiveStage {
    try {
        if ($script:liveStage) { $script:liveStage.Close(); $script:liveStage.Dispose() }
    } catch { }
    $script:liveStage = $null
    Write-Err 'LIVE-STAGE-OFF'
}

function Start-Live {
    $script:liveOn = $true
    $script:liveNextAt = (Get-Date).AddSeconds(8)
    Start-LiveStage | Out-Null
    try { Show-Bubble '直播模式开啦，本鱼自己表演～' } catch { }
    Write-Err 'LIVE-ON'
    return $true
}

function Stop-Live {
    $script:liveOn = $false
    Stop-LiveStage
    try { Show-Bubble '直播结束啦，主人辛苦～' } catch { }
    Write-Err 'LIVE-OFF'
    return $true
}

function Get-LivePoemLine {
    try {
        $lib = Get-PoemData
        if (-not $lib -or -not $lib.poems -or $lib.poems.Count -eq 0) { return $null }
        $p = $lib.poems[(Get-Random -Maximum $lib.poems.Count)]
        $lines = @()
        if ($p.lines) { $lines = @($p.lines) } elseif ($p.content) { $lines = @([string]$p.content -split "`r?`n") }
        $lines = @($lines | Where-Object { $_ -and $_.Trim() })
        if ($lines.Count -eq 0) { return $null }
        $body = ($lines | Select-Object -First 2) -join '，'
        return ($p.title + '，' + [string]$p.author + '。' + $body)
    } catch { return $null }
}

function Invoke-LiveTurn {
    # 一个节目：60% 弹琴 / 30% 读诗 / 10% 报时（或整点必报时）
    try {
        if (-not $script:liveOn) { return }
        $now = Get-Date
        $roll = Get-Random -Minimum 0 -Maximum 100
        if ($now.Minute -eq 0 -and $now.Second -lt 40) {
            $say = ('现在是' + $now.ToString('H点mm分') + '，本鱼陪主人值班中～')
            try { Speak-Text $say } catch { }
            $script:liveNextAt = $now.AddSeconds(35)
            Write-Err 'LIVE-TURN time'
            return
        }
        if ($roll -lt 60) {
            if (-not (Test-MusicBusy)) {
                $lib = @(Get-MusicLib)
                if ($lib.Count -gt 0) {
                    $song = $lib[(Get-Random -Maximum $lib.Count)]
                    Start-Music $song.name | Out-Null
                    Write-Err ('LIVE-TURN music ' + $song.name)
                    $script:liveNextAt = $now.AddSeconds(90)
                    return
                }
            }
            $script:liveNextAt = $now.AddSeconds(15)
            return
        }
        if ($roll -lt 90) {
            $text = Get-LivePoemLine
            if ($text) {
                try { Show-Bubble $text } catch { }
                try { Speak-Text $text } catch { }
                Write-Err ('LIVE-TURN poem')
                $script:liveNextAt = $now.AddSeconds(25)
                return
            }
        }
        try { Show-Bubble '本鱼在水里游着呢～' } catch { }
        $script:liveNextAt = $now.AddSeconds(20)
    } catch { Write-Err ('LIVE-TURN-ERR ' + $_.Exception.Message) }
}

function Update-Live {
    if (-not $script:liveOn) { return }
    if (-not $script:liveNextAt) { $script:liveNextAt = (Get-Date).AddSeconds(10) }
    if ((Get-Date) -lt $script:liveNextAt) { return }
    Invoke-LiveTurn
}

$script:liveOn = $false
$script:liveStage = $null
$script:liveNextAt = $null
