# ============================================================
# reminders.ps1 — 提醒与便签
# 依赖声明（自动生成，勿手改）：
#   主脚本提供: Show-Bubble, Write-Err
#   $script 变量: inputBox, inputDlg, inputText, notesPath, remBtnClear, remBtnClose, remBtnDel, remDlg, remItems, remList, remRefresh
#   被其他模块调用: Get-DueFromText() ← chat.ps1; Load-Notes() ← briefing.ps1; Load-Notes() ← chat.ps1; Save-Note() ← chat.ps1
# ============================================================

# reminders.ps1 · 便签/提醒（数据结构、解析、清单 UI，从主脚本拆出）

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
