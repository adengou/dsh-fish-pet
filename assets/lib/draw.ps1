# ============================================================
# draw.ps1 — 画鱼（GDI+ 逐帧绘制）
# 依赖声明（自动生成，勿手改）：见 tools\add-module-headers.py 输出
# ============================================================

function New-Solid([string]$hex, [int]$a = 255) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    return New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B))
}

function New-Pen([string]$hex, [float]$w, [int]$a = 255) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $p = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B), $w)
    $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    return $p
}

# 颜色卡（蓝白配色）
$C_OUTLINE = '#1B3B5F'
$C_BODY1   = '#9FD9FF'
$C_BODY2   = '#3F8FD8'
$C_BELLY   = '#EAF7FF'
$C_FIN1    = '#BDE5FF'
$C_FIN2    = '#5EA9E6'
$C_CHEEK   = '#FF9BB4'
$C_EYEWHITE= '#FFFFFF'
$C_PUPIL   = '#132A45'

# ---------- 读档 ----------
$script:st = @{ x = $null; y = $null; dir = 1; scale = 1.0; feeds = 0; hunger = 30; intimacy = 10; mood = 'normal'; seen = $null; lastFeedAt = $null }
if (Test-Path $StatePath) {
    try {
        $j = Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $j.x) { $script:st.x = [int]$j.x }
        if ($null -ne $j.y) { $script:st.y = [int]$j.y }
        if ($null -ne $j.dir) { $script:st.dir = [int]$j.dir }
        if ($null -ne $j.scale) { $script:st.scale = [double]$j.scale }
        if ($null -ne $j.feeds) { $script:st.feeds = [int]$j.feeds }
        if ($null -ne $j.hunger) { $script:st.hunger = [double]$j.hunger }
        if ($null -ne $j.intimacy) { $script:st.intimacy = [double]$j.intimacy }
        if ($null -ne $j.mood) { $script:st.mood = [string]$j.mood }
        if ($null -ne $j.seen) { $script:st.seen = [string]$j.seen }
        if ($null -ne $j.lastFeedAt) { $script:st.lastFeedAt = [string]$j.lastFeedAt }
    } catch { }
}

