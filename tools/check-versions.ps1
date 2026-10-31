# check-versions.ps1 · 检查 Gitee / GitHub / npm 三个渠道的版本是否一致
# 用法：powershell -ExecutionPolicy Bypass -File tools\check-versions.ps1
# 退出码：0 = 全部一致；1 = 有不一致

$ErrorActionPreference = 'Stop'
$pkgDir = Split-Path -Parent $PSScriptRoot
$reg = 'https://registry.npmjs.org'

Push-Location $pkgDir
try {
    $localVer = (Get-Content 'package.json' -Raw | ConvertFrom-Json).version

    $gitVer = ''
    try { $gitVer = (git show HEAD:package.json | Out-String | ConvertFrom-Json).version } catch { $gitVer = '(读取失败)' }

    $gitHubVer = ''
    try { $gitHubVer = (git show 'github/main:package.json' | Out-String | ConvertFrom-Json).version } catch { $gitHubVer = '(未同步)' }

    $npmVer = ''
    try {
        $npmVer = (& npm view dsh-fish-pet version --registry=$reg 2>$null | Out-String).Trim()
        if (-not $npmVer) { $npmVer = '(查询失败)' }
    } catch { $npmVer = '(查询失败)' }

    $gitHead = (git rev-parse --short HEAD 2>$null | Out-String).Trim()
    $gitGitee = (git rev-parse --short origin/main 2>$null | Out-String).Trim()
    $gitGH = (git rev-parse --short github/main 2>$null | Out-String).Trim()

    Write-Host ''
    Write-Host '渠道            版本        提交' -ForegroundColor Cyan
    Write-Host ('本地工作区      {0,-10}  {1}' -f $localVer, $gitHead)
    Write-Host ('Gitee (origin)  {0,-10}  {1}' -f $gitVer, $gitGitee)
    Write-Host ('GitHub          {0,-10}  {1}' -f $gitHubVer, $gitGH)
    Write-Host ('npm (latest)    {0,-10}' -f $npmVer)
    Write-Host ''

    $problems = @()
    if ($localVer -ne $gitVer) { $problems += "本地 package.json($localVer) 与 Gitee($gitVer) 不一致——忘了提交？" }
    if ($gitVer -ne $gitHubVer) { $problems += "Gitee($gitVer) 与 GitHub($gitHubVer) 不一致——GitHub 没推上去" }
    if ($localVer -ne $npmVer) {
        if ($npmVer -match '^\d') {
            $problems += "本地($localVer) 与 npm($npmVer) 不一致——npm 可能还在审核，或没发布"
        } else {
            $problems += "npm 版本查询失败（$npmVer），检查网络或 registry 配置"
        }
    }

    if ($problems.Count -eq 0) {
        Write-Host '✅ 三个渠道版本一致' -ForegroundColor Green
        exit 0
    } else {
        Write-Host '⚠️ 发现不一致：' -ForegroundColor Yellow
        $problems | ForEach-Object { Write-Host ("  - " + $_) -ForegroundColor Yellow }
        Write-Host ''
        Write-Host '提示：npm 发布后要等自动审核（几分钟），审核通过 latest 才会跳到新版本。' -ForegroundColor DarkGray
        exit 1
    }
}
finally {
    Pop-Location
}
