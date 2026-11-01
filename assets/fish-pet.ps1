# ============================================================
#  桌面蓝鱼 (Desktop Blue Fish) - DSH 插件版
#  WinForms layered window + GDI+ 逐帧绘制，无外部依赖。
#  左键拖动 / 单击喂食，右键菜单。
# ============================================================

param(
    [double]$Scale = 0.0,
    [int]$Speed = 0,
    [string]$Say = '',
    [switch]$Listen
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
Add-Type -AssemblyName System.Drawing

# 单实例：系统互斥量（比 pid 文件可靠，彻底防双开）
$__pidFile = Join-Path (Join-Path $env:USERPROFILE '.dsh\fish-pet') 'pet.pid'
try {
    $__mutex = New-Object System.Threading.Mutex($false, 'Global\dsh-fish-pet-single')
    $__got = $false
    try { $__got = $__mutex.WaitOne(0, $false) } catch { $__got = $false }
    if (-not $__got) { exit 0 }
} catch { }
# 写 pid，供耳朵/守护识别
try {
    New-Item -ItemType Directory -Force -Path (Split-Path $__pidFile) | Out-Null
    $__json = [ordered]@{ pid = $PID; startedAt = (Get-Date).ToString('o'); script = $PSCommandPath } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($__pidFile, $__json, (New-Object Text.UTF8Encoding($false)))
} catch { }

# 异常兜底：不允许 WinForms 弹「未处理异常」模态框（那就是闪退现场）
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $eventArgs)
        $line = (Get-Date -Format 'HH:mm:ss') + '  THREAD-EXC  ' + $eventArgs.Exception.Message
        try { Add-Content -LiteralPath (Join-Path $env:USERPROFILE '.dsh\fish-pet\error.log') -Value $line -Encoding UTF8 } catch { }
    })
} catch { }

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $env:USERPROFILE '.dsh\fish-pet'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
try { Remove-Item (Join-Path $DataDir 'asr.stop') -Force -ErrorAction SilentlyContinue } catch { }
$StatePath = Join-Path $DataDir 'state.json'
$ConfigPath = Join-Path $DataDir 'config.json'
function Load-Config {
    $def = [ordered]@{
        persona = [ordered]@{ name = '大肥鱼'; nameEn = 'Mia'; dad = '光光'; mom = '丽丽'; birthday = '2026年10月30日'; birthplace = '中国广西北海'; likes = '白饭、被摸头、主人夸它'; dislikes = '被说胖、被冷落、吵'; ownerBirthday = ''; lang = 'auto'; extra = '你说话简短、俏皮、微微傲娇，用中文，称呼用户为"主人"，每次回复不超过30个字，不要用表情符号。' }
        bubble  = [ordered]@{ opacity = 0.15 }
        voice   = [ordered]@{ silenceGate = 1200; boost = 1; engine = 'cloud'; localConf = 0.55 }
        tts     = [ordered]@{ engine = 'edge'; voice = 'zh-CN-XiaoxiaoNeural'; rate = '+12%'; pitch = '+10Hz'; voiceEn = 'en-US-AnaNeural'; rateEn = '+8%'; pitchEn = '+15Hz' }
        ui      = [ordered]@{ lang = 'zh' }
    }
    $script:cfg = $def
    try {
        if (-not (Test-Path $ConfigPath)) {
            [IO.File]::WriteAllText($ConfigPath, ($def | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
        }
        $j = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($j.persona) { foreach ($k in @('name','nameEn','dad','mom','extra','birthday','birthplace','likes','dislikes','ownerBirthday','lang')) { $v = $j.persona.$k; if ($v) { $script:cfg.persona[$k] = [string]$v } } }
        if ($j.bubble -and $j.bubble.opacity) { $script:cfg.bubble.opacity = [double]$j.bubble.opacity }
        if ($j.ui -and $j.ui.lang) { $script:cfg.ui.lang = [string]$j.ui.lang }
        if ($j.tts) { foreach ($k2 in @('engine','voice','rate','pitch','voiceEn','rateEn','pitchEn')) { $v2 = $j.tts.$k2; if ($v2) { $script:cfg.tts[$k2] = [string]$v2 } } }
        if ($j.voice) {
            if ($j.voice.silenceGate) { $script:cfg.voice.silenceGate = [int]$j.voice.silenceGate }
            if ($j.voice.boost) { $script:cfg.voice.boost = [int]$j.voice.boost }
        }
    } catch { $script:cfg = $def }
}
Load-Config
$script:ttsEngine = $script:cfg.tts.engine
# 启动自检：edge 音色需要 Python + edge-tts，缺了就退回本机语音并提示
$script:ttsWarn = $false
if ($script:ttsEngine -eq 'edge') {
    $edgeOk = $false
    try {
        $null = & python -m edge_tts --version 2>$null
        if ($LASTEXITCODE -eq 0) { $edgeOk = $true }
    } catch { }
    if (-not $edgeOk) {
        $script:ttsEngine = 'sapi'
        $script:ttsWarn = $true
        Write-Err 'TTS-PY-MISSING（已退回本机 SAPI 语音）'
    }
}
$script:ttsVoice  = $script:cfg.tts.voice
$script:ttsVoiceEn = $script:cfg.tts.voiceEn
$script:ttsRateEn  = $script:cfg.tts.rateEn
$script:ttsPitchEn = $script:cfg.tts.pitchEn
$script:langMode   = $script:cfg.persona.lang
$script:uiLang     = $script:cfg.ui.lang
if (-not $script:uiLang) { $script:uiLang = 'zh' }
$script:ttsRate   = $script:cfg.tts.rate
$script:ttsPitch  = $script:cfg.tts.pitch
$PidPath   = Join-Path $DataDir 'pet.pid'
$ErrorPath = Join-Path $DataDir 'error.log'

# ---------- 分层窗口（逐像素 alpha，无锯齿毛边） ----------
$cs = @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class FishPetWindow : Form
{
    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE { public int cx; public int cy; }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct BLENDFUNCTION
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("user32.dll")] private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst,
        ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc,
        int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);

    private const int WS_EX_LAYERED    = 0x00080000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int ULW_ALPHA        = 0x00000002;

    public FishPetWindow()
    {
        this.FormBorderStyle = FormBorderStyle.None;
        this.ShowInTaskbar   = false;
        this.TopMost         = true;
        this.StartPosition   = FormStartPosition.Manual;
        this.Text            = "fish-pet";
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED | WS_EX_TOOLWINDOW;
            return cp;
        }
    }

    public void ShowNow()
    {
        // A task launched with -WindowStyle Hidden can keep the first window
        // hidden; force it visible and back to the top of the z-order.
        ShowWindow(this.Handle, 5);
        SetWindowPos(this.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002);
    }

    public void ReTop()
    {
        // 定期抢回最上层：浏览器（尤其 Edge/Chrome 的合成层）刷新时可能把窗口压下去
        if (!this.Visible) return;
        SetWindowPos(this.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
    }

    public void Push(Bitmap bmp, int x, int y)
    {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc    = CreateCompatibleDC(screenDc);
        IntPtr hBmp     = IntPtr.Zero;
        IntPtr old      = IntPtr.Zero;
        try
        {
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            old  = SelectObject(memDc, hBmp);

            POINT dst; dst.X = x; dst.Y = y;
            POINT src; src.X = 0; src.Y = 0;
            SIZE  size; size.cx = bmp.Width; size.cy = bmp.Height;

            BLENDFUNCTION blend;
            blend.BlendOp             = 0;
            blend.BlendFlags          = 0;
            blend.SourceConstantAlpha = 255;
            blend.AlphaFormat         = 1;

            UpdateLayeredWindow(this.Handle, screenDc, ref dst, ref size,
                memDc, ref src, 0, ref blend, ULW_ALPHA);
        }
        finally
        {
            if (old != IntPtr.Zero) SelectObject(memDc, old);
            if (hBmp != IntPtr.Zero) DeleteObject(hBmp);
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}
"@
Add-Type -TypeDefinition $cs -ReferencedAssemblies 'System.Drawing','System.Windows.Forms','System'

Add-Type -ReferencedAssemblies 'System.Drawing','System.Windows.Forms','System' -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class CoolMenuRenderer : ToolStripProfessionalRenderer
{
    public CoolMenuRenderer() : base(new ToolStripProfessionalRenderer().ColorTable) { this.RoundedEdges = true; }

    public static GraphicsPath RoundRect(Rectangle r, int radius)
    {
        var p = new GraphicsPath();
        int d = radius * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d - 1, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d - 1, r.Bottom - d - 1, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d - 1, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        var r = e.ToolStrip.ClientRectangle;
        if (r.Width <= 0 || r.Height <= 0) return;
        using (var b = new LinearGradientBrush(r, Color.FromArgb(26, 40, 72), Color.FromArgb(12, 22, 44), 90f))
            e.Graphics.FillRectangle(b, r);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        var r = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        using (var pen = new Pen(Color.FromArgb(110, 190, 255), 1f))
        using (var path = RoundRect(r, 12))
            e.Graphics.DrawPath(pen, path);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        var r = new Rectangle(4, 1, e.Item.Width - 8, e.Item.Height - 2);
        using (var path = RoundRect(r, 9))
        {
            using (var b = new LinearGradientBrush(r, Color.FromArgb(90, 190, 255), Color.FromArgb(40, 120, 210), 0f))
                e.Graphics.FillPath(b, path);
            using (var pen = new Pen(Color.FromArgb(150, 225, 255), 1f))
                e.Graphics.DrawPath(pen, path);
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Selected ? Color.White : Color.FromArgb(214, 232, 252);
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        using (var pen = new Pen(Color.FromArgb(70, 105, 150), 1f))
            e.Graphics.DrawLine(pen, 14, e.Item.Height / 2, e.Item.Width - 14, e.Item.Height / 2);
    }
}
"@

# ---------- 画布与初始状态 ----------
$W = 320; $H = 240
$bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

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

$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
function Get-DefaultX { return [int]($wa.Right - $W - 30) }
function Get-DefaultY { return [int]($wa.Bottom - $H - 10) }

$script:x      = if ($null -ne $script:st.x) { $script:st.x } else { Get-DefaultX }
$script:y      = if ($null -ne $script:st.y) { $script:st.y } else { Get-DefaultY }
# 位置兜底：别让鱼跑到屏幕外
$script:x = [Math]::Max(0, [Math]::Min([int]$script:x, [int]($wa.Right - $W)))
$script:y = [Math]::Max(0, [Math]::Min([int]$script:y, [int]($wa.Bottom - $H - 4)))
$script:baseY  = $script:y
$script:dir    = if ($script:st.dir -ne 0) { $script:st.dir } else { 1 }
$script:scale  = if ($Scale -gt 0) { $Scale } else { [double]$script:st.scale }
$script:speed  = if ($Speed -gt 0) { [double]$Speed } else { 26.0 }
$script:vx     = -$script:speed * $script:dir
$script:paused = $false
$script:dragging = $false
$script:dragMoved = 0
$script:dragOff = @{ x = 0; y = 0 }
$script:dragStart = @{ x = 0; y = 0 }
$script:dragActive = $false
$script:t      = 0.0
$script:pulse  = 1.0
    $script:tx = $null; $script:ty = $null; $script:pauseUntil = 0.0
    $script:lastPx = -9999; $script:lastPy = -9999
$script:satiety = 0.0
$script:feeds  = [int]$script:st.feeds
$script:lastFeedAtStr = $script:st.lastFeedAt
    # ---- 情绪状态：饥饿 / 亲密度 / 心情 ----
    $script:hunger   = [double]$script:st.hunger
    $script:intimacy = [double]$script:st.intimacy
    $script:mood     = [string]$script:st.mood
    if (-not $script:mood) { $script:mood = 'normal' }
    if ($script:st.seen) {
        try {
            $hoursAway = ((Get-Date) - [datetime]::Parse([string]$script:st.seen)).TotalHours
            if ($hoursAway -gt 0) {
                $script:hunger   = [Math]::Min(100, $script:hunger + $hoursAway * 3)
                $script:intimacy = [Math]::Max(0, $script:intimacy - $hoursAway * 0.5)
            }
        } catch { }
    }
    $script:birthdayMMDD = ''
    try { if ($script:cfg.persona.birthday -match '(\d{1,2})月(\d{1,2})日') { $script:birthdayMMDD = ('{0:D2}-{1:D2}' -f [int]$Matches[1], [int]$Matches[2]) } } catch { }
    $script:moodTick = Get-Date
    $script:moodUntil = $null
$script:bubbles = @()
$script:hearts  = @()
$script:nextBubbleAt = 0.0
$script:nextBlinkAt = 3.0
$script:blinkUntil = -1.0
$script:nextTurnAt = 9.0
$script:lastSave = Get-Date

# ---------- 画鱼 ----------
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
function Read-NewAsrLines {
    $res = @()
    try {
        if (-not (Test-Path $script:asrFile)) { return @() }
        $len = (Get-Item -LiteralPath $script:asrFile).Length
        if ($len -lt [int64]$script:asrPos) { $script:asrPos = 0; $script:asrRest = '' }
        if ($len -eq [int64]$script:asrPos) { return @() }
        $fs = [IO.File]::Open($script:asrFile, 'Open', 'Read', 'ReadWrite')
        [void]$fs.Seek([int64]$script:asrPos, 'Begin')
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $chunk = $sr.ReadToEnd()
        $script:asrPos = $fs.Position
        $sr.Dispose(); $fs.Dispose()
        $all = [string]$script:asrRest + $chunk
        $arr = $all -split "`n"
        $script:asrRest = [string]$arr[-1]
        if ($arr.Count -gt 1) {
            $res = @($arr[0..($arr.Count - 2)] | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ })
        }
    } catch { }
    return $res
}
$script:asrRest = ''
$script:asrPoll = 0
$script:earCheck = 0
function Start-Ear {
    try { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path (Split-Path -Parent $PSCommandPath) 'asr-listener.ps1')) -WindowStyle Hidden } catch { }
}
function Stop-Ear {
    try { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'asr-listener' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
}
$script:chatOn = $true

# ---------- 菜单 ----------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miFeed   = $menu.Items.Add('喂它一口')
$miType = $menu.Items.Add('打字说两句')
$miTalk   = $menu.Items.Add('开始听我说（麦克风）')
$miVoice  = $menu.Items.Add('语音朗读：开')
$miVoiceSet = New-Object System.Windows.Forms.ToolStripMenuItem('换个声音')
$menu.Items.Add($miVoiceSet) | Out-Null
$miChatLang = New-Object System.Windows.Forms.ToolStripMenuItem('聊天语言')
$langChoices = @(
    @('zh', '中文'),
    @('en', 'English'),
    @('auto', '自动模式')
)
$script:langItemMap = @{}
foreach ($lc in $langChoices) {
    $itL = New-Object System.Windows.Forms.ToolStripMenuItem($lc[1])
    $itL.Tag = $lc[0]
    $itL.CheckOnClick = $false
    $itL.Checked = ([string]$script:langMode -eq [string]$lc[0])
    $itL.Add_Click({
        param($s, $e)
        Set-LangMode ([string]$s.Tag) ([string]$s.Text)
    })
    $miChatLang.DropDownItems.Add($itL) | Out-Null
    $script:langItemMap[[string]$lc[0]] = $itL
}
$menu.Items.Add($miChatLang) | Out-Null

# 界面语言：只影响右键菜单文字，不动聊天语言
$miUiLang = New-Object System.Windows.Forms.ToolStripMenuItem('界面语言')
$uiChoices = @(
    @('zh', '中文'),
    @('en', 'English')
)
$script:uiItemMap = @{}
foreach ($uc in $uiChoices) {
    $itU = New-Object System.Windows.Forms.ToolStripMenuItem($uc[1])
    $itU.Tag = $uc[0]
    $itU.CheckOnClick = $false
    $itU.Checked = ([string]$script:uiLang -eq [string]$uc[0])
    $itU.Add_Click({
        param($s, $e)
        Set-UiLang ([string]$s.Tag) ([string]$s.Text)
    })
    $miUiLang.DropDownItems.Add($itU) | Out-Null
    $script:uiItemMap[[string]$uc[0]] = $itU
}
$menu.Items.Add($miUiLang) | Out-Null
$voiceChoices = @(
    @('zh-CN-XiaoyiNeural', '活泼少女·晓伊'),
    @('zh-CN-XiaoxiaoNeural', '温柔姐姐·晓晓'),
    @('zh-CN-liaoning-XiaobeiNeural', '东北话·小北'),
    @('zh-CN-shaanxi-XiaoniNeural', '陕西话·小妮'),
    @('zh-CN-YunxiNeural', '阳光男声·云希'),
    @('zh-CN-YunxiaNeural', '可爱男声·云夏')
)
$script:voiceItemMap = @{}
foreach ($vc in $voiceChoices) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem(($vc[1] + '（' + $vc[0] + '）'))
    $it.Tag = $vc[0]
    $it.CheckOnClick = $false
    $it.Checked = ([string]$script:ttsVoice -eq [string]$vc[0])
    $it.Add_Click({ 
        param($s, $e)
        $script:voicePickTag = [string]$s.Tag
        $script:voicePickLabel = [string]$s.Text
        Set-TtsVoice $script:voicePickTag $script:voicePickLabel
    })
    $miVoiceSet.DropDownItems.Add($it) | Out-Null
    $script:voiceItemMap[[string]$vc[0]] = $it
}
$miWake   = $menu.Items.Add('语音待命：开')
$miChat   = $menu.Items.Add('语音聊天：开')
$miBalance = $menu.Items.Add('余额：--')
$miPause  = $menu.Items.Add('停下歇会儿')
$miHome   = $menu.Items.Add('回到右下角')
$miBigger = $menu.Items.Add('长大一点')
$miSmall  = $menu.Items.Add('变小一点')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miRemind = $menu.Items.Add('加个提醒…')
$miRemindList = $menu.Items.Add('提醒清单…')
$miClear  = $menu.Items.Add('清除记忆…')
$miQuit   = $menu.Items.Add('让它游走（退出）')

