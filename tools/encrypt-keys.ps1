# encrypt-keys.ps1 · 把明文 key 换成 Windows DPAPI 加密文件
# 用法： powershell -ExecutionPolicy Bypass -File tools\encrypt-keys.ps1
# 加密后生成 <name>.key.enc 并删除明文 <name>.key；鱼和耳朵会优先读 .enc

$dir = Join-Path $env:USERPROFILE '.dsh\fish-pet'
if (-not (Test-Path $dir)) { Write-Host "找不到数据目录：$dir"; exit 1 }

$encrypted = 0
foreach ($name in @('deepseek', 'siliconflow')) {
    $plain = Join-Path $dir ($name + '.key')
    if (-not (Test-Path $plain)) { continue }
    $v = (Get-Content -LiteralPath $plain -Raw -ErrorAction SilentlyContinue)
    if (-not $v) { continue }
    $v = $v.Trim()
    if (-not $v) { continue }
    $enc = Join-Path $dir ($name + '.key.enc')
    $v | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString |
        Set-Content -LiteralPath $enc -NoNewline
    Remove-Item $plain -Force
    Write-Host "$name：已加密 -> $enc"
    $encrypted++
}

if ($encrypted -eq 0) {
    Write-Host "没有找到可加密的明文 key（可能已经加密过）"
} else {
    Write-Host "完成，共加密 $encrypted 个。加密只能在本机当前用户下解开。"
}
