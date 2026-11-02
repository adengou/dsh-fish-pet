# vision.ps1 · 截图问答：窗口拾取 + 截图 + 视觉模型（从主脚本拆出）

# 窗口拾取：把鱼拖到哪个窗口上就认出哪个窗口（截图问答用）
Add-Type -ReferencedAssemblies 'System.Drawing','System.Windows.Forms','System' -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinPick
{
    public static string LastDebug = "";
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint ga);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    public static string Pick(int x, int y, IntPtr self, uint selfPid)
    {
        var pt = new POINT { X = x, Y = y };
        IntPtr h = WindowFromPoint(pt);
        if (h == IntPtr.Zero) return null;
        IntPtr root = GetAncestor(h, 2);
        if (root != IntPtr.Zero) h = root;
        uint hp;
        GetWindowThreadProcessId(h, out hp);
        var c0 = new StringBuilder(256);
        GetClassName(h, c0, 256);
        string cls0 = c0.ToString();
        bool initialSkip = (hp == selfPid) || cls0 == "Progman" || cls0 == "WorkerW" || cls0 == "Shell_TrayWnd" || cls0 == "Shell_SecondaryTrayWnd";
        if (initialSkip)
        {
            IntPtr next = GetWindow(h, 2);
            int guard = 0;
            while (next != IntPtr.Zero && guard < 200)
            {
                uint np;
                GetWindowThreadProcessId(next, out np);
                var c2 = new StringBuilder(256);
                GetClassName(next, c2, 256);
                string cls2 = c2.ToString();
                RECT r2;
                GetWindowRect(next, out r2);
                int rw = r2.Right - r2.Left;
                int rh = r2.Bottom - r2.Top;
                bool skip = (np == selfPid) || !IsWindowVisible(next) || rw <= 0 || rh <= 0 || cls2 == "Progman" || cls2 == "WorkerW" || cls2 == "Shell_TrayWnd" || cls2 == "Shell_SecondaryTrayWnd";
                if (LastDebug.Length < 400) { LastDebug = LastDebug + "[" + cls2 + " pid=" + np + " vis=" + IsWindowVisible(next) + " " + rw + "x" + rh + "]"; }
                if (!skip) { h = next; break; }
                next = GetWindow(next, 2);
                guard++;
            }
            uint hp2;
            GetWindowThreadProcessId(h, out hp2);
            if (hp2 == selfPid) return null;
        }
        if (!IsWindowVisible(h)) return null;
        var cn = new StringBuilder(256);
        GetClassName(h, cn, 256);
        string cls = cn.ToString();
        if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") return null;
        var sb = new StringBuilder(512);
        GetWindowText(h, sb, 512);
        RECT r;
        GetWindowRect(h, out r);
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        return h.ToString() + "\t" + sb.ToString() + "\t" + cls + "\t" + r.Left + "," + r.Top + "," + (r.Right - r.Left) + "," + (r.Bottom - r.Top) + "\t" + pid;
    }
}
'@