function Save-State {
    $obj = [ordered]@{
        x = [int]$script:x; y = [int]$script:y; dir = [int]$script:dir
        scale = [Math]::Round($script:scale, 3); feeds = [int]$script:feeds
    hunger = [Math]::Round($script:hunger, 1); intimacy = [Math]::Round($script:intimacy, 1)
    mood = [string]$script:mood; seen = (Get-Date).ToString('o'); lastFeedAt = $script:lastFeedAtStr
    }
    try { ($obj | ConvertTo-Json -Compress) | Set-Content -Path $StatePath -Encoding UTF8 } catch { }
}

function Invoke-Feed {
    try {
        $script:feeds += 1
        $script:lastFeedAtStr = (Get-Date).ToString('o')
        $script:satiety += 1
        $script:hunger = [Math]::Max(0, $script:hunger - 30)
        $script:intimacy = [Math]::Min(100, $script:intimacy + 2)
        $script:mood = 'happy'
        $script:pulse = 1.16
        foreach ($dx in @(-26, 4, 30)) {
            $script:hearts += @{ dx = $dx; age = 0.0; life = 1.4 }
        }
        # 给个明显的反馈：气泡 + 说话
        $zhFeed = @('哼，就一口啊…再来一碗嘛', '白饭！主人最好了', '才、才不是为了你才吃的呢', '谢谢主人，鱼鱼吃饱了')
        $enFeed = @('Hmph, only one bite? More please.', 'Rice! You are the best, master.', 'I am NOT eating because of you, okay?', 'Thank you master, Fatty Fish is full.')
        $feedLine = ''
        $feedLang = $script:langMode
        if ($feedLang -eq 'auto') { try { $feedLang = Get-TextLang ([string]$script:lastUser) } catch { $feedLang = 'zh' } }
        if ($feedLang -eq 'en') { $feedLine = Get-Random -InputObject $enFeed } else { $feedLine = Get-Random -InputObject $zhFeed }
        Show-Bubble $feedLine
        # 正在说话时只冒泡，不插话（否则语音和喂食不搭调）
        $speechBusy = ($script:ttsSegPlaying -ge 0) -or (@($script:ttsSegs).Count -gt 0) -or ($null -ne $script:ttsHandle)
        if (-not $speechBusy) { try { Speak-Text $feedLine } catch { } }
        Save-State
    } catch {
        $line = (Get-Date -Format 'HH:mm:ss') + '  FEED-ERR  ' + $_.Exception.Message
        try { Add-Content -LiteralPath (Join-Path $env:USERPROFILE '.dsh\fish-pet\error.log') -Value $line -Encoding UTF8 } catch { }
    }
}

