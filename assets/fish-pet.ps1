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
# 动态解析存档根目录：优先 config 指定 → 有 D~F 盘就用盘上的「桌宠」→ 否则落到用户目录
function Resolve-PetStore {
    $dir = '' 
    try { if ($script:cfg -and $script:cfg.storage -and $script:cfg.storage.dir) { $dir = [string]$script:cfg.storage.dir } } catch { }
    if (-not $dir) {
        foreach ($d in @('F:')) {
            if (Test-Path $d) { $dir = Join-Path $d '桌宠'; break }
        }
    }
    if (-not $dir) { $dir = Join-Path $env:USERPROFILE '.dsh\fish-pet\存档' }
    if (-not (Test-Path $dir)) { try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { } }
    return $dir
}

function Resolve-DshCwd {
    $dir = '' 
    try { if ($script:cfg -and $script:cfg.dsh -and $script:cfg.dsh.cwd) { $dir = [string]$script:cfg.dsh.cwd } } catch { }
    if (-not $dir) {
        foreach ($cand in @('F:\李智梅党建工作材料')) {
            if (Test-Path $cand) { $dir = $cand; break }
        }
    }
    if (-not $dir) { $dir = [Environment]::GetFolderPath('MyDocuments') }
    return $dir
}

function Load-Config {
    $def = [ordered]@{
        persona = [ordered]@{ name = '大肥鱼'; nameEn = 'Mia'; dad = '光光'; mom = '丽丽'; birthday = '2026年10月30日'; birthplace = '中国广西北海'; likes = '白饭、被摸头、主人夸它'; dislikes = '被说胖、被冷落、吵'; ownerBirthday = ''; lang = 'auto'; extra = '说话简短、俏皮、微微傲娇，用中文，称呼用户为"主人"，每次回复不超过30个字，不要用表情符号。' }
        bubble  = [ordered]@{ opacity = 0.15 }
        voice   = [ordered]@{ silenceGate = 1200; boost = 1; engine = 'cloud'; localConf = 0.55 }
        tts     = [ordered]@{ engine = 'edge'; voice = 'zh-CN-XiaoyiNeural'; rate = '+12%'; pitch = '+10Hz'; voiceEn = 'en-US-AnaNeural'; rateEn = '+8%'; pitchEn = '+15Hz'; ffmpeg = '' }
        ui      = [ordered]@{ lang = 'zh' }
        briefing = [ordered]@{ enabled = $true; time = '07:30'; cityCode = '101301301'; dir = '' }
        dsh     = [ordered]@{ cwd = '' }
        storage = [ordered]@{ dir = '' }
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
        if ($j.tts) { foreach ($k2 in @('engine','voice','rate','pitch','voiceEn','rateEn','pitchEn','ffmpeg')) { $v2 = $j.tts.$k2; if ($v2) { $script:cfg.tts[$k2] = [string]$v2 } } }
        if ($j.voice) {
            if ($j.voice.silenceGate) { $script:cfg.voice.silenceGate = [int]$j.voice.silenceGate }
            if ($j.voice.boost) { $script:cfg.voice.boost = [int]$j.voice.boost }
        }
        if ($j.briefing) {
            if ($null -ne $j.briefing.enabled) { $script:cfg.briefing.enabled = [bool]$j.briefing.enabled }
            if ($j.briefing.time) { $script:cfg.briefing.time = [string]$j.briefing.time }
            if ($j.briefing.cityCode) { $script:cfg.briefing.cityCode = [string]$j.briefing.cityCode }
            if ($j.briefing.dir) { $script:cfg.briefing.dir = [string]$j.briefing.dir }
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

# 视觉/截图模块（WinPick + 截图问答），实现在 lib\vision.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\vision.ps1')



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
$script:lookOnDrag = $true
$script:visionPending = $null
$script:dictateOn = $false
$script:dictateBuf = @()
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
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miMusic  = New-Object System.Windows.Forms.ToolStripMenuItem('弹首曲子')
$menu.Items.Add($miMusic) | Out-Null
                    # 子项在脚本末尾（函数定义齐全之后）一次性建好，避免展开时崩溃
$miMusicStop = $menu.Items.Add('停止弹奏')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miMusicStop.Add_Click({ try { Stop-Music | Out-Null } catch { } })
$miType = $menu.Items.Add('打字说两句')
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
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
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
$miBriefing = $menu.Items.Add('今日简报：开')
$miBriefNow = $menu.Items.Add('现在简报一次')
$miBriefRecent = New-Object System.Windows.Forms.ToolStripMenuItem('最近简报')
$menu.Items.Add($miBriefRecent) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miDictate = $menu.Items.Add('口述公文：开始')
$miDsh = $menu.Items.Add('交给 DSH 助手…')
$miRemind = $menu.Items.Add('加个提醒…')
$miRemindList = $menu.Items.Add('提醒清单…')
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miClear  = $menu.Items.Add('清除记忆…')
$miQuit   = $menu.Items.Add('让它游走（退出）')

# 菜单最下面显示版本号（灰色不可点）
$script:petVersion = 'dev'
try {
    $pj = Join-Path (Split-Path -Parent $PSScriptRoot) 'package.json'
    if (Test-Path $pj) { $script:petVersion = [string](Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json).version }
} catch { }
if (-not $script:petVersion) { $script:petVersion = 'dev' }
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miVersion = $menu.Items.Add('版本 v' + $script:petVersion)
$miVersion.Enabled = $false

function Save-State {
    $obj = [ordered]@{
        x = [int]$script:x; y = [int]$script:y; dir = [int]$script:dir
        scale = [Math]::Round($script:scale, 3); feeds = [int]$script:feeds
        hunger = [Math]::Round($script:hunger, 1); intimacy = [Math]::Round($script:intimacy, 1)
        mood = [string]$script:mood; seen = (Get-Date).ToString('o'); lastFeedAt = $script:lastFeedAtStr
    }
    # 原子写：先写 .tmp 再替换，避免被强杀时留下半截 JSON
    try {
        $tmpState = $StatePath + '.tmp'
        ($obj | ConvertTo-Json -Compress) | Set-Content -Path $tmpState -Encoding UTF8
        Move-Item -LiteralPath $tmpState -Destination $StatePath -Force
    } catch { }
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
# 便签/提醒模块，实现在 lib\reminders.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\reminders.ps1')


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
    if ($env:DEEPSEEK_API_KEY) { return ([string]$env:DEEPSEEK_API_KEY).Trim() }
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

# 菜单语言/界面语言模块，实现在 lib\language.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\language.ps1')



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

# 语音朗读模块（TTS 流水线），实现在 lib\speech.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\speech.ps1')

# 简报/拖拽/备忘/公文模块，实现在 lib\briefing.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\briefing.ps1')




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
# 聊天核心模块，实现在 lib\chat.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\chat.ps1')
# 诗歌/奏乐模块，实现在 lib\music.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\music.ps1')
# 鱼 -> DSH 转交任务模块，实现在 lib\dsh.ps1
. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib\dsh.ps1')

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
        if ($wasDrag) { Write-Err ("DRAGUP moved=" + $script:dragMoved + " look=" + $script:lookOnDrag) }
        if ($wasDrag -and $script:lookOnDrag -and $script:dragMoved -gt 12) { try { Analyze-UnderCursor } catch { } }
        Save-State
    }
})
# 右键菜单：延迟到鼠标事件之后再弹出，避免"闪退"（事件循环里 Show 会被立刻关掉）
$script:menuHold = $false   # 菜单打开期间冻结游动与置顶
$menu.Add_Closed({ $script:menuHold = $false; try { if ($script:menuResume) { $timer.Start(); $script:menuResume = $false } } catch { }; Write-Err 'MENU-CLOSED' })
$script:menuResume = $false
$script:menuTimer = New-Object System.Windows.Forms.Timer
$script:menuTimer.Interval = 120
$script:menuTimer.Add_Tick({
    $script:menuTimer.Stop()
    try {
        try { foreach ($k in @($script:langItemMap.Keys)) { $script:langItemMap[$k].Checked = ([string]$k -eq [string]$script:langMode) } } catch { }
        try { foreach ($k2 in @($script:voiceItemMap.Keys)) { $script:voiceItemMap[$k2].Checked = ([string]$k2 -eq [string]$script:ttsVoice) } } catch { }
        try { Update-MenuLang } catch { }
        try { $miBalance.Text = Get-BalanceText } catch { }
        try { Update-RecentBriefs } catch { }
        $menu.Show($script:menuScreenPt)
    } catch { Write-Err 'MENU-SHOW-ERR'; try { if ($script:menuResume) { $timer.Start(); $script:menuResume = $false }; $script:menuHold = $false } catch { } }
})
$form.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $script:menuHold = $true
        if ($timer.Enabled) { $timer.Stop(); $script:menuResume = $true }
        Write-Err 'MENU-HOLD-ON'
        $script:menuScreenPt = [System.Windows.Forms.Cursor]::Position
        $script:menuTimer.Start()
    }
})

