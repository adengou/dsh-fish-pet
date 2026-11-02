# dsh.ps1 · 鱼 → DSH 任务转交（通过插件本机路由 /fishpet/task）
# 依赖主脚本：Show-Bubble / Speak-Text / Write-Err / Get-ApiKey

# 把一段任务文字交给 DSH（新开一个会话），成功返回 $true
function Send-DshTask([string]$text) {
    try {
        if (-not $text -or -not $text.Trim()) { return $false }
        $text = $text.Trim()
        # 工作目录：优先 config.json 的 dsh.cwd，其次主人常用的 F 盘工作目录
        $cwd = ''
        try { if ($script:cfg.dsh -and $script:cfg.dsh.cwd) { $cwd = [string]$script:cfg.dsh.cwd } } catch { }
        if (-not $cwd) { $cwd = 'F:\李智梅党建工作材料' }
        $body = @{ text = $text; cwd = $cwd } | ConvertTo-Json -Compress
        $http = New-Object System.Net.Http.HttpClient
        $http.Timeout = [TimeSpan]::FromSeconds(30)
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'http://127.0.0.1:3080/fishpet/task')
        $req.Content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $resp = $http.SendAsync($req).GetAwaiter().GetResult()
        $json = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $obj = $null
        try { $obj = $json | ConvertFrom-Json } catch { }
        if ($obj -and $obj.ok) {
            Show-Bubble '任务已交给 DSH 会话，去网页看结果～'
            Speak-Text '任务已经交给 DSH 了'
            Write-Err ('DSH-TASK ok sid=' + [string]$obj.sessionId + ' text=' + $text)
            return $true
        }
        Show-Bubble 'DSH 那边没接住任务'
        Write-Err ('DSH-TASK-FAIL ' + $json)
        return $false
    } catch {
        Write-Err ('DSH-TASK-ERR ' + $_.Exception.Message)
        Show-Bubble '连不上 DSH（要重启一次 DSH 才有这条路）'
        return $false
    }
}

# 简易输入框：弹窗输入任务，交给 DSH
function Show-DshTaskInput {
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '交给 DSH 助手'
        $dlg.Size = New-Object System.Drawing.Size(480, 230)
        $dlg.StartPosition = 'CenterScreen'
        $dlg.TopMost = $true
        $dlg.FormBorderStyle = 'FixedDialog'
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Multiline = $true
        $tb.ScrollBars = 'Vertical'
        $tb.Location = New-Object System.Drawing.Point(14, 14)
        $tb.Size = New-Object System.Drawing.Size(440, 130)
        $tb.Font = New-Object System.Drawing.Font('Microsoft YaHei', 10)
        $dlg.Controls.Add($tb)
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = '交给它'
        $ok.Location = New-Object System.Drawing.Point(280, 156)
        $ok.Size = New-Object System.Drawing.Size(80, 30)
        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = '算了'
        $cancel.Location = New-Object System.Drawing.Point(374, 156)
        $cancel.Size = New-Object System.Drawing.Size(80, 30)
        $dlg.Controls.Add($ok)
        $dlg.Controls.Add($cancel)
        $ok.Add_Click({ $script:dshInputText = $tb.Text; $dlg.Close() })
        $cancel.Add_Click({ $script:dshInputText = ''; $dlg.Close() })
        $dlg.Add_Shown({ $tb.Focus() })
        [void]$dlg.ShowDialog()
        $text = [string]$script:dshInputText
        if ($text.Trim()) { Send-DshTask $text | Out-Null }
    } catch { Write-Err ('DSH-INPUT-ERR ' + $_.Exception.Message) }
}