# ---------- 聊天：输入框 / 气泡 / 语音 ----------
$script:chatBusy  = $false
$script:chatPending = $null
$script:memPath = Join-Path $DataDir 'memory.json'
$script:memorySummary = ''
$script:summaryCount = 0
function Load-Memory {
    try {
        if (Test-Path $script:memPath) {
            $j = [IO.File]::ReadAllText($script:memPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($j.summary) { $script:memorySummary = [string]$j.summary }
            if ($j.history) {
                $script:chatHistory = @($j.history | ForEach-Object { @{ role = [string]$_.role; content = [string]$_.content } })
            }
        }
    } catch { }
}
# ---- 主人交代过的事（便签）----
$script:notesPath = Join-Path $DataDir 'notes.json'
function Load-Notes {
    try {
        if (Test-Path $script:notesPath) {
            $arr = [IO.File]::ReadAllText($script:notesPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            return @($arr)
        }
    } catch { }
    return @()
}
# 从一句话里解析提醒时间，解析不出就返回 $null
function Get-DueFromText([string]$s) {
    try {
        $now = Get-Date
        if ($s -match '(\d+)\s*分钟(后|以后|之后)') { return $now.AddMinutes([int]$Matches[1]) }
        if ($s -match '(\d+)\s*小时(后|以后|之后)') { return $now.AddHours([int]$Matches[1]) }
        $dayShift = 0
        if ($s -match '后天') { $dayShift = 2 } elseif ($s -match '明天|明早') { $dayShift = 1 }
        if ($s -match '(早上|上午|中午|下午|晚上)?\s*(\d{1,2})\s*[点:：]\s*(半|\d{1,2})?') {
            $perm = [string]$Matches[1]
            $h = [int]$Matches[2]
            $mm = 0
            if ($Matches[3] -eq '半') { $mm = 30 } elseif ($Matches[3]) { $mm = [int]$Matches[3] }
            if (($perm -eq '下午' -or $perm -eq '晚上') -and $h -lt 12) { $h += 12 }
            $due = (Get-Date).Date.AddDays($dayShift).AddHours($h).AddMinutes($mm)
            if ($dayShift -eq 0 -and $due -lt $now) { $due = $due.AddDays(1) }
            return $due
        }
    } catch { }
    return $null
}

function Save-Note([string]$text, $due = $null) {
    try {
        $arr = @(Load-Notes)
        $entry = @{ t = (Get-Date).ToString('yyyy-MM-dd HH:mm'); text = [string]$text }
        if ($due) { $entry.due = $due.ToString('o'); $entry.fired = $false }
        $arr += $entry
        if ($arr.Count -gt 20) { $arr = @($arr[($arr.Count - 20)..($arr.Count - 1)]) }
        [IO.File]::WriteAllText($script:notesPath, ($arr | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Save-Memory {
    try {
        $j = @{ history = $script:chatHistory; summary = $script:memorySummary; savedAt = (Get-Date).ToString('o') } | ConvertTo-Json -Depth 5 -Compress
        [IO.File]::WriteAllText($script:memPath, $j, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}
# 把最近对话压缩成长期记忆摘要
function Update-Summary {
    try {
        $k = Get-ApiKey
        if (-not $k) { return }
        $convo = (@($script:chatHistory | Select-Object -Last 16 | ForEach-Object { $(if ($_.role -eq 'user') { '主人' } else { '大肥鱼' }) + '：' + $_.content }) -join "`n")
        if (-not $convo) { return }
        $sys2 = '你在帮一条桌面宠物鱼整理长期记忆。把对话压缩成不超过80字的中文要点，只保留关于主人的事实（称呼、喜好、约定）和主人交代要记住的事。不要评论，不要加引号，只输出要点本身。'
        $old = $(if ($script:memorySummary) { $script:memorySummary } else { '（无）' })
        $u = '旧记忆：' + $old + "`n最近对话：`n" + $convo
        $body = @{ model = 'deepseek-flash'; messages = @(@{ role = 'system'; content = $sys2 }, @{ role = 'user'; content = $u }); max_tokens = 220; temperature = 0.3; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
        $resp = Invoke-WebRequest -Uri 'https://api.deepseek.com/chat/completions' -Method Post -Headers @{ Authorization = "Bearer $k" } -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60 -UseBasicParsing
        $obj = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
        $s = [string]$obj.choices[0].message.content
        if ($s) { $script:memorySummary = $s.Trim(); Save-Memory }
    } catch { }
}
$script:chatHistory = @()
Load-Memory
$script:speakOn   = $true
$script:synth     = $null
$script:chatForm  = $null
$script:chatBox   = $null
$script:bubble    = $null
$script:bubbleLabel = $null
$script:bubbleUntil = [DateTime]::MinValue
$script:chatPs    = $null
$script:chatAsync = $null
$script:chatTask  = $null
$script:http      = $null
$script:lastUser  = ''

function Write-Err([string]$tag) {
    try {
        $ep = Join-Path (Join-Path $env:USERPROFILE '.dsh\fish-pet') 'error.log'
        if ((Test-Path $ep) -and (Get-Item $ep).Length -gt 1MB) {
            Remove-Item ($ep + '.1') -Force -ErrorAction SilentlyContinue
            Move-Item $ep ($ep + '.1') -Force
        }
    } catch { }
    try {
        $line = (Get-Date -Format 'HH:mm:ss') + '  ' + $tag
        Add-Content -LiteralPath $ErrorPath -Value $line -Encoding UTF8
    } catch { }
}

# 读取密钥：环境变量 → DPAPI 加密文件 → 明文文件
function Read-Key([string]$name) {
    $dir = Join-Path $env:USERPROFILE '.dsh\fish-pet'
    $enc = Join-Path $dir ($name + '.key.enc')
    if (Test-Path $enc) {
        try {
            $sec = ConvertTo-SecureString (Get-Content -LiteralPath $enc -Raw).Trim()
            $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
        } catch { }
    }
    $plain = Join-Path $dir ($name + '.key')
    if (Test-Path $plain) { return (Get-Content -LiteralPath $plain -Raw -ErrorAction SilentlyContinue).Trim() }
    return $null
}
function Get-ApiKey {
    if ($env:DEEPSEEK_API_KEY) { return $env:DEEPSEEK_API_KEY }
    $kk = Read-Key 'deepseek'
    if ($kk) { return $kk }
    try {
        $kf = Join-Path $DataDir 'deepseek.key'
        if (Test-Path $kf) { $v = (Get-Content -LiteralPath $kf -Raw).Trim(); if ($v) { return $v } }
    } catch { }
    try {
        $raw = Get-Content (Join-Path $env:USERPROFILE '.dsh\.credentials.yaml') -Raw -ErrorAction Stop
        $m = [regex]::Match($raw, 'DEEPSEEK_API_KEY:\s*(\S+)')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return $null
}

# 打字聊天窗口
# 手动添加提醒
# 提醒清单：查看 / 删除
function Show-ReminderList {
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '提醒清单'
        $dlg.Size = New-Object System.Drawing.Size(560, 380)
        $dlg.StartPosition = 'CenterScreen'
        $dlg.TopMost = $true
        $dlg.FormBorderStyle = 'FixedDialog'
        $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
        $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5)
        $lb = New-Object System.Windows.Forms.ListBox
        $lb.Location = New-Object System.Drawing.Point(16, 14)
        $lb.Size = New-Object System.Drawing.Size(512, 240)
        $lb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5)
        $dlg.Controls.Add($lb)
        $btnDel = New-Object System.Windows.Forms.Button
        $btnDel.Text = '删除选中'
        $btnDel.Location = New-Object System.Drawing.Point(16, 268)
        $btnDel.Width = 120
        $dlg.Controls.Add($btnDel)
        $btnClear = New-Object System.Windows.Forms.Button
        $btnClear.Text = '清空全部'
        $btnClear.Location = New-Object System.Drawing.Point(150, 268)
        $btnClear.Width = 120
        $dlg.Controls.Add($btnClear)
        $btnClose = New-Object System.Windows.Forms.Button
        $btnClose.Text = '关闭'
        $btnClose.Location = New-Object System.Drawing.Point(408, 268)
        $btnClose.Width = 120
        $dlg.Controls.Add($btnClose)
        $script:remList = $lb
        $script:remDlg = $dlg
        $script:remBtnDel = $btnDel
        $script:remBtnClear = $btnClear
        $script:remBtnClose = $btnClose
        $script:remItems = @()
        $script:remRefresh = {
            $script:remList.Items.Clear()
            $script:remItems = @(Load-Notes)
            $i = 0
            foreach ($n in $script:remItems) {
                $i++
                $dueText = '不限时'
                if ($n.due) {
                    try {
                        $d = [datetime]::Parse([string]$n.due)
                        $firedMark = ''
                        try { if ($n.fired) { $firedMark = '（已提醒）' } } catch { }
                        $dueText = $d.ToString('MM-dd HH:mm') + $firedMark
                    } catch { }
                }
                [void]$script:remList.Items.Add(('{0}. {1}   〔{2}〕' -f $i, [string]$n.text, $dueText))
            }
            if ($script:remList.Items.Count -eq 0) { [void]$script:remList.Items.Add('（还没有提醒事项）') }
        }
        $btnClose.Add_Click({ $script:remDlg.Close() })
        $dlg.Add_Shown({
            & $script:remRefresh
        })
        $btnDel.Add_Click({
            $sel = $script:remList.SelectedIndex
            $arr = @(Load-Notes)
            if ($sel -ge 0 -and $arr.Count -gt $sel) {
                $kept = @()
                for ($i = 0; $i -lt $arr.Count; $i++) { if ($i -ne $sel) { $kept += $arr[$i] } }
                [IO.File]::WriteAllText($script:notesPath, (ConvertTo-Json -InputObject @($kept) -Depth 4), (New-Object Text.UTF8Encoding($false)))
                & $script:remRefresh
            }
        })
        $btnClear.Add_Click({
            $r = [System.Windows.Forms.MessageBox]::Show('清空全部提醒事项？', '提醒清单', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                [IO.File]::WriteAllText($script:notesPath, '[]', (New-Object Text.UTF8Encoding($false)))
                & $script:remRefresh
            }
        })
        [void]$dlg.ShowDialog()
    } catch { Write-Err 'REMLIST-ERR' }
}

# 右键菜单文字随语言切换（中文 / English）
function Set-MenuItemText($item, [string]$text) {
    try { if ($null -ne $item) { $item.Text = $text } } catch { }
}
function Update-MenuLang {
    try {
        $en = ([string]$script:uiLang -eq 'en')
        if ($en) {
            Set-MenuItemText $miFeed 'Feed me'
            Set-MenuItemText $miType 'Type a message'
            Set-MenuItemText $miTalk 'Start listening (mic)'
            Set-MenuItemText $miVoice $(if ($script:speakOn) { 'Voice reading: on' } else { 'Voice reading: off' })
            Set-MenuItemText $miVoiceSet 'Change voice'
            Set-MenuItemText $miChatLang 'Chat language'
            Set-MenuItemText $miUiLang 'UI language'
            try { $script:langItemMap['zh'].Text = 'Chinese'; $script:langItemMap['en'].Text = 'English'; $script:langItemMap['auto'].Text = 'Auto' } catch { }
            try { $script:uiItemMap['zh'].Text = 'Chinese'; $script:uiItemMap['en'].Text = 'English' } catch { }
            Set-MenuItemText $miWake $(if ($script:autoOn) { 'Voice standby: on' } else { 'Voice standby: off' })
            Set-MenuItemText $miChat $(if ($script:chatOn) { 'Voice chat: on' } else { 'Voice chat: off' })
            Set-MenuItemText $miPause $(if ($script:paused) { 'Resume' } else { 'Rest a while' })
            Set-MenuItemText $miHome 'Back to corner'
            Set-MenuItemText $miBigger 'Grow bigger'
            Set-MenuItemText $miSmall 'Shrink'
            Set-MenuItemText $miRemind 'Add a reminder...'
            Set-MenuItemText $miRemindList 'Reminders...'
            Set-MenuItemText $miClear 'Clear memory...'
            Set-MenuItemText $miQuit 'Swim away (exit)'
        } else {
            Set-MenuItemText $miFeed '喂它一口'
            Set-MenuItemText $miType '打字说两句'
            Set-MenuItemText $miTalk '开始听我说（麦克风）'
            Set-MenuItemText $miVoice $(if ($script:speakOn) { '语音朗读：开' } else { '语音朗读：关' })
            Set-MenuItemText $miVoiceSet '换个声音'
            Set-MenuItemText $miChatLang '聊天语言'
            Set-MenuItemText $miUiLang '界面语言'
            try { $script:langItemMap['zh'].Text = '中文'; $script:langItemMap['en'].Text = 'English'; $script:langItemMap['auto'].Text = '自动模式' } catch { }
            try { $script:uiItemMap['zh'].Text = '中文'; $script:uiItemMap['en'].Text = 'English' } catch { }
            Set-MenuItemText $miWake $(if ($script:autoOn) { '语音待命：开' } else { '语音待命：关' })
            Set-MenuItemText $miChat $(if ($script:chatOn) { '语音聊天：开' } else { '语音聊天：关（省 token）' })
            Set-MenuItemText $miPause $(if ($script:paused) { '继续游' } else { '停下歇会儿' })
            Set-MenuItemText $miHome '回到右下角'
            Set-MenuItemText $miBigger '长大一点'
            Set-MenuItemText $miSmall '变小一点'
            Set-MenuItemText $miRemind '加个提醒…'
            Set-MenuItemText $miRemindList '提醒清单…'
            Set-MenuItemText $miClear '清除记忆…'
            Set-MenuItemText $miQuit '让它游走（退出）'
        }
        Set-MenuItemText $miBalance $(if ($en) { 'Balance: --' } else { '余额：--' })
        try { if ($menu) { $menu.Refresh() } } catch { }
        Write-Err ('LANG-UI ui=' + [string]$script:uiLang + ' chat=' + [string]$script:langMode + ' feed=' + $miFeed.Text + ' pause=' + $miPause.Text + ' balance=' + $miBalance.Text)
    } catch { }
}

# 切换朗读音色（立即生效并写入 config.json）
# 切换中英文聊天模式（立即生效并写入 config.json）
function Set-LangMode([string]$mode, [string]$label) {
    Write-Err ('LANG-SET mode=' + $mode + ' label=' + $label)
    try {
        $script:langMode = $mode
        try {
            $cfg = Join-Path $DataDir 'config.json'
            if (Test-Path $cfg) {
                $j = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.persona) { $j | Add-Member -NotePropertyName persona -NotePropertyValue ([ordered]@{ lang = $mode }) }
                elseif ($j.persona.PSObject.Properties.Name -notcontains 'lang') { $j.persona | Add-Member -NotePropertyName lang -NotePropertyValue $mode }
                else { $j.persona.lang = $mode }
                [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        # 更新子菜单的勾选状态（同时只勾一个）
        try {
            if ($script:langItemMap) {
                foreach ($k in @($script:langItemMap.Keys)) { $script:langItemMap[$k].Checked = ([string]$k -eq [string]$mode) }
                $script:langItemsFresh = $true
            }
        } catch { }
        if ($mode -eq 'en') { Show-Bubble 'Language: English' }
        elseif ($mode -eq 'auto') { Show-Bubble '语言：自动模式' }
        else { Show-Bubble ('语言：' + $label) }
    } catch { Write-Err 'LANG-SET-ERR' }
}

# 切换界面语言（只影响右键菜单文字，不动聊天语言）
function Set-UiLang([string]$mode, [string]$label) {
    try {
        $script:uiLang = $mode
        try {
            $cfg = Join-Path $DataDir 'config.json'
            if (Test-Path $cfg) {
                $j = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.ui) { $j | Add-Member -NotePropertyName ui -NotePropertyValue ([ordered]@{ lang = $mode }) }
                elseif ($j.ui.PSObject.Properties.Name -notcontains 'lang') { $j.ui | Add-Member -NotePropertyName lang -NotePropertyValue $mode }
                else { $j.ui.lang = $mode }
                [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        try {
            if ($script:uiItemMap) {
                foreach ($k in @($script:uiItemMap.Keys)) { $script:uiItemMap[$k].Checked = ([string]$k -eq [string]$mode) }
            }
        } catch { }
        Update-MenuLang
        Write-Err ('UI-LANG mode=' + $mode)
    } catch { }
}

# 启动时按当前界面语言设置一遍菜单文字
try { Update-MenuLang } catch { }

function Set-TtsVoice([string]$voice, [string]$label) {
    try {
        $script:ttsVoice = $voice
        try {
            $cfg = Join-Path $DataDir 'config.json'
            if (Test-Path $cfg) {
                $j = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.tts) { $j | Add-Member -NotePropertyName tts -NotePropertyValue ([ordered]@{ engine = 'edge'; voice = $voice; rate = '+12%'; pitch = '+10Hz' }) }
                $j.tts.voice = $voice
                [IO.File]::WriteAllText($cfg, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        Show-Bubble ('声音换成：' + $label)
        try {
            if ($script:voiceItemMap) {
                foreach ($k in @($script:voiceItemMap.Keys)) { $script:voiceItemMap[$k].Checked = ([string]$k -eq [string]$voice) }
            }
        } catch { }
        Speak-Text ('主人你好呀，我是大肥鱼，现在用的是' + $label + '的声音')
    } catch { Write-Err 'VOICE-SET-ERR' }
}

function Show-Reminder {
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '加个提醒'
        $dlg.Size = New-Object System.Drawing.Size(460, 190)
        $dlg.StartPosition = 'CenterScreen'
        $dlg.TopMost = $true
        $dlg.FormBorderStyle = 'FixedDialog'
        $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
        $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = '写一句话，能带时间就定时提醒：' + [Environment]::NewLine + '例：15:30 开会 / 明天7点 起床 / 10分钟后 喝水'
        $lbl.Location = New-Object System.Drawing.Point(16, 12)
        $lbl.Width = 420; $lbl.Height = 44
        $dlg.Controls.Add($lbl)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(16, 62)
        $tb.Width = 412
        $tb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
        $dlg.Controls.Add($tb)
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = '记下'
        $btn.Location = New-Object System.Drawing.Point(328, 104)
        $btn.Width = 100
        $dlg.Controls.Add($btn)
        $script:inputDlg = $dlg
        $script:inputBox = $tb
        $script:inputText = $null
        $btn.Add_Click({ $script:inputText = $script:inputBox.Text; $script:inputDlg.Close() })
        $tb.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $script:inputText = $script:inputBox.Text; $script:inputDlg.Close() } })
        $dlg.Add_Shown({ $script:inputBox.Focus() })
        [void]$dlg.ShowDialog()
        $txt = [string]$script:inputText
        $script:inputText = $null
        if ($txt -and $txt.Trim().Length -gt 0) {
            $txt = $txt.Trim()
            $due = Get-DueFromText $txt
            Save-Note $txt $due
            if ($due) {
                Show-Bubble ('记下了：' + $txt + '（' + $due.ToString('MM-dd HH:mm') + ' 提醒你）')
            } else {
                Show-Bubble ('记下了：' + $txt + '（没说时间，我就一直记着）')
            }
        }
    } catch { Write-Err 'REMIND-ERR' }
}

function Show-Input {
    Write-Err 'INPUT-OPEN'
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '跟大肥鱼说两句'
        $dlg.Size = New-Object System.Drawing.Size(410, 140)
        $dlg.StartPosition = 'CenterScreen'
        $dlg.TopMost = $true
        $dlg.FormBorderStyle = 'FixedDialog'
        $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
        $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(16, 16)
        $tb.Width = 362
        $tb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
        $dlg.Controls.Add($tb)
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = '发过去'
        $btn.Location = New-Object System.Drawing.Point(278, 56)
        $btn.Width = 100
        $dlg.Controls.Add($btn)
        $script:inputDlg = $dlg
        $script:inputBox = $tb
        $btn.Add_Click({ $script:inputText = $script:inputBox.Text; $script:inputDlg.Close() })
        $tb.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $script:inputText = $script:inputBox.Text; $script:inputDlg.Close() } })
        $dlg.Add_Shown({ $script:inputBox.Focus() })
        [void]$dlg.ShowDialog()
        $txt = [string]$script:inputText
        $script:inputText = $null
        Write-Err ('INPUT-SEND [' + $txt + ']')
        if ($txt -and $txt.Trim().Length -gt 0) {
            $script:lastReplyAt = Get-Date
            Start-Chat $txt.Trim()
        }
    } catch { Write-Err 'INPUT-ERR' }
}

# 取 DeepSeek 余额文本（缓存 60 秒，避免每次开菜单都卡一下）
function Get-BalanceText {
    if ($script:balCache -and ((Get-Date) - $script:balAt).TotalSeconds -lt 60) { return $script:balCache }
    $uiEn = ([string]$script:uiLang -eq 'en')
    $prefix = if ($uiEn) { 'Balance: ' } else { '余额：' }
    $txt = $prefix + $(if ($uiEn) { 'query failed' } else { '查询失败' })
    try {
        $k = Get-ApiKey
        if (-not $k) {
            $txt = $prefix + $(if ($uiEn) { 'no key' } else { '未配置 key' })
        } else {
            $r = Invoke-RestMethod -Uri 'https://api.deepseek.com/user/balance' -Headers @{ Authorization = "Bearer $k" } -TimeoutSec 8
            $b = @($r.balance_infos) | Select-Object -First 1
            if ($b) {
                $sym = switch ([string]$b.currency) { 'CNY' { '¥' } 'USD' { '$' } default { [string]$b.currency + ' ' } }
                $txt = $prefix + $sym + $b.total_balance
            }
        }
    } catch { }
    $script:balCache = $txt
    $script:balAt = Get-Date
    return $txt
}

function Show-Bubble([string]$text) {
    try {
        if ($null -eq $script:bubble) {
            $b = New-Object System.Windows.Forms.Form
            $b.FormBorderStyle = 'None'
            $b.StartPosition   = 'Manual'
            $b.TopMost         = $true
            $b.ShowInTaskbar   = $false
            $b.BackColor       = [System.Drawing.Color]::FromArgb(255, 20, 40, 70)
            $b.TransparencyKey = [System.Drawing.Color]::FromArgb(255, 20, 40, 70)
            $b.Opacity         = [double]$script:cfg.bubble.opacity
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.AutoSize      = $true
            $lbl.MaximumSize   = New-Object System.Drawing.Size(340, 0)
            $lbl.Font          = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5)
            $lbl.ForeColor     = [System.Drawing.Color]::FromArgb(255, 28, 38, 52)
            $lbl.BackColor     = [System.Drawing.Color]::FromArgb(255, 248, 251, 255)
            $lbl.Padding       = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
            $lbl.Text          = ''
            $lbl.Add_Click({ $script:bubble.Hide() })
            $b.Controls.Add($lbl)
            $script:bubble = $b
            $script:bubbleLabel = $lbl
        }
        $script:bubbleLabel.Text = $text
        $sz = $script:bubbleLabel.PreferredSize
        $w = [Math]::Min(364, [Math]::Max(120, $sz.Width))
        $h = $sz.Height
        $bx = [Math]::Min([Math]::Max(0, [int]$script:x + [int](150 - ($w / 2))), $wa.Right - $w - 8)
        $by = [int]$script:y + 44 - $h
        if ($by -lt 0) { $by = [Math]::Min($wa.Bottom - $h - 8, [int]$script:y + $H - 10) }
        $script:bubble.SetBounds($bx, $by, $w, $h)
        $script:bubble.Show()
        $script:bubble.BringToFront()
        $script:bubbleUntil = (Get-Date).AddSeconds([Math]::Max(6, [Math]::Min(18, $text.Length / 7 + 5)))
    } catch { Write-Err 'BUBBLE-ERR' }
}

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
        $ff = 'C:\Users\Lenovo\.local\bin\ffmpeg.exe'
        if (-not (Test-Path $ff)) { $ff = (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue).Source }
        if (-not $ff) { Write-Err 'TTS-NO-FFMPEG'; return }
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
        } else {
            Write-Err ('TTS-CONV-FAIL ' + $mp3)
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
    $script:ttsSegReqAt = @()
    for ($i = 0; $i -lt $script:ttsSegs.Count; $i++) {
        $script:ttsSegFiles += (Join-Path $env:TEMP ('fish-tts-' + [guid]::NewGuid().ToString('N') + '.mp3'))
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
        $workerPath = Join-Path (Split-Path -Parent $PSCommandPath) 'tts_worker.py'
        if (-not (Test-Path $workerPath)) { Write-Err 'TTS-WORKER-MISSING'; return $false }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
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
                $hit = Get-Content $script:ttsStatusFile -ErrorAction SilentlyContinue | Where-Object { $_ -match ('^' + $rid + ' ') } | Select-Object -Last 1
            } catch { $hit = $null }
            # 请求丢失检测：6 秒还没有任何状态记录，按失败处理（会走下面的重试）
            if (-not $hit -and $script:ttsSegReqAt -and $script:ttsSegReqAt.Count -gt $i -and $script:ttsSegReqAt[$i] -and ((Get-Date) - $script:ttsSegReqAt[$i]).TotalSeconds -gt 6) {
                Write-Err ('TTS-SEG-TIMEOUT idx=' + $i)
                $hit = 'TIMEOUT'
            }
            if ($hit) {
                if ($hit -like ('*' + $rid + ' OK*')) { $script:ttsSegDone[$i] = $true }
                else {
                    Write-Err ('TTS-SEG-FAIL idx=' + $i)
                    # 合成失败也要立刻放开“正在说话”的锁，否则耳朵会被挡住整整一个看门狗周期
                    $script:speakEndAt = (Get-Date)
                    if ($null -eq $script:ttsRetry) { $script:ttsRetry = @{} }
                    if (-not $script:ttsRetry[[string]$i]) {
                        # 失败自动重试一次：换新请求 id 再合成
                        $script:ttsRetry[[string]$i] = 1
                        $script:ttsSegReq[$i] = ''
                        $script:ttsSegDone[$i] = $false
                    } else {
                        $script:ttsSegDone[$i] = $true
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
                $file = $script:ttsSegFiles[$next]
                if ((Test-Path $file) -and (Get-Item $file).Length -gt 800) {
                    $script:ttsSegPlaying = $next
                    Play-TtsFile $file $script:ttsVoiceUsed
                } else {
                    $script:ttsSegPlayed[$next] = $true
                }
            } elseif (-not $script:ttsSegReq[$next]) {
                Request-TtsSegment $next
            }
        } else {
            # 3) 正在播：到点视为播完（SoundPlayer 无结束事件），再预取下一段
            if ($script:playUntil -and (Get-Date) -ge $script:playUntil) {
                Complete-TtsSegment
            } else {
                $nx = $script:ttsSegPlaying + 1
                if ($nx -lt $script:ttsSegs.Count -and -not $script:ttsSegDone[$nx] -and -not $script:ttsSegReq[$nx]) { Request-TtsSegment $nx }
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

# ---------- 麦克风：离线中文识别 + 唤醒词 ----------
$script:rec = $null
$script:gWake = $null
$script:gDict = $null
$script:autoOn = $false
$script:dictating = $false
$script:woke = $false
$script:heard = $null
$script:heardConf = 0.0
$script:dictDeadline = [DateTime]::MinValue
$script:resumeAt = $null
$script:listen = $false
$script:listenDeadline = [DateTime]::MinValue
$script:fixWords = @{ '大飞宇' = '大肥鱼'; '大飞鱼' = '大肥鱼'; '大肥于' = '大肥鱼'; '飞鱼' = '肥鱼' }

function Ensure-Recognizer {
    if ($null -ne $script:rec) { return $true }
    try {
        Add-Type -AssemblyName System.Speech
        $r = New-Object System.Speech.Recognition.SpeechRecognitionEngine([System.Globalization.CultureInfo]'zh-CN')
        $r.SetInputToDefaultAudioDevice()

        $dict = New-Object System.Speech.Recognition.DictationGrammar
        $dict.Name = 'dictation'
        $dict.Enabled = $false
        $r.LoadGrammar($dict)

        $wc = New-Object System.Speech.Recognition.Choices
        $wc.Add(@('大肥鱼', '大肥鱼你在吗', '喂大肥鱼', '小鱼', '蓝鱼', '小蓝鱼'))
        $wb = New-Object System.Speech.Recognition.GrammarBuilder
        $wb.Culture = [System.Globalization.CultureInfo]'zh-CN'
        $wb.Append($wc)
        $wg = New-Object System.Speech.Recognition.Grammar($wb)
        $wg.Name = 'wake'
        $wg.Enabled = $true
        $r.LoadGrammar($wg)

        $r.Add_SpeechRecognized({
            param($s, $e)
            if (-not $e.Result) { return }
            $name = ''
            try { $name = $e.Result.Grammar.Name } catch { }
            $txt = [string]$e.Result.Text
            if ($txt) {
                $script:heard = $txt
                $script:heardConf = [double]$e.Result.Confidence
                try { Add-Content -LiteralPath $ErrorPath -Value ((Get-Date -Format 'HH:mm:ss') + '  HEARD[' + [Math]::Round($e.Result.Confidence,2) + ']  ' + $txt) -Encoding UTF8 } catch { }
            }
        })
        $script:rec = $r
        $script:gWake = $wg
        $script:gDict = $dict
        return $true
    } catch {
        Write-Err 'SR-INIT'
        return $false
    }
}

function Start-Auto {
    if (-not (Ensure-Recognizer)) { return }
    $script:autoOn = $true
    $script:dictating = $false
    $script:woke = $false
    try { $script:gDict.Enabled = $true; $script:gWake.Enabled = $false } catch { }
    try { $script:rec.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple); Add-Content -LiteralPath $ErrorPath -Value ((Get-Date -Format 'HH:mm:ss') + '  AUTO-ON') -Encoding UTF8 } catch { Write-Err 'SR-AUTO' }
}

function Enter-Dictation {
    if (-not (Ensure-Recognizer)) { Show-Bubble '耳朵打不开…检查一下麦克风？'; return }
    $script:dictating = $true
    $script:woke = $false
    $script:heard = $null
    $script:heardConf = 0.0
    $script:dictDeadline = (Get-Date).AddSeconds(11)
    try { $script:gWake.Enabled = $false; $script:gDict.Enabled = $true } catch { }
    [System.Media.SystemSounds]::Asterisk.Play()
    Show-Bubble '我在听…（说完停一下）'
}

function BackToWake {
    $script:dictating = $false
    $script:heard = $null
    $script:heardConf = 0.0
    
}

function Start-Listen { Show-Bubble '语音在后台自动听，主人直接说话就行。' }
function Stop-Listen { BackToWake }

function Open-Chat {
    try {
        if ($null -eq $script:chatForm) {
            $cf = New-Object System.Windows.Forms.Form
            $cf.FormBorderStyle = 'FixedToolWindow'
            $cf.StartPosition   = 'Manual'
            $cf.TopMost         = $true
            $cf.ShowInTaskbar   = $false
            $cf.Text            = '和大肥鱼说话'
            $cf.Width           = 360
            $cf.Height          = 96
            $cf.BackColor       = [System.Drawing.Color]::FromArgb(255, 252, 244)
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.SetBounds(12, 12, 324, 26)
            $tb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5)
            $cf.Controls.Add($tb)
            $cf.Add_Shown({ $script:chatBox.Focus() })
            $tb.Add_KeyDown({
                param($s, $e)
                if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                    $e.SuppressKeyPress = $true
                    $txt = $script:chatBox.Text.Trim()
                    if ($txt) {
                        $script:chatBox.Text = ''
                        $script:chatForm.Hide()
                        Start-Chat $txt
                    }
                } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                    $script:chatForm.Hide()
                }
            })
            $script:chatForm = $cf
            $script:chatBox  = $tb
        }
        $script:chatForm.Left  = [Math]::Min([Math]::Max(0, [int]$script:x + 20), $wa.Right - 370)
        $script:chatForm.Top   = [Math]::Max(0, [int]$script:y - 110)
        $script:chatForm.Show()
        $script:chatForm.BringToFront()
        $script:chatBox.Focus()
    } catch { Write-Err 'CHATUI-ERR' }
}


# 语音识别常见同音错字纠正
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

function Start-Chat([string]$text) {
    Write-Err ('CHAT-START busy=' + $script:chatBusy + ' text=' + $text)
    $text = Fix-AsrText $text
    if ($text -match '记住|别忘了|提醒我|答应我|约定') {
        # 问句不算交代，别把"我们约定过什么"记成便签
        if ($text -notmatch '[？?]' -and $text -notmatch '什么|哪件事|哪一个|是不是|吗') { Save-Note $text (Get-DueFromText $text) }
    }
    if ($script:chatBusy) { $script:chatPending = $text; Show-Bubble '等我先说完这一句…'; return }
    $key = Get-ApiKey
    if (-not $key) { Show-Bubble '我没有钥匙，打不开话匣子…'; return }
    $script:chatBusy = $true
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
    } else {
        $sys = '你是主人桌面上的一条圆滚滚的蓝色小鱼，名字叫' + $pn.name + '，爸爸叫' + $pn.dad + '，妈妈叫' + $pn.mom + '，生日是' + $pn.birthday + '，出生在' + $pn.birthplace + '。有人问起家人、生日、出生地就照这个答，不要瞎编。' + $pn.extra
        if ($pn.likes) { $sys = $sys + ' 你喜欢：' + $pn.likes + '。' }
        if ($pn.dislikes) { $sys = $sys + ' 你讨厌：' + $pn.dislikes + '。' }
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
        if ($feedAgoEn) { $sys = $sys + ' The master has fed you ' + [int]$script:feeds + ' times in total; the last feeding was ' + $feedAgoEn + '. If the master asks whether you have eaten, answer truthfully based on this.' }
        $sys = $sys + "`r`n`r`nIMPORTANT: Answer ONLY in English. Never write Chinese characters - not even your own name. Use your English name and write family names in pinyin (Guangguang, Lili). Everything you output must be English only."
    } else {
        $sys = $sys + ' 你现在的状态：' + $moodDesc + '，饥饿值约' + [int]$script:hunger + '，和主人的亲密度约' + [int]$script:intimacy + '。说话要自然带出这种状态，但不要报具体数字。'
        if ($feedAgoText) { $sys = $sys + ' 主人一共喂过你 ' + [int]$script:feeds + ' 次白饭，上次喂食是 ' + $feedAgoText + '。主人问起你吃没吃过，就照实说，别乱讲。' }
    }
    if ($replyLang -eq 'en') { Write-Err ('SYS-EN[' + $sys.Length + ']: ' + ($sys -replace "[\r\n]+", ' | ')) }
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
    $body  = @{ model = 'deepseek-flash'; messages = $msgs; max_tokens = 100; temperature = 0.7; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
    if ($null -eq $script:http) {
        $script:http = New-Object System.Net.Http.HttpClient
        $script:http.Timeout = [TimeSpan]::FromSeconds(40)
        $script:http.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
    }
    $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
    $script:chatTask = $script:http.PostAsync('https://api.deepseek.com/chat/completions', $content)
    $script:chatTimer.Start()
}

$script:chatTimer = New-Object System.Windows.Forms.Timer
$script:chatTimer.Interval = 120
$script:chatTimer.Add_Tick({
    try {
        if ($null -eq $script:chatTask -or -not $script:chatTask.IsCompleted) { return }
        $script:chatTimer.Stop()
        $resp = $script:chatTask.GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        try { $resp.Dispose() } catch { }
        $script:chatTask = $null
        $reply = ''
        if ($jsonText) { try { $reply = [string]($jsonText | ConvertFrom-Json).choices[0].message.content } catch { } }
        if ($out -and $out.Count -gt 0) { $reply = [string]$out[0] }
        if ([string]::IsNullOrWhiteSpace($reply)) { $reply = '（吐了个泡泡）没听清，再说一遍嘛' }
        $reply = $reply.Trim()
        $script:chatHistory += @{ role = 'user'; content = $script:lastUser }
        $script:chatHistory += @{ role = 'assistant'; content = $reply }
        if ($script:chatHistory.Count -gt 24) { $script:chatHistory = @($script:chatHistory[($script:chatHistory.Count - 24)..($script:chatHistory.Count - 1)]); Save-Memory }
        Save-Memory
        Save-State
        $script:summaryCount = [int]$script:summaryCount + 1
        if (($script:summaryCount % 10) -eq 0 -and $script:chatHistory.Count -ge 6) { Update-Summary }
        # 亲密度与情绪
        $script:intimacy = [Math]::Min(100, $script:intimacy + 1.5)
        if ($script:lastUser -match '闭嘴|烦|滚|讨厌|笨蛋|丑') {
            $script:mood = 'sad'; $script:moodUntil = (Get-Date).AddSeconds(150)
        } elseif ($script:lastUser -match '乖|可爱|好鱼|棒|喜欢你|真聪明') {
            $script:mood = 'happy'; $script:moodUntil = (Get-Date).AddSeconds(150)
        }
        # 情绪：被夸冒爱心，被说胖就鼓起来
        if ($script:lastUser -match '乖|可爱|好鱼|棒|喜欢你|真聪明') {
            $script:pulse = 1.18
            foreach ($dx in @(-24, 0, 24)) { $script:hearts += @{ dx = $dx; age = 0.0; life = 1.4 } }
        } elseif ($script:lastUser -match '胖|肥|圆|丑') {
            $script:pulse = 1.26
        }
        $script:lastReply = $reply
        Show-Bubble $reply
        Speak-Text $reply
        $script:chatBusy = $false
        if ($script:chatPending) { $pp = $script:chatPending; $script:chatPending = $null; Start-Chat $pp }
    } catch {
        $script:chatBusy = $false
        $script:chatTimer.Stop()
        Show-Bubble '（呛了口水）刚才没接通…再试一次？'
        Write-Err 'CHAT-ERR'
    }
})

$form.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragging = $true
        $script:dragActive = $false
        $script:dragMoved = 0
        $script:dragOff.x = $e.X
        $script:dragOff.y = $e.Y
        $script:dragStart.x = $e.X
        $script:dragStart.y = $e.Y
    }
})
$form.Add_MouseMove({
    param($s, $e)
    if ($script:dragging) {
        $dx = $e.X - $script:dragStart.x
        $dy = $e.Y - $script:dragStart.y
        if (-not $script:dragActive -and ([Math]::Abs($dx) + [Math]::Abs($dy)) -lt 4) { return }
        $script:dragActive = $true
        $script:x = $e.X + $form.Left - $script:dragOff.x
        $script:y = $e.Y + $form.Top  - $script:dragOff.y
        $script:dragMoved += 1
        $script:baseY = $script:y
        if ([int]$script:x -ne $script:lastPx -or [int]$script:y -ne $script:lastPy) { $form.SetBounds([int]$script:x, [int]$script:y, $W, $H); $script:lastPx = [int]$script:x; $script:lastPy = [int]$script:y }
    }
})
$form.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $wasDrag = $script:dragging -and $script:dragActive
        $script:dragging = $false
        $script:dragActive = $false
        $script:baseY = $script:y
        if ($wasDrag) {
            $snap = 18
            $maxX = $wa.Right - $W
            $bottom = $wa.Bottom - $H
            if ($script:x -lt $snap) { $script:x = 0 }
            elseif ($script:x -gt ($maxX - $snap)) { $script:x = $maxX }
            if ($script:y -lt $snap) { $script:y = 0 }
            elseif ($script:y -gt ($bottom - $snap)) { $script:y = $bottom }
            if ([int]$script:x -ne $script:lastPx -or [int]$script:y -ne $script:lastPy) { $form.SetBounds([int]$script:x, [int]$script:y, $W, $H); $script:lastPx = [int]$script:x; $script:lastPy = [int]$script:y }
        }
        if (-not $wasDrag) { Invoke-Feed }
        Save-State
    }
})
# 右键菜单：延迟到鼠标事件之后再弹出，避免"闪退"（事件循环里 Show 会被立刻关掉）
$script:menuTimer = New-Object System.Windows.Forms.Timer
$script:menuTimer.Interval = 120
$script:menuTimer.Add_Tick({
    $script:menuTimer.Stop()
    try {
        try { foreach ($k in @($script:langItemMap.Keys)) { $script:langItemMap[$k].Checked = ([string]$k -eq [string]$script:langMode) } } catch { }
        try { foreach ($k2 in @($script:voiceItemMap.Keys)) { $script:voiceItemMap[$k2].Checked = ([string]$k2 -eq [string]$script:ttsVoice) } } catch { }
        try { Update-MenuLang } catch { }
        try { $miBalance.Text = Get-BalanceText } catch { }
        $menu.Show($script:menuScreenPt)
    } catch { Write-Err 'MENU-SHOW-ERR' }
})
$form.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $script:menuScreenPt = [System.Windows.Forms.Cursor]::Position
        $script:menuTimer.Start()
    }
})