function Draw-Fish {
    param(
        [System.Drawing.Graphics]$g,
        [double]$t, [int]$dir, [double]$scale, [double]$pulse,
        [bool]$blink, [int]$mood, [string]$expr = 'normal'
    )

    $g.Clear([System.Drawing.Color]::Transparent)

    $bob   = [Math]::Sin($t * 1.7) * 3.5
    $sway  = [Math]::Sin($t * 3.4) * 11.0
    $up    = [Math]::Sin($t * 2.1) * 2.0
    $s     = $scale * $pulse

    $g.ResetTransform()
    $g.TranslateTransform(160.0, 130.0)
    $g.ScaleTransform([float]($s * $dir), [float]$s)
    $g.TranslateTransform(-160.0, -130.0 + [float]$bob)

    # ---- 尾鳍（绕 86,130 摆动）----
    $stateTail = $g.Save()
    $g.TranslateTransform(86.0, 130.0)
    $g.RotateTransform([float]$sway)
    $g.TranslateTransform(-86.0, -130.0)
    $tail = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tail.AddBezier(88, 122, 52, 96, 22, 52, 12, 44)
    $tail.AddBezier(12, 44, 30, 96, 40, 118, 40, 130)
    $tail.AddBezier(40, 130, 40, 142, 30, 164, 12, 216)
    $tail.AddBezier(12, 216, 22, 208, 52, 164, 88, 138)
    $tail.CloseFigure()
    $tailBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(12, 60)), (New-Object System.Drawing.Point(90, 150)),
        [System.Drawing.ColorTranslator]::FromHtml($C_FIN1), [System.Drawing.ColorTranslator]::FromHtml($C_FIN2))
    $g.FillPath($tailBrush, $tail)
    $tailPen = New-Pen $C_OUTLINE 3.2
    $g.DrawPath($tailPen, $tail)
    $tailBrush.Dispose(); $tailPen.Dispose(); $tail.Dispose()
    $g.Restore($stateTail)

    # ---- 背鳍 ----
    $dorsal = New-Object System.Drawing.Drawing2D.GraphicsPath
    $dorsal.AddBezier(152, 74, 172, 34, 198, 24, 214, 56)
    $dorsal.AddBezier(214, 56, 196, 68, 176, 76, 170, 82)
    $dorsal.CloseFigure()
    $g.FillPath((New-Solid $C_FIN2 235), $dorsal)
    $g.DrawPath((New-Pen $C_OUTLINE 2.6), $dorsal)
    $dorsal.Dispose()

    # ---- 身体（大肥）----
    $body = New-Object System.Drawing.Drawing2D.GraphicsPath
    $body.AddEllipse(70, 60, 180, 140)
    $bodyBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(150, 58)), (New-Object System.Drawing.Point(150, 202)),
        [System.Drawing.ColorTranslator]::FromHtml($C_BODY1), [System.Drawing.ColorTranslator]::FromHtml($C_BODY2))
    $g.FillPath($bodyBrush, $body)

    # 肚子
    $belly = New-Object System.Drawing.Drawing2D.GraphicsPath
    $belly.AddEllipse(96, 112, 140, 82)
    $g.FillPath((New-Solid $C_BELLY 210), $belly)

    # 高光
    $shine = New-Object System.Drawing.Drawing2D.GraphicsPath
    $shine.AddEllipse(104, 74, 66, 26)
    $g.FillPath((New-Solid '#FFFFFF' 70), $shine)

    # 身体轮廓
    $g.DrawPath((New-Pen $C_OUTLINE 3.4), $body)
    $body.Dispose(); $belly.Dispose(); $shine.Dispose(); $bodyBrush.Dispose()

    # ---- 胸鳍（贴在下腹边缘，随游动轻摆）----
    $stateFin = $g.Save()
    $g.TranslateTransform(146.0, 170.0)
    $g.RotateTransform([float](-34 + [Math]::Sin($t * 4.2) * 8))
    $g.TranslateTransform(-24.0, -10.0)
    $g.FillEllipse((New-Solid $C_FIN1 245), (New-Object System.Drawing.RectangleF(0, 0, 48, 20)))
    $g.DrawEllipse((New-Pen $C_OUTLINE 2.4), (New-Object System.Drawing.RectangleF(0, 0, 48, 20)))
    $g.Restore($stateFin)

    # ---- 鳃线 ----
    $gill = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gill.AddBezier(176, 94, 188, 114, 188, 150, 174, 172)
    $g.DrawPath((New-Pen '#3F86C4' 2.2 150), $gill)
    $gill.Dispose()

    # ---- 眼睛（随心情变化）----
    if ($expr -eq 'happy') {
        if ($blink) {
            # 开心时也要眨眼
            $bp2 = New-Pen $C_PUPIL 3.6
            $g.DrawArc($bp2, 199, 104, 34, 20, 200, 140)
            $bp2.Dispose()
        } else {
            $g.FillEllipse((New-Solid $C_EYEWHITE), 199, 93, 34, 34)
            $g.FillEllipse((New-Solid $C_PUPIL), 207, 101, 20, 20)
            $g.FillEllipse((New-Solid '#FFFFFF' 255), 219, 100, 8, 8)
            $g.FillEllipse((New-Solid '#FFFFFF' 200), 211, 113, 6, 6)
        }
    } elseif ($expr -eq 'sad') {
        # 委屈：眼睛半垂 + 一滴泪
        $g.FillEllipse((New-Solid $C_EYEWHITE), 199, 95, 34, 30)
        $g.FillEllipse((New-Solid $C_PUPIL), 208, 108, 18, 16)
        $g.FillEllipse((New-Solid '#FFFFFF' 235), 218, 106, 6, 6)
        $lid = New-Pen $C_PUPIL 3.0
        $g.DrawArc($lid, 199, 88, 34, 22, 200, 140)
        $lid.Dispose()
        $g.FillEllipse((New-Solid '#7FC7F0' 200), 206, 128, 7, 11)
    } elseif ($expr -eq 'angry') {
        # 生气：眼睛压低 + 斜眉
        $g.FillEllipse((New-Solid $C_EYEWHITE), 199, 97, 34, 30)
        $g.FillEllipse((New-Solid $C_PUPIL), 207, 106, 20, 18)
        $g.FillEllipse((New-Solid '#FFFFFF' 235), 219, 105, 6, 6)
        $brow = New-Pen $C_OUTLINE 3.2
        $g.DrawLine($brow, 197, 86, 232, 94)
        $brow.Dispose()
    } elseif ($blink) {
        $blinkPen = New-Pen $C_PUPIL 3.6
        $g.DrawArc($blinkPen, 199, 104, 34, 20, 200, 140)
        $blinkPen.Dispose()
    } else {
        $g.FillEllipse((New-Solid $C_EYEWHITE), 199, 93, 34, 34)
        $g.FillEllipse((New-Solid $C_PUPIL), 207, 101, 20, 20)
        $g.FillEllipse((New-Solid '#FFFFFF' 235), 219, 100, 7, 7)
        $g.FillEllipse((New-Solid '#FFFFFF' 110), 211, 113, 5, 5)
    }

    # ---- 腮红 ----
    $g.FillEllipse((New-Solid $C_CHEEK 95), 202, 140, 30, 20)

    # ---- 嘴 ----
    $mouthPen = New-Pen $C_OUTLINE 2.8
    if ($mood -eq 1) {
        $g.FillEllipse((New-Solid '#C9526B'), 236, 128, 16, 12)
        $mouthPen.Dispose()
        $mouthPen = New-Pen $C_OUTLINE 2.2
        $g.DrawEllipse($mouthPen, 236, 128, 16, 12)
    } else {
        $g.DrawArc($mouthPen, 236, 126, 20, 16, 338, 200)
    }
    $mouthPen.Dispose()

    # ---- 泡泡 ----
    foreach ($b in @($script:bubbles)) {
        $bx = 250 + [Math]::Sin($b.seed + $b.age * 2.2) * 8
        $by = 128 - $b.age * 46
        $r  = 5 + $b.size
        $al = [int](180 * [Math]::Max(0, 1 - $b.age / $b.life))
        if ($al -gt 0) {
            $g.FillEllipse((New-Solid '#CFEFFF' ([Math]::Min(255, $al))), ($bx - $r), ($by - $r), (2 * $r), (2 * $r))
            $g.DrawEllipse((New-Pen '#9FD8F5' 1.4 $al), ($bx - $r), ($by - $r), (2 * $r), (2 * $r))
        }
    }

    # ---- 爱心 ----
    foreach ($h in @($script:hearts)) {
        $al = [int](230 * [Math]::Max(0, 1 - $h.age / $h.life))
        if ($al -le 6) { continue }
        $hx = 160 + $h.dx
        $hy = 70 - $h.age * 42 + [Math]::Sin($h.age * 5) * 2
        $k  = 1.0 + $h.age * 0.5
        $heart = New-Object System.Drawing.Drawing2D.GraphicsPath
        $heart.AddBezier($hx, $hy + 8 * $k, $hx - 14 * $k, $hy - 6 * $k, $hx - 6 * $k, $hy - 16 * $k, $hx, $hy - 7 * $k)
        $heart.AddBezier($hx, $hy - 7 * $k, $hx + 6 * $k, $hy - 16 * $k, $hx + 14 * $k, $hy - 6 * $k, $hx, $hy + 8 * $k)
        $heart.CloseFigure()
        $g.FillPath((New-Solid '#FF5C8A' $al), $heart)
        $heart.Dispose()
    }

    $g.ResetTransform()
}

