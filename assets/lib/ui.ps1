# ============================================================
# ui.ps1 — 气泡与输入框（WinForms 弹窗）
# 依赖声明（自动生成，勿手改）：见 tools\add-module-headers.py 输出
# ============================================================

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