$miFeed.Add_Click({ Invoke-Feed })
$miTalk.Add_Click({ Start-Listen })
$miWake.Add_Click({
    $script:autoOn = -not $script:autoOn
    if ($script:autoOn) { Start-Auto; try { Update-MenuLang } catch { } } else { try { if ($script:rec) { $script:rec.RecognizeAsyncCancel() } } catch { }; BackToWake; try { Update-MenuLang } catch { } }
})
$miType.Add_Click({ Show-Input })
$miRemind.Add_Click({ Show-Reminder })
$miRemindList.Add_Click({ Show-ReminderList })
$miClear.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show('确定要清空全部聊天记录和长期摘要吗？
清空后不可恢复（提醒事项会保留）。', '清除记忆', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
        $script:chatHistory = @()
        $script:memorySummary = ''
        try { Remove-Item -LiteralPath $script:memPath -Force -ErrorAction SilentlyContinue } catch { }
        try { Save-Memory } catch { }
        Show-Bubble '记忆清空了，咱们重新认识一下吧'
        Write-Err 'MEMORY-CLEARED'
    }
})
$miChat.Add_Click({
    $script:chatOn = -not $script:chatOn
    try { Update-MenuLang } catch { }
    if ($script:chatOn) { Start-Ear; Show-Bubble '聊天开啦，我继续听' } else { Stop-Ear; Show-Bubble '聊天先关着，省点 token～' }
})
$miBalance.Add_Click({
    $script:balCache = $null
    $miBalance.Text = Get-BalanceText
    Show-Bubble $miBalance.Text
})
$miVoice.Add_Click({
    $script:speakOn = -not $script:speakOn
    try { Update-MenuLang } catch { }
    if (-not $script:speakOn -and $script:synth) { try { $script:synth.SpeakAsyncCancelAll() } catch { } }
})
$miPause.Add_Click({
    $script:paused = -not $script:paused
    if (-not $script:paused) { $script:baseY = $script:y }
})
$miHome.Add_Click({
    $script:x = Get-DefaultX
    $script:y = Get-DefaultY
    $script:baseY = $script:y
    $script:dir = -1
    $script:vx = -26.0
    if ([int]$script:x -ne $script:lastPx -or [int]$script:y -ne $script:lastPy) { $form.SetBounds([int]$script:x, [int]$script:y, $W, $H); $script:lastPx = [int]$script:x; $script:lastPy = [int]$script:y }
    Save-State
})
$miBigger.Add_Click({
    $script:scale = [Math]::Min(1.6, $script:scale + 0.1)
    Save-State
})
$miSmall.Add_Click({
    $script:scale = [Math]::Max(0.6, $script:scale - 0.1)
    Save-State
})
$miQuit.Add_Click({
    try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.stop'), (Get-Date).ToString('o')) } catch { }
    try { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'asr-listener' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
    Save-State
    $form.Close()
})

# ---------- 动画计时器 ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 33
$script:frames = 0

$timer.Add_Tick({
    try {
        $dt = 0.033
        $script:t += $dt

        # TTS 常驻进程预热：第一次对话前把 python worker 拉起来，避免冷启动失败
        if (-not $script:ttsWarmed) {
            $script:ttsWarmed = $true
            try { Start-TtsWorker | Out-Null } catch { }
        }

        # 启动 3 秒后自报家门，让人知道它在听
        if (-not $script:greeted -and $script:t -gt 3) {
            $script:greeted = $true
            Show-Bubble '我在这里听你说话，说完停一下'
            try { [void](Get-BalanceText) } catch { }
        }

        # 每 15 秒看一眼耳朵还在不在，掉了就拉起来
        $script:earCheck += 1
        if ($script:chatOn -and $script:earCheck % 450 -eq 0) {
            $alive = $false
            try { $alive = [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'asr-listener' }) } catch { }
            if (-not $alive) {
                try { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path (Split-Path -Parent $PSCommandPath) 'asr-listener.ps1')) -WindowStyle Hidden } catch { }
                Show-Bubble '耳朵刚重启，继续听你说'
            }
        }

        # 脉动回归
        if ($script:pulse -gt 1.0) { $script:pulse = [Math]::Max(1.0, $script:pulse - $dt * 0.55) }

        # 游动：随机目标点，平滑靠近（不叠加额外抖动）
        if (-not $script:paused -and -not $script:dragging -and -not $menu.Visible) {
            $maxTX = [Math]::Max(20, $wa.Right - $W - 10)
            $maxTY = [Math]::Max(20, $wa.Bottom - $H - 10)
            if ($null -eq $script:tx) { $script:tx = Get-Random -Minimum 10 -Maximum $maxTX; $script:ty = Get-Random -Minimum 10 -Maximum $maxTY }
            $dx = [double]$script:tx - [double]$script:x
            $dy = [double]$script:ty - [double]$script:y
            $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
            if ($dist -lt 14 -and $script:t -gt $script:pauseUntil) {
                $script:pauseUntil = $script:t + (Get-Random -Minimum 1 -Maximum 4)
                $script:tx = Get-Random -Minimum 10 -Maximum $maxTX
                $script:ty = Get-Random -Minimum 10 -Maximum $maxTY
            } elseif ($script:t -gt $script:pauseUntil) {
                # 越靠近越减速，避免在目标点附近来回抖
                $k = 2.4 * $dt
                if ($dist -lt 60) { $k = [Math]::Max(0.08, $dist / 60.0 * 2.4 * $dt) }
                if ($k -gt 1.0) { $k = 1.0 }
                $script:x += $dx * $k
                $script:y += $dy * $k
                if ([Math]::Abs($dx) -gt 4) { if ($dx -gt 0) { $script:dir = 1 } else { $script:dir = -1 } }
            }
            if ($script:x -lt 0) { $script:x = 0 }; if ($script:x -gt $maxTX) { $script:x = $maxTX }
            if ($script:y -lt 0) { $script:y = 0 }; if ($script:y -gt $maxTY) { $script:y = $maxTY }
            $script:baseY = $script:y
            if ([int]$script:x -ne $script:lastPx -or [int]$script:y -ne $script:lastPy) { $form.SetBounds([int]$script:x, [int]$script:y, $W, $H); $script:lastPx = [int]$script:x; $script:lastPy = [int]$script:y }

            # 气泡每帧跟随鱼，避免错位
            if ($script:bubble -and $script:bubble.Visible) {
                $bw = [int]$script:bubble.Width
                $bh = [int]$script:bubble.Height
                $nbx = [Math]::Min([Math]::Max(0, [int]$script:x + [int](150 - ($bw / 2))), $wa.Right - $bw - 8)
                $nby = [int]$script:y + 44 - $bh
            if ($nby -lt 0) { $nby = [Math]::Min($wa.Bottom - $bh - 8, [int]$script:y + $H - 10) }
                if ([int]$script:bubble.Left -ne $nbx -or [int]$script:bubble.Top -ne $nby) {
                    $script:bubble.Location = New-Object System.Drawing.Point($nbx, $nby)
                }
            }
        }

        # 随机转身，别像传送带
        if ($false -and $script:t -gt $script:nextTurnAt) {
            $script:nextTurnAt = $script:t + (Get-Random -Minimum 8 -Maximum 16)
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 45) {
                $script:dir = -$script:dir
                $script:vx  = -$script:vx
            }
        }

        # 眨眼
        if ($script:t -gt $script:nextBlinkAt) {
            $script:blinkUntil = $script:t + 0.13
            $script:nextBlinkAt = $script:t + (Get-Random -Minimum 2.8 -Maximum 6.5)
        }
        $blink = $script:t -lt $script:blinkUntil

        # 泡泡（数组追加，别用定长集合的 Add）
        if (-not $script:paused -and $script:t -gt $script:nextBubbleAt) {
            $script:nextBubbleAt = $script:t + (Get-Random -Minimum 1.1 -Maximum 2.4)
            $script:bubbles += @{ age = 0.0; life = 2.2; size = (Get-Random -Minimum 0 -Maximum 4) / 2.0; seed = (Get-Random -Minimum 0 -Maximum 628) / 100.0 }
        }
        $alive = @()
        foreach ($b in @($script:bubbles)) {
            $b.age += $dt
            if ($b.age -lt $b.life) { $alive += $b }
        }
        $script:bubbles = $alive

        $heartsAlive = @()
        foreach ($h in @($script:hearts)) {
            $h.age += $dt
            if ($h.age -lt $h.life) { $heartsAlive += $h }
        }
        $script:hearts = $heartsAlive

        # 读后台耳朵的识别结果（每 0.5 秒一次，只读新增部分，不再整文件重读）
        $script:asrPoll = ([int]$script:asrPoll + 1) % 5
        if ($script:asrPoll -eq 0 -and -not $script:chatBusy) {
            foreach ($ln in (Read-NewAsrLines)) {
                $parts = $ln -split "`t"
                if ($parts.Count -ge 2 -and $parts[1] -eq 'H') {
                    if (-not $script:lastHeardBubble -or ((Get-Date) - $script:lastHeardBubble).TotalSeconds -gt 12) {
                        $script:lastHeardBubble = Get-Date
                        Show-Bubble '我在听…'
                    }
                } elseif ($parts.Count -ge 2 -and $parts[1] -eq 'M') {
                    Show-Bubble '我没找到麦克风，插一个再叫我'
                } elseif ($parts.Count -ge 2 -and $parts[1] -eq '?') {
                    if (-not $script:chatBusy) { Show-Bubble '（没听清，再说一遍嘛）' }
                } elseif ($parts.Count -ge 3 -and $parts[1] -eq '1') {
                    $text = $parts[2].Trim()
                    $dup = $false
                    if ($text.Length -ge 1) {
                        if ($script:lastHeard -eq $text -and ((Get-Date) - $script:lastHeardAt).TotalSeconds -lt 20) { $dup = $true }
                        if (-not $dup) { $script:lastHeard = $text; $script:lastHeardAt = Get-Date }
                    }
                    $lastR = [string]$script:lastReply
                    $echo = $false
                    # 回环过滤：只认“识别文本是回复的一段”或“开头 6 个字完全相同”，避免把主人的正常提问误杀
                    $nt = ($text -replace '[\s\p{P}\p{S}]', '')
                    $nr = ($lastR -replace '[\s\p{P}\p{S}]', '')
                    if ($nt.Length -ge 3 -and $nr.Length -ge 3) {
                        if ($nr.Contains($nt) -or $nt.Contains($nr)) { $echo = $true }
                        elseif ($nt.Length -ge 6 -and $nr.Length -ge 6 -and $nt.Substring(0, 6) -eq $nr.Substring(0, 6)) { $echo = $true }
                    }
                    $cool = (-not $script:lastReplyAt) -or (((Get-Date) - $script:lastReplyAt).TotalSeconds -gt 3)
                    $long = $text.Length -ge 3
                    if ($text.Length -ge 1 -and ($dup -or $echo -or (-not $script:chatOn) -or (-not $long))) {
                        Write-Err ('SKIP dup=' + $dup + ' echo=' + $echo + ' chatOn=' + $script:chatOn + ' long=' + $long + ' text=' + $text)
                    }
                    if ($text.Length -ge 1 -and -not $dup -and -not $echo -and $script:chatOn -and $long) {
                        if ($cool) { $script:lastReplyAt = Get-Date; Start-Chat $text; break }
                        else { $script:chatPending = $text; break }
                    }
                }
            }
        }

        # 冷却期内排队的消息，冷却过了补发
        if ($script:chatPending -and -not $script:chatBusy) {
            if ((-not $script:lastReplyAt) -or (((Get-Date) - $script:lastReplyAt).TotalSeconds -gt 3)) {
                $pp = $script:chatPending; $script:chatPending = $null; $script:lastReplyAt = Get-Date; Start-Chat $pp
            }
        }
        # 情绪随时间变化：每分钟饥饿 +1.2，心情按状态重算
        if (((Get-Date) - $script:moodTick).TotalSeconds -gt 60) {
    $script:moodTick = Get-Date
            $script:hunger = [Math]::Min(100, $script:hunger + 1.2)
            if (-not ($script:moodUntil -and (Get-Date) -lt $script:moodUntil)) {
                if ($script:hunger -ge 75) { $script:mood = 'hungry' }
                elseif ($script:intimacy -le 12) { $script:mood = 'lonely' }
                elseif ($script:intimacy -ge 70 -and $script:hunger -le 40) { $script:mood = 'happy' }
                else { $script:mood = 'normal' }
            }
        }

        # 缺 Python/edge-tts 时提示一次
        if ($script:ttsWarn -and -not $script:ttsWarnShown) {
            $script:ttsWarnShown = $true
            Show-Bubble '没装 Python/edge-tts，先用本机声音；装好后能换少女音'
        }

        # 缺 SiliconFlow key 时提示一次（否则鱼会“假装在听”）
        if (-not $script:keyWarn -and $script:t -gt 5 -and $script:chatOn) {
            $script:keyWarn = $true
            $hasKey = [bool]$env:SILICONFLOW_API_KEY
            if (-not $hasKey) { try { $hasKey = [bool](Read-Key 'siliconflow') } catch { } }
            if (-not $hasKey) {
                Show-Bubble '没找到硅基流动钥匙，先用本机耳朵听，识别会吃亏些'
            }
        }

        # 说完之后再恢复收音（否则会听见自己说话，自己跟自己聊）
        if ($script:speakEndAt -and (Get-Date) -ge $script:speakEndAt) {
            try { Remove-Item -LiteralPath (Join-Path $DataDir 'asr.talking') -Force -ErrorAction SilentlyContinue } catch { }
            try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.pause'), (Get-Date).ToString('o')) } catch { }
            $script:speakEndAt = $null
            # 鱼一说完立刻亮“在听…”，告诉主人可以开口
            if ($script:chatOn -and -not $script:chatBusy) {
                $script:lastIdleHint = Get-Date
                Show-Bubble '在听…（说吧）'
            }
        }
        # 看门狗：只在没有播放计时（合成失败/丢失回调）时兜底释放，避免把正在播放的锁提前解开
        $tkFile = Join-Path $DataDir 'asr.talking'
        if (Test-Path $tkFile) {
            $tkAge = ((Get-Date) - (Get-Item $tkFile).LastWriteTime).TotalSeconds
            if (-not $script:speakEndAt -and $tkAge -gt 12) {
                try { Remove-Item -LiteralPath $tkFile -Force -ErrorAction SilentlyContinue } catch { }
                $script:speakEndAt = $null
                Write-Err ('TALKING-WATCHDOG age=' + [int]$tkAge)
            }
        }

        # 到点的提醒：主动冒泡 + 开口
        if ($script:frames % 600 -eq 0) {
            try {
                $remArr = @(Load-Notes)
                $remChanged = $false
                foreach ($n in $remArr) {
                    $dueStr = [string]$n.due
                    if (-not $dueStr) { continue }
                    $isFired = $false
                    try { if ($n.fired) { $isFired = [bool]$n.fired } } catch { }
                    if ($isFired) { continue }
                    try {
                        if ((Get-Date) -ge [datetime]::Parse($dueStr)) {
                            $n | Add-Member -NotePropertyName fired -NotePropertyValue $true -Force
                            $remChanged = $true
                            Show-Bubble ([char]0x23F0 + ' 主人，你让我提醒你：' + [string]$n.text)
                            Speak-Text ('主人，你让我提醒你：' + [string]$n.text)
                        }
                    } catch { }
                }
                if ($remChanged) {
                    [IO.File]::WriteAllText($script:notesPath, (ConvertTo-Json -InputObject @($remArr) -Depth 4), (New-Object Text.UTF8Encoding($false)))
                }
            } catch { }
        }

        # 空闲时常驻“在听…”，回复后 3 秒内让位给回复气泡
        if ($script:chatOn -and -not $script:chatBusy -and -not (Test-Path (Join-Path $DataDir 'asr.talking'))) {
            $quiet = (-not $script:lastReplyAt) -or (((Get-Date) - $script:lastReplyAt).TotalSeconds -gt 3)
            $due = (-not $script:lastIdleHint) -or (((Get-Date) - $script:lastIdleHint).TotalSeconds -gt 3)
            if ($quiet -and $due) {
                $script:lastIdleHint = Get-Date
                Show-Bubble '在听…'
            }
        }

        # 气泡到期就收
        if ($script:bubble -and $script:bubble.Visible -and (Get-Date) -gt $script:bubbleUntil) { $script:bubble.Hide() }

        # 每 ~2 秒抢回最上层，避免被浏览器等窗口压住（33ms×60）
        $script:topCheck += 1
        if ($script:topCheck % 60 -eq 0) { try { $form.ReTop() } catch { } }

        # 画画
        Draw-Fish -g $g -t $script:t -dir $script:dir -scale $script:scale -pulse $script:pulse -blink $blink -mood 0 -expr $script:mood
        $form.Push($bmp, [int]$script:x, [int]$script:y)

        # 定期存盘
        $script:frames += 1
        if ($script:frames % 300 -eq 0) { Save-State }
    } catch {
        $line = (Get-Date -Format 'HH:mm:ss') + '  ' + $_.Exception.Message
        try { Add-Content -LiteralPath $ErrorPath -Value $line -Encoding UTF8 } catch { }
    }
})

$form.Add_FormClosing({ $timer.Stop(); $script:chatTimer.Stop(); Save-State; Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue })
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
