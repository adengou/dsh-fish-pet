# publish.ps1 · 发布 dsh-fish-pet 到 npm（token 只在本机内存/临时 .npmrc 中出现）
# 用法：在 PowerShell 里运行
#   powershell -ExecutionPolicy Bypass -File tools\publish.ps1
# token 输入时不回显；发布完自动删除 .npmrc 里的那一行

$ErrorActionPreference = 'Stop'
$pkgDir = Split-Path -Parent $PSScriptRoot
$npmrc = Join-Path $env:USERPROFILE '.npmrc'
$registry = 'https://registry.npmjs.org'

Write-Host "包目录: $pkgDir" -ForegroundColor Cyan
Push-Location $pkgDir
try {
    $pkg = Get-Content "package.json" -Raw | ConvertFrom-Json
    Write-Host "将发布: $($pkg.name)@$($pkg.version)" -ForegroundColor Cyan

    # 确认没登录也继续（下面用一次性 token）
    $secure = Read-Host "粘贴 npm Granular Token（npm_ 开头，输入不回显）" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $token = $token.Trim()
    if (-not $token.StartsWith('npm_')) { throw "token 格式不对（应以 npm_ 开头）" }

    # 备份 .npmrc，追加临时认证行
    $backup = $null
    if (Test-Path $npmrc) { $backup = Get-Content $npmrc -Raw } else { $backup = '' }
    try {
        $line = "//registry.npmjs.org/:_authToken=$token"
        [IO.File]::AppendAllText($npmrc, "`r`n$line`r`n", (New-Object Text.UTF8Encoding($false)))

        Write-Host "`n正在发布到 $registry ..." -ForegroundColor Yellow
        & npm publish --registry=$registry
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host "发布失败（exit $code）" -ForegroundColor Red }
        else { Write-Host "`n发布成功：https://www.npmjs.com/package/$($pkg.name)" -ForegroundColor Green }
    }
    finally {
        # 还原 .npmrc（彻底去掉 token）
        [IO.File]::WriteAllText($npmrc, $backup, (New-Object Text.UTF8Encoding($false)))
        $left = (Select-String -Path $npmrc -Pattern 'npm_' -ErrorAction SilentlyContinue).Count
        Write-Host ".npmrc 已还原（残留 token 行: $left）" -ForegroundColor Cyan
    }
}
finally {
    Pop-Location
}
