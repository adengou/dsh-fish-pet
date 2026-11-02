# ============================================================
# vision_worker.ps1 — 截图问答后台工作脚本
# 依赖声明（自动生成，勿手改）：
#   主脚本提供: (无函数依赖)
#   $script 变量: (无)
# ============================================================

# vision_worker.ps1 · 截图问答的后台识图进程（不阻塞鱼）
# 用法: powershell -File vision_worker.ps1 -Image <png> -Title <窗口标题> -Out <结果json> -Key <apiKey>
param(
    [string]$Image,
    [string]$Title = '',
    [string]$Out,
    [string]$Key
)

try {
    if (-not $Image -or -not (Test-Path $Image)) { exit }
    if (-not $Out) { exit }
    if (-not $Key) { exit }
    $size = (Get-Item $Image).Length
    if ($size -gt 1048576) { $result = '这张图太大，我看不清' } else {
        Add-Type -AssemblyName System.Net.Http
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Image))
        $what = if ($Title) { '窗口（标题：' + $Title + '）' } else { '屏幕画面' }
        $q = '这是电脑上的' + $what + '。看图回答主人：如果里面是文字，读出标题和关键内容；如果是图片，描述画面（人物、风景、物品、颜色）。中文口语化，40字以内。'
        $arr = @(
            @{ type = 'text'; text = $q },
            @{ type = 'image_url'; image_url = @{ url = ('data:image/png;base64,' + $b64) } }
        )
        $body = @{ model = 'deepseek-flash'; messages = @(@{ role = 'user'; content = $arr }); max_tokens = 120; temperature = 0.3; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 10
        $http = New-Object System.Net.Http.HttpClient
        $http.Timeout = [TimeSpan]::FromSeconds(60)
        $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.deepseek.com/chat/completions')
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Key)
        $req.Content = $content
        $resp = $http.SendAsync($req).GetAwaiter().GetResult()
        $jsonText = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $result = [string](($jsonText | ConvertFrom-Json).choices[0].message.content)
        if (-not $result) { $result = '这块画面我看不太清' }
    }
    $obj = @{ text = $result.Trim() } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($Out, $obj, (New-Object Text.UTF8Encoding($false)))
} catch {
    try {
        $fail = @{ text = '' } | ConvertTo-Json -Compress
        if ($Out) { [IO.File]::WriteAllText($Out, $fail, (New-Object Text.UTF8Encoding($false))) }
    } catch { }
}