$miFeed.Add_Click({ Invoke-Feed })
$miWake.Add_Click({
    $script:autoOn = -not $script:autoOn
    if ($script:autoOn) { Start-Auto; try { Update-MenuLang } catch { } } else { try { if ($script:rec) { $script:rec.RecognizeAsyncCancel() } } catch { }; BackToWake; try { Update-MenuLang } catch { } }
})
$miType.Add_Click({ Show-Input })
$miBriefing.Add_Click({
    try {
        $script:cfg.briefing.enabled = -not [bool]$script:cfg.briefing.enabled
        try {
            $cfgPath2 = Join-Path $DataDir 'config.json'
            if (Test-Path $cfgPath2) {
                $j = [IO.File]::ReadAllText($cfgPath2, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (-not $j.briefing) { $j | Add-Member -NotePropertyName briefing -NotePropertyValue ([ordered]@{ enabled = $true; time = '07:30'; cityCode = '101301301' }) }
                $j.briefing.enabled = [bool]$script:cfg.briefing.enabled
                [IO.File]::WriteAllText($cfgPath2, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            }
        } catch { }
        try { Update-MenuLang } catch { }
    } catch { }
})
$miBriefNow.Add_Click({
    try { Update-MenuLang } catch { }
    Show-Briefing
})
$miDictate.Add_Click({
    try {
        if ($script:dictateOn) {
            $script:dictateOn = $false
            try { $miDictate.Text = '口述公文：开始' } catch { }
            $raw = (@($script:dictateBuf) -join '')
            if (-not $raw) { Show-Bubble '刚才没记到内容'; return }
            Show-Bubble '我理一理…'
            Generate-Gongwen $raw
        } else {
            $script:dictateOn = $true
            $script:dictateBuf = @()
            try { $miDictate.Text = '口述公文：结束' } catch { }
            Show-Bubble '你说，我记着，说完再点一次'
        }
    } catch { Write-Err ('DICTATE-ERR ' + $_.Exception.Message) }
})

$miDsh.Add_Click({ Show-DshTaskInput })

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

        # 唱模式：旋律放完后再念歌词
        if ($script:musicPendingLyrics -and (-not $script:musicUntil -or (Get-Date) -ge $script:musicUntil)) {
            $ly = $script:musicPendingLyrics; $script:musicPendingLyrics = $null
            try { Speak-Text $ly } catch { }
        }

        # 弹琴：子进程跑完且文件够大才播
        if ($script:musicOut -and $script:musicProc) {
            try { if ($script:musicProc.HasExited) { Finish-Music } } catch { $script:musicOut = $null; $script:musicProc = $null }

        # 弹完了，处理排队中的对话（不打断正在进行的聊天）
        if ($script:musicQueue.Count -gt 0 -and -not (Test-MusicBusy) -and -not $script:chatBusy) {
            $nextText = [string]$script:musicQueue[0]
            $script:musicQueue = @($script:musicQueue | Select-Object -Skip 1)
            Write-Err ('MUSIC-RESUME ' + $nextText)
            try { Start-Chat $nextText } catch { }
        }
        }

        # 脉动回归
        if ($script:pulse -gt 1.0) { $script:pulse = [Math]::Max(1.0, $script:pulse - $dt * 0.55) }

        # 游动：随机目标点，平滑靠近（不叠加额外抖动）
        if (-not $script:paused -and -not $script:dragging -and -not $menu.Visible -and -not $script:menuHold) {
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
                } elseif ($parts.Count -ge 2 -and $parts[1] -eq 'K') {
                    Show-Bubble '（没配硅基流动 key，先用本机耳朵听）'
                    if (-not $script:keyWarn) { $script:keyWarn = $true }
                } elseif ($parts.Count -ge 2 -and $parts[1] -eq '?') {
                    if (-not $script:chatBusy) { Show-Bubble '（没听清，再说一遍嘛）' }
                } elseif ($parts.Count -ge 3 -and $parts[1] -eq '1') {
                    if ($script:dictateOn) {
                        $script:dictateBuf += [string]$parts[2].Trim()
                        Write-Err ('DICTATE+' + $parts[2].Trim())
                        continue
                    }
                    $text = $parts[2].Trim()
                    if ($text -match '提醒我|记一下|别忘了|帮我记') { try { Create-ReminderFromText $text } catch { }; continue }
                    if ($text -match '让DSH|交给DSH|让DSH助手|让代理') { try { Send-DshTask $text } catch { }; continue }
                    if ($text -match '^(知道了|收到|好的|好，知道了|不用提醒了|行了)。?$') {
                        try {
                            $arr = @(Load-Notes)
                            $target = @($arr | Where-Object { $_.due -and -not $_.done } | Sort-Object { [string]$_.due } | Select-Object -First 1)
                            if ($target.Count -gt 0) {
                                $target[0] | Add-Member -NotePropertyName done -NotePropertyValue $true -Force
                                [IO.File]::WriteAllText($script:notesPath, (ConvertTo-Json -InputObject @($arr) -Depth 4), (New-Object Text.UTF8Encoding($false)))
                                Show-Bubble '好，不吵你了'
                                Speak-Text '好，不吵你了'
                                continue
                            }
                        } catch { }
                    }
                    # 弹琴意图：命中曲库就本地合成播放，不走对话模型
                    if ($text -match '别弹|不要弹|停止|安静|安静点|闭嘴|stop') {
                        if (Stop-Music) { break }
                    }
                    if ($text -match '弹|演奏|唱首|唱个|来首曲子|music|play') {
                        if (Request-Music $text) { break }
                    }
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
                        if ($nr.Contains($nt)) { $echo = $true }
                        elseif ($nt.Contains($nr) -and $nt.Length -le ($nr.Length + 2)) { $echo = $true }
                        elseif ($nt.Length -ge 6 -and $nr.Length -ge 6 -and $nt.Substring(0, 6) -eq $nr.Substring(0, 6)) { $echo = $true }
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

    # 看门狗：chatBusy 卡住超过 60 秒就强制复位，避免麦克风被永久关闭
    if ($script:chatBusy -and $script:chatBusyAt -and ((Get-Date) - $script:chatBusyAt).TotalSeconds -gt 60) {
        $script:chatBusy = $false
        Write-Err ('CHATBUSY-WATCHDOG')
    }

        # 说完之后再恢复收音（否则会听见自己说话，自己跟自己聊）
        if ($script:speakEndAt -and (Get-Date) -ge $script:speakEndAt) {
            try { Remove-Item -LiteralPath (Join-Path $DataDir 'asr.talking') -Force -ErrorAction SilentlyContinue } catch { }
            try { [IO.File]::WriteAllText((Join-Path $DataDir 'asr.pause'), (Get-Date).ToString('o')) } catch { }
            $script:speakEndAt = $null
            # 不在这里立刻亮“在听…”，交由下面的空闲提示判断：只有耳朵真正空闲时才显示
            $script:lastIdleHint = $null
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

        # 每日简报：到点自动播报一次（每天只触发一次）
        if ($script:cfg.briefing -and $script:cfg.briefing.enabled) {
            try {
                $nowT = Get-Date
                $tparts = ([string]$script:cfg.briefing.time) -split ':'
                if ($tparts.Count -ge 2 -and $nowT.Hour -eq [int]$tparts[0] -and $nowT.Minute -eq [int]$tparts[1]) {
                    $todayKey = $nowT.ToString('yyyy-MM-dd')
                    if ($script:lastBriefingDate -ne $todayKey) {
                        $script:lastBriefingDate = $todayKey
                        Show-Briefing
                    }
                }
            } catch { }
        }

                # 截图问答：后台识图结果回收
        if ($script:visionPending) {
            $vp = $script:visionPending
            if (Test-Path $vp.out) {
                $ans = ''
                try { $ans = [string](Get-Content $vp.out -Raw | ConvertFrom-Json).text } catch { }
                try { Remove-Item $vp.out -Force -ErrorAction SilentlyContinue } catch { }
                try { Remove-Item $vp.png -Force -ErrorAction SilentlyContinue } catch { }
                $script:visionPending = $null
                if ($ans) { Show-Bubble $ans; Speak-Text $ans } else { Show-Bubble '这块画面我看不太清' }
            } elseif (((Get-Date) - $vp.at).TotalSeconds -gt 70) {
                try { Remove-Item $vp.png -Force -ErrorAction SilentlyContinue } catch { }
                $script:visionPending = $null
                Write-Err 'VISION-TIMEOUT'
            }
        }
# 到点的提醒：到点响一次，没确认就每 10 分钟再提醒，最多 3 次
        if ($script:frames % 600 -eq 0) {
            try {
                $remArr = @(Load-Notes)
                $remChanged = $false
                $nowRem = Get-Date
                foreach ($n in $remArr) {
                    $done = $false
                    try { if ($n.done) { $done = [bool]$n.done } } catch { }
                    if ($done) { continue }
                    $dueStr = [string]$n.due
                    if (-not $dueStr) { continue }
                    try { $dueDt = [datetime]::Parse($dueStr) } catch { continue }
                    $count = 0
                    try { if ($n.remindCount) { $count = [int]$n.remindCount } } catch { }
                    $wasFired = $false
                    try { if ($n.fired) { $wasFired = [bool]$n.fired } } catch { }
                    if ($wasFired -and -not $count) { continue }
                    $nextAt = $null
                    try { if ($n.nextAt) { $nextAt = [datetime]::Parse([string]$n.nextAt) } } catch { }
                    $shouldRemind = $false
                    if ($count -eq 0 -and $nowRem -ge $dueDt) { $shouldRemind = $true }
                    elseif ($count -lt 3 -and $nextAt -and $nowRem -ge $nextAt) { $shouldRemind = $true }
                    if ($shouldRemind) {
                        $n | Add-Member -NotePropertyName remindCount -NotePropertyValue ($count + 1) -Force
                        $n | Add-Member -NotePropertyName fired -NotePropertyValue $true -Force
                        $n | Add-Member -NotePropertyName nextAt -NotePropertyValue ((Get-Date).AddMinutes(10).ToString('o')) -Force
                        $remChanged = $true
                        Show-Bubble ([char]0x23F0 + ' 主人，你让我提醒你：' + [string]$n.text)
                        Speak-Text ('主人，你让我提醒你：' + [string]$n.text)
                        Write-Err ('REMIND-RING count=' + ($count + 1) + ' text=' + [string]$n.text)
                    }
                }
                if ($remChanged) {
                    [IO.File]::WriteAllText($script:notesPath, (ConvertTo-Json -InputObject @($remArr) -Depth 4), (New-Object Text.UTF8Encoding($false)))
                }
            } catch { }
        }
        # 空闲时常驻“在听…”，但只在耳朵真正空闲时显示：没在接话、没在识别、说完的暂停期已过
        if ($script:chatOn -and -not $script:chatBusy -and -not (Test-Path (Join-Path $DataDir 'asr.talking'))) {
            $busyFile = Join-Path $DataDir 'asr.busy'
            $pauseFile = Join-Path $DataDir 'asr.pause'
            $busyOk = -not (Test-Path $busyFile)
            $pauseOk = (-not (Test-Path $pauseFile)) -or (((Get-Date) - (Get-Item $pauseFile).LastWriteTime).TotalSeconds -gt 0.8)
            $quiet = (-not $script:lastReplyAt) -or (((Get-Date) - $script:lastReplyAt).TotalSeconds -gt 3)
            $due = (-not $script:lastIdleHint) -or (((Get-Date) - $script:lastIdleHint).TotalSeconds -gt 3)
            if ($busyOk -and $pauseOk -and $quiet -and $due) {
                $script:lastIdleHint = Get-Date
                Show-Bubble '在听…'
            }
        }

        # 气泡到期就收
        if ($script:bubble -and $script:bubble.Visible -and (Get-Date) -gt $script:bubbleUntil) { $script:bubble.Hide() }

        # 每 ~2 秒抢回最上层，避免被浏览器等窗口压住（33ms×60）
        $script:topCheck += 1
        if ($script:topCheck % 60 -eq 0 -and -not $menu.Visible -and -not $script:menuHold) { try { $form.ReTop() } catch { } }

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
# 填充「弹首曲子」子菜单（此处所有函数已定义，安全）
try {
    $miMusic.DropDownItems.Clear() | Out-Null
    $rndItem = New-Object System.Windows.Forms.ToolStripMenuItem('随便弹一首')
    $rndItem.Add_Click({ try { $all = Get-MusicLib; if ($all -and $all.Count -gt 0) { $pk = $all[(Get-Random -Maximum $all.Count)]; Request-Music $pk.name | Out-Null } } catch { } })
    $miMusic.DropDownItems.Add($rndItem) | Out-Null
    $miMusic.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
    $songCount = 0
    foreach ($sg in @(Get-MusicLib)) {
        if (-not $sg) { continue }
        $one = New-Object System.Windows.Forms.ToolStripMenuItem([string]$sg.name)
        $one.Add_Click({ param($snd, $ev) try { Request-Music $snd.Text | Out-Null } catch { } })
        $miMusic.DropDownItems.Add($one) | Out-Null
        $songCount++
    }
    Write-Err ('MUSIC-MENU ' + $songCount)
} catch { Write-Err ('MUSIC-MENU-ERR ' + $_.Exception.Message) }

[System.Windows.Forms.Application]::Run($form)