# ---------- 截图问答：把鱼拖到窗口上，让鱼看一眼 ----------
function Capture-Window([string]$info) {
    try {
        $parts = $info -split "`t"
        if ($parts.Count -lt 4) { return $null }
        $rect = $parts[3] -split ','
        $l = [int]$rect[0]; $t = [int]$rect[1]; $w = [int]$rect[2]; $h = [int]$rect[3]
        if ($w -le 20 -or $h -le 20) { return $null }
        # 裁剪窗口中心区域：去掉标题栏、工具栏、侧边栏，让正文更大更清楚
        $cl = $l + [int]($w * 0.10)
        $ct = $t + [int]($h * 0.12)
        $cw = [Math]::Max(20, [int]($w * 0.80))
        $ch = [Math]::Max(20, [int]($h * 0.76))
        $maxSide = 800
        $scale = [Math]::Min(1.0, [Math]::Min($maxSide / [double]$cw, $maxSide / [double]$ch))
        $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($cl, $ct, 0, 0, (New-Object System.Drawing.Size($cw, $ch)))
        $g.Dispose()
        $out = Join-Path $DataDir ('shot-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.png')
        if ($scale -lt 1.0) {
            $nw = [Math]::Max(1, [int]($cw * $scale)); $nh = [Math]::Max(1, [int]($ch * $scale))
            $bmp2 = New-Object System.Drawing.Bitmap($nw, $nh)
            $g2 = [System.Drawing.Graphics]::FromImage($bmp2)
            $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g2.DrawImage($bmp, 0, 0, $nw, $nh)
            $g2.Dispose()
            $bmp.Dispose()
            $bmp2.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp2.Dispose()
        } else {
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
        return $out
    } catch { Write-Err ('SHOT-ERR ' + $_.Exception.Message); return $null }
}

function Invoke-VisionLlm([string]$imagePath, [string]$title) {
    try {
        $key = Get-ApiKey
        if (-not $key) { return $null }
        if ((Get-Item $imagePath).Length -gt 1048576) { return '这张图有点大，我看不清' }
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($imagePath))
        if ($null -eq $script:visionHttp) {
            $script:visionHttp = New-Object System.Net.Http.HttpClient
            $script:visionHttp.Timeout = [TimeSpan]::FromSeconds(40)
        }
        $what = if ($title) { '窗口（标题：' + $title + '）' } else { '屏幕画面' }
        $q = '这是电脑上的' + $what + '。看图回答主人：如果里面是文字，读出标题和关键内容；如果是图片，描述画面（人物、风景、物品、颜色）。中文口语化，40字以内。'
        $arr = @(
            @{ type = 'text'; text = $q },
            @{ type = 'image_url'; image_url = @{ url = ('data:image/png;base64,' + $b64) } }
        )
        $body = @{ model = 'deepseek-flash'; messages = @( @{ role = 'user'; content = $arr } ); max_tokens = 120; temperature = 0.3; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 10
        $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $req.Content = $content
        $resp = $script:visionHttp.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $reply = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        if ($reply) { return $reply.Trim() }
    } catch { Write-Err ('VISION-ERR ' + $_.Exception.Message) }
    return $null
}

function Capture-AtCursor([int]$px, [int]$py) {
    try {
        $wa2 = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $cw = 900; $ch = 600
        $cl = [Math]::Max($wa2.Left, $px - [int]($cw / 2))
        $ct = [Math]::Max($wa2.Top, $py - [int]($ch / 2))
        if (($cl + $cw) -gt $wa2.Right) { $cl = $wa2.Right - $cw }
        if (($ct + $ch) -gt $wa2.Bottom) { $ct = $wa2.Bottom - $ch }
        if ($cl -lt $wa2.Left) { $cl = $wa2.Left }
        if ($ct -lt $wa2.Top) { $ct = $wa2.Top }
        $wasVisible = $false
        try { $wasVisible = $form.Visible; $form.Hide() } catch { }
        Start-Sleep -Milliseconds 160
        $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($cl, $ct, 0, 0, (New-Object System.Drawing.Size($cw, $ch)))
        $g.Dispose()
        if ($wasVisible) { try { $form.Show() } catch { } }
        $out = Join-Path $DataDir ('shot-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.png')
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        return $out
    } catch {
        try { $form.Show() } catch { }
        Write-Err ('SHOT2-ERR ' + $_.Exception.Message)
        return $null
    }
}

function Analyze-UnderCursor {
    try {
        if (-not $script:lookOnDrag) { return }
        if ($script:visionPending) { return }
        $pos = [System.Windows.Forms.Cursor]::Position
        $myPid = [uint32][System.Diagnostics.Process]::GetCurrentProcess().Id
        $title = ''
        $info = $null
        try { $info = [WinPick]::Pick($pos.X, $pos.Y, $form.Handle, $myPid) } catch { }
        if ($info) {
            $parts = $info -split "`t"
            if ($parts.Count -ge 2) { $title = [string]$parts[1] }
            if (-not $title -and $parts.Count -ge 3) { $title = [string]$parts[2] }
        }
        $key2 = ('{0}x{1}' -f [int]($pos.X / 50), [int]($pos.Y / 50))
        $now = Get-Date
        if ($script:lastShotWin -eq $key2 -and ($null -ne $script:lastShotAt) -and ($now - $script:lastShotAt).TotalSeconds -lt 15) { return }
        $script:lastShotWin = $key2
        $script:lastShotAt = $now
        $png = $null
        $via = 'area'
        if ($info) {
            $png = Capture-Window $info
            if ($png) { $via = 'window' }
        }
        if (-not $png) { $png = Capture-AtCursor $pos.X $pos.Y }
        if (-not $png) { return }
        $key = Get-ApiKey
        if (-not $key) { Show-Bubble '没有密钥，看不了'; return }
        if (-not $title) { $title = '屏幕画面' }
        $outFile = Join-Path $DataDir ('vision-out-' + [guid]::NewGuid().ToString('N') + '.json')
        $worker = Join-Path (Split-Path -Parent $PSCommandPath) 'vision_worker.ps1'
        if (-not (Test-Path $worker)) { Show-Bubble '缺识图脚本'; return }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $worker, '-Image', $png, '-Title', $title, '-Out', $outFile, '-Key', $key)
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden | Out-Null
        $script:visionPending = @{ out = $outFile; png = $png; at = Get-Date }
        Show-Bubble '让我看看…'
        Write-Err ('VISION-START via=' + $via + ' title=' + $title + ' shot=' + $png)
    } catch { Write-Err ('ANALYZE-ERR ' + $_.Exception.Message) }
}

# 流水线调度：边合成边播
$script:ttsTimer = New-Object System.Windows.Forms.Timer
$script:ttsTimer.Interval = 90