# ---------- 窗口 ----------
$form = New-Object FishPetWindow
            if ([int]$script:x -ne $script:lastPx -or [int]$script:y -ne $script:lastPy) { $form.SetBounds([int]$script:x, [int]$script:y, $W, $H); $script:lastPx = [int]$script:x; $script:lastPy = [int]$script:y }

$form.Show()
$form.ShowNow()
$form.AllowDrop = $true
$form.Add_DragEnter({
    param($s, $e)
    try {
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy } else { $e.Effect = [System.Windows.Forms.DragDropEffects]::None }
    } catch { }
})
$form.Add_DragDrop({
    param($s, $e)
    try {
        $files = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
        if ($files.Count -gt 0) { Handle-DroppedFile ([string]$files[0]) }
    } catch { Write-Err ('DROP-ERR ' + $_.Exception.Message) }
})
$form.BringToFront()
$pidJson = [ordered]@{ pid = $PID; startedAt = (Get-Date).ToString('o'); script = $PSCommandPath } | ConvertTo-Json -Compress
[IO.File]::WriteAllText($PidPath, $pidJson, (New-Object Text.UTF8Encoding($false)))

# 自检用：启动 1.5 秒后自动说一句（-Say "..."），方便无人工验证聊天链路
if ($Say) {
    $script:sayText = $Say
    $script:sayTimer = New-Object System.Windows.Forms.Timer
    $script:sayTimer.Interval = 1500
    $script:sayTimer.Add_Tick({ $script:sayTimer.Stop(); Start-Chat $script:sayText })
    $script:sayTimer.Start()
}
# 耳朵在后台独立跑（asr-listener.ps1），鱼只读结果，不再自己占麦克风
$script:asrFile = Join-Path $DataDir 'asr.log'
$script:asrPos = 0
