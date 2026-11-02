# ============================================================
# smoke-test.ps1 — 桌宠冒烟测试
#
# 改完代码先跑这个，不用每次手动重启鱼试探。
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\smoke-test.ps1
#   powershell -ExecutionPolicy Bypass -File tools\smoke-test.ps1 -Start   # 额外真启动一次鱼
#
# 检查项：
#   1. 所有 .ps1 语法可解析
#   2. 主脚本 dot-source 的模块文件都存在
#   3. 模块间调用的函数都有定义（不会运行时报“无法识别”）
#   4. 数据文件（melodies.json / poems.json）可解析且有内容
#   5. Python 外置脚本可通过 py_compile
#   6. （-Start）真实启动鱼，确认进程存活且菜单构建成功
# ============================================================
param(
    [switch]$Start,
    [int]$WaitSec = 12
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $root 'assets'
$lib = Join-Path $assets 'lib'
$fail = 0
$warn = 0

function Ok([string]$msg) { Write-Host ('  [OK]   ' + $msg) -ForegroundColor Green }
function Bad([string]$msg) { Write-Host ('  [FAIL] ' + $msg) -ForegroundColor Red; $script:fail++ }
function Warn([string]$msg) { Write-Host ('  [WARN] ' + $msg) -ForegroundColor Yellow; $script:warn++ }
function Section([string]$t) { Write-Host ''; Write-Host ('== ' + $t + ' ==') -ForegroundColor Cyan }

# ---------- 1. 语法 ----------
Section '1. 语法检查'
$psFiles = @(Get-ChildItem $assets -Filter '*.ps1' -File) + @(Get-ChildItem $lib -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
foreach ($f in $psFiles) {
    $err = $null; $tok = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err)
    if ($err -and $err.Count -gt 0) {
        Bad ("{0}: {1} 处语法错误（首个在第 {2} 行）" -f $f.Name, $err.Count, $err[0].Extent.StartLineNumber)
    } else {
        Ok $f.Name
    }
}

# ---------- 2. 模块加载 ----------
Section '2. 模块文件完整性'
$mainPath = Join-Path $assets 'fish-pet.ps1'
if (-not (Test-Path $mainPath)) {
    Bad 'assets\fish-pet.ps1 不存在'
} else {
    $mainText = [IO.File]::ReadAllText($mainPath, [Text.Encoding]::UTF8)
    $refs = [regex]::Matches($mainText, "lib\\([A-Za-z0-9_\-\.]+\.ps1)")
    $names = @($refs | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($names.Count -eq 0) { Warn '未在主脚本中找到 lib\*.ps1 的引用' }
    foreach ($n in $names) {
        $p = Join-Path $lib $n
        if (Test-Path $p) { Ok ("已加载模块 $n") } else { Bad ("主脚本引用了 $n，但文件不存在") }
    }
    # 反向：磁盘上有但没被加载
    foreach ($f in Get-ChildItem $lib -Filter '*.ps1' -File -ErrorAction SilentlyContinue) {
        if ($names -notcontains $f.Name) { if ($f.Name -like '*_worker.ps1') { Ok ("$($f.Name) 是外置 worker（不作为模块加载，正常）") } else { Warn ("$($f.Name) 存在于 lib，但主脚本没有 dot-source") } }
    }
}

# ---------- 3. 跨模块函数调用 ----------
Section '3. 函数定义完整性'
$allFuncs = @{}
foreach ($f in $psFiles) {
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($t, '(?m)^\s*function\s+([A-Za-z0-9_\-]+)')) {
        $allFuncs[$m.Groups[1].Value] = $f.Name
    }
}
$known = @{}
foreach ($c in (Get-Command -CommandType Cmdlet, Function -ErrorAction SilentlyContinue)) { $known[$c.Name] = $true }
foreach ($f in Get-ChildItem $lib -Filter '*.ps1' -File -ErrorAction SilentlyContinue) {
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $calls = [regex]::Matches($t, '(?m)^(?![ \t]*#)(?![ \t]*function)[^\n]*?(\b[A-Z][A-Za-z0-9]+-[A-Z][A-Za-z0-9]+\b)\s*(?:\(|\s)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    $missing = @($calls | Where-Object { -not $allFuncs.ContainsKey($_) -and -not $known.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        Bad ("{0} 调用了既非内置、也未定义的命令: {1}" -f $f.Name, ($missing -join ', '))
    } else {
        Ok ("$($f.Name) 调用的命令都有定义或为内置")
    }
}

# ---------- 4. 数据文件 ----------
Section '4. 数据文件'
Push-Location $root
try {
    $mj = Join-Path $assets 'data\melodies.json'
    if (Test-Path $mj) {
        $j = [IO.File]::ReadAllText($mj, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $cnt = @($j.songs).Count
        if ($cnt -gt 0) { Ok ("melodies.json：$cnt 首（$((@($j.songs) | ForEach-Object { $_.name }) -join ' / ')）") }
        else { Bad 'melodies.json 没有曲目' }
        foreach ($s in @($j.songs)) {
            if (-not $s.notes -or @($s.notes).Count -eq 0) { Bad ("曲目 $($s.name) 没有音符") }
        }
    } else { Bad 'melodies.json 不存在' }

    $pj = Join-Path $assets 'data\poems.json'
    if (Test-Path $pj) {
        $p = [IO.File]::ReadAllText($pj, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $pc = if ($p.poems) { @($p.poems).Count } else { 0 }
        if ($pc -gt 0) { Ok ("poems.json：$pc 首") } else { Warn 'poems.json 没有诗' }
    } else { Warn 'poems.json 不存在' }
} finally { Pop-Location }

# ---------- 5. Python 外置脚本 ----------
Section '5. Python 脚本'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Warn '本机没有 python，跳过'
} else {
    foreach ($f in Get-ChildItem $assets -Filter '*.py' -File) {
        $out = & python -m py_compile $f.FullName 2>&1
        if ($LASTEXITCODE -eq 0) { Ok $f.Name } else { Bad ("$($f.Name) 编译失败: $($out -join ' ')") }
    }
}

# ---------- 6. 真启动 ----------
if ($Start) {
    Section '6. 真启动测试'
    $runDir = Join-Path $env:USERPROFILE '.dsh\fish-pet'
    $vbs = Join-Path $runDir 'fish-pet.vbs'
    if (-not (Test-Path $vbs)) {
        Bad "找不到 $vbs"
    } else {
        $log = Join-Path $runDir 'error.log'
        Remove-Item $log -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $runDir 'pet.pid') -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $vbs + '"')
        Start-Sleep -Seconds $WaitSec
        $me = $PID
        $proc = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -match 'fish-pet\.ps1' })
        if ($proc.Count -ge 1) { Ok ("鱼已启动，PID " + (($proc | ForEach-Object { $_.ProcessId }) -join ',')) }
        else { Bad '鱼没有启动（没有进程）' }
        if (Test-Path $log) {
            $txt = [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8)
            if ($txt -match 'MUSIC-MENU') { Ok '菜单构建成功' } else { Warn '日志里没有 MUSIC-MENU' }
            if ($txt -match 'THREAD-EXC|Unhandled') { Bad '日志里有未处理异常' }
            if ($txt -match 'TTS-WORKER-START') { Ok 'TTS worker 已启动' }
        } else { Warn '没有生成 error.log' }
    }
}

# ---------- 汇总 ----------
Write-Host ''
if ($fail -eq 0) {
    Write-Host ("✅ 冒烟测试通过（警告 $warn 条）") -ForegroundColor Green
    exit 0
} else {
    Write-Host ("❌ 冒烟测试失败：$fail 项失败，警告 $warn 条") -ForegroundColor Red
    exit 1
}
