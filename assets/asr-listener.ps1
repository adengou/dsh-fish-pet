# asr-listener.ps1 · 云端耳朵（VAD 连续采集版）
# 一次连续采集，检测到"说完"立刻上传，不再固定切片
param(
    [int]$MaxMs = 8000,
    [int]$SilenceMs = 700,
    [int]$Boost = 1,
    [int]$SilenceGate = 600
)

# 单实例：防止耳朵双开（双开会重复识别、重复回话）
try {
    $earMutex = New-Object System.Threading.Mutex($false, 'Global\dsh-fish-ear-single')
    if (-not $earMutex.WaitOne(0)) { exit 0 }
} catch { }
$ErrorActionPreference = 'Stop'
try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
$DataDir = Join-Path $env:USERPROFILE '.dsh\fish-pet'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
$OutFile   = Join-Path $DataDir 'asr.log'
$LevelFile = Join-Path $DataDir 'asr.level'
$ErrFile   = Join-Path $DataDir 'asr.err'
$KeyFile   = Join-Path $DataDir 'siliconflow.key'

# 读外部配置（config.json 里的 voice 段）
$CfgPath = Join-Path $DataDir 'config.json'
if (Test-Path $CfgPath) {
    try {
        $cj = Get-Content -LiteralPath $CfgPath -Raw | ConvertFrom-Json
        if ($cj.voice) {
            if ($cj.voice.silenceGate) { $SilenceGate = [int]$cj.voice.silenceGate }
    if ($cj.voice.silenceMs) { $SilenceMs = [int]$cj.voice.silenceMs }
            if ($cj.voice.boost) { $Boost = [int]$cj.voice.boost }
            if ($cj.voice.engine) { $script:engine = [string]$cj.voice.engine }
            if ($cj.voice.localConf) { $script:localConf = [double]$cj.voice.localConf }
        }
    } catch { }
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class VadEnum { }
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IVadEnum { int EnumAudioEndpoints(int f, int s, out IntPtr c); int GetDefaultAudioEndpoint(int f, int r, out IVadDev d); }
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IVadDev { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IVadClient {
  int Initialize(int share, int flags, long dur, long period, IntPtr fmt, IntPtr sess);
  int GetBufferSize(out uint frames); int GetStreamLatency(out long lat); int GetCurrentPadding(out uint pad);
  int IsFormatSupported(int share, IntPtr fmt, out IntPtr closest); int GetMixFormat(out IntPtr fmt);
  int GetDevicePeriod(out long def, out long min); int Start(); int Stop(); int Reset(); int SetEventHandle(IntPtr e);
  int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
}
[ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IVadCapture {
  int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devpos, out ulong qpc);
  int ReleaseBuffer(uint frames); int GetNextPacketSize(out uint frames);
}

public class EarVad
{
    public static byte[] Pcm;
    public static int RawPeak;
    public static int DurationMs;

    public static bool Capture(int maxMs, int gate, int silenceMs, int boost, int role)
    {
        Pcm = new byte[0]; RawPeak = 0; DurationMs = 0;
        var en = (IVadEnum)(new VadEnum());
        IVadDev dev;
        if (en.GetDefaultAudioEndpoint(1, role, out dev) != 0) { if (en.GetDefaultAudioEndpoint(1, 0, out dev) != 0) return false; }
        Guid iid = typeof(IVadClient).GUID; object o; dev.Activate(ref iid, 1, IntPtr.Zero, out o);
        var ac = (IVadClient)o;
        IntPtr fmt; ac.GetMixFormat(out fmt);
        int rate = Marshal.ReadInt32(fmt, 4);
        short ch = Marshal.ReadInt16(fmt, 2);
        if (ac.Initialize(0, 0, 5000000, 0, fmt, IntPtr.Zero) != 0) return false;
        Guid ci = typeof(IVadCapture).GUID; object co; ac.GetService(ref ci, out co);
        var cc = (IVadCapture)co;
        if (ac.Start() != 0) return false;

        var all = new List<float>();
        var pre = new List<float>();
        bool started = false;
        int silent = 0, total = 0;
        var b4 = new byte[4];
        var end = DateTime.UtcNow.AddMilliseconds(maxMs + 1500);

        while (DateTime.UtcNow < end && total < maxMs)
        {
            uint pkt;
            if (cc.GetNextPacketSize(out pkt) != 0 || pkt == 0) { Thread.Sleep(3); continue; }
            IntPtr data; uint frames, flags; ulong dp, qp;
            if (cc.GetBuffer(out data, out frames, out flags, out dp, out qp) != 0) break;

            int n = (int)frames * ch * 4;
            float peak = 0;
            var buf = new float[frames * ch];
            int k = 0;
            for (int i = 0; i + 3 < n; i += 4)
            {
                b4[0] = Marshal.ReadByte(data, i); b4[1] = Marshal.ReadByte(data, i+1);
                b4[2] = Marshal.ReadByte(data, i+2); b4[3] = Marshal.ReadByte(data, i+3);
                float f = BitConverter.ToSingle(b4, 0);
                buf[k++] = f;
                float a = Math.Abs(f); if (a > peak) peak = a;
            }
            cc.ReleaseBuffer(frames);

            int packetMs = (int)(frames * 1000 / rate);
            total += packetMs;
            int peakInt = (int)(peak * 32767f);

            if (!started)
            {
                pre.AddRange(buf);
                int keep = rate * ch / 3; // 保留最近约 300ms 作为前置
                if (pre.Count > keep * 2) pre.RemoveRange(0, pre.Count - keep);
                if (peakInt >= gate)
                {
                    started = true;
                    all.AddRange(pre);
                    pre.Clear();
                    silent = 0;
                    if (peakInt > RawPeak) RawPeak = peakInt;
                }
            }
            else
            {
                all.AddRange(buf);
                if (peakInt > RawPeak) RawPeak = peakInt;
                if (peakInt < gate) silent += packetMs; else silent = 0;
                // 相邻片段自动合并：短句（有效语音不足 2.5 秒）时放宽断句等待，避免“Hello | MIA”被切成两段
                int effectiveSilence = ((total - silent) >= 2500) ? silenceMs : Math.Max(silenceMs, 800);
                if (silent >= effectiveSilence && (total - silent) >= 1200) break;
            }
        }
        ac.Stop();
        if (!started || all.Count < rate / 2) return false;

        // 轻声增益：整段峰值偏低时放大，响的句子不动
        float maxA = 0; double sumSq = 0; int cntAll = 0;
        for (int i = 0; i < all.Count; i++) { float a = Math.Abs(all[i]); if (a > maxA) maxA = a; sumSq += all[i] * all[i]; cntAll++; }
        double peakInt2 = maxA * 32767.0;
        double gain2 = 1.0;
        // 峰值归一化：把这段音频拉到约 70% 满幅，轻声也能被云端听清
        if (peakInt2 > 200) {
            gain2 = 22936.0 / peakInt2;
            if (gain2 < 1.0) gain2 = 1.0;
            if (gain2 > 35.0) gain2 = 35.0;
            // 极轻的声音额外再提一点（>35 倍会明显失真，所以封顶）
        }

        double step = (double)rate / 16000.0;
        int framesIn = all.Count / ch;
        int outCount = (int)(framesIn / step);
        if (outCount < 1600) return false;
        var pcmBytes = new byte[outCount * 2];
        for (int i = 0; i < outCount; i++)
        {
            int s0 = (int)(i * step);
            int s1 = (int)Math.Min(framesIn - 1, (i + 1) * step);
            double sum = 0; int cnt = 0;
            for (int f = s0; f <= s1; f++) { sum += all[f * ch]; cnt++; }
            int v = cnt > 0 ? (int)((sum / cnt) * 32767.0 * boost * gain2) : 0;
            if (v > 32767) v = 32767; if (v < -32768) v = -32768;
            pcmBytes[i*2] = (byte)(v & 0xFF); pcmBytes[i*2+1] = (byte)((v >> 8) & 0xFF);
        }
        Pcm = pcmBytes;
        DurationMs = (int)(outCount * 1000 / 16000);
        return true;
    }
}
"@

function Write-Wav([string]$path, [byte[]]$pcm) {
    $fs = [IO.File]::Open($path, 'Create', 'Write')
    $bw = New-Object IO.BinaryWriter($fs)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $pcm.Length))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVE')); $bw.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]16000)
    $bw.Write([int]32000); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$pcm.Length)
    $bw.Write($pcm); $bw.Close(); $fs.Close()
}

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


# 用 Windows 自带中文识别（免费、离线）
function Try-Local([string]$wavPath) {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $eng = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Where-Object { $_.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
        if (-not $eng) { return $null }
        $rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine($eng)
        $rec.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
        $rec.SetInputToWaveFile($wavPath)
        $r = $rec.Recognize()
        $rec.Dispose()
        if ($r -and $r.Text) { return @{ text = [string]$r.Text; conf = [double]$r.Confidence } }
    } catch { }
    return $null
}
function Rotate-Log([string]$path) {
    try {
        if (Test-Path $path) {
            if ((Get-Item $path).Length -gt 1MB) {
                $bak = $path + '.1'
                Remove-Item $bak -Force -ErrorAction SilentlyContinue
                Move-Item $path $bak -Force
            }
        }
    } catch { }
}

$script:http = $null
$script:lastFishCheck = Get-Date
Add-Content -LiteralPath $OutFile -Value ("# ear(start) pid=" + $PID) -Encoding UTF8

while ($true) {
    try {
        Rotate-Log $OutFile
        Rotate-Log $LevelFile

        if (Test-Path (Join-Path $DataDir 'asr.talking')) { Start-Sleep -Milliseconds 200; continue }
        $pf = Join-Path $DataDir 'asr.pause'
        if (Test-Path $pf) {
            $age = ((Get-Date) - (Get-Item $pf).LastWriteTime).TotalSeconds
            if ($age -lt 0.6) { Start-Sleep -Milliseconds 200; continue }
        }

        if (((Get-Date) - $script:lastFishCheck).TotalSeconds -gt 30) {
            $script:http = $null
$script:lastFishCheck = Get-Date
            if (Test-Path (Join-Path $DataDir 'asr.stop')) { break }
            $fishAlive = $false
            try {
                $pfile = Join-Path $DataDir 'pet.pid'
                if (Test-Path $pfile) {
                    $pj = Get-Content -LiteralPath $pfile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                    if ($pj -and $pj.pid) { $fishAlive = [bool](Get-Process -Id ([int]$pj.pid) -ErrorAction SilentlyContinue) }
                }
            } catch { }
            if (-not $fishAlive) {
                $vbs = Join-Path $PSScriptRoot 'start-pet.vbs'
                if (-not (Test-Path $vbs)) { $vbs = Join-Path $PSScriptRoot 'fish-pet.vbs' }
                if (Test-Path $vbs) { try { Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $vbs + '"') -WindowStyle Hidden } catch { } }
            }
        }

        $key = $env:SILICONFLOW_API_KEY
        if (-not $key) { $key = Read-Key 'siliconflow' }
        if ($key) { $key = $key.Trim() }
        # 没 key 不再停摆：本地引擎照常录音，只有云端识别这一步会跳过

        $ok = $false
        try { $ok = [EarVad]::Capture($MaxMs, $SilenceGate, $SilenceMs, $Boost, 2) }
        catch {
            # 没有可用麦克风时不再每 0.8 秒刷一次 asr.err：只提示一次，然后慢速重试
            if (-not $script:micWarned) {
                $script:micWarned = $true
                Add-Content -LiteralPath $OutFile -Value ((Get-Date -Format 'HH:mm:ss') + "`tM`t(没有找到麦克风设备，语音输入先歇着)") -Encoding UTF8
            }
            Start-Sleep -Seconds 3
            continue
        }

        # 录音过程中鱼开口说话（或刚说完）→ 这段是自己的声音，丢掉
        $talkF = Join-Path $DataDir 'asr.talking'
        if (Test-Path $talkF) { continue }
        $pauseF = Join-Path $DataDir 'asr.pause'
        if ((Test-Path $pauseF) -and (((Get-Date) - (Get-Item $pauseF).LastWriteTime).TotalSeconds -lt 0.6)) { continue }
        if (-not $ok) {
            Start-Sleep -Milliseconds 80
            continue
        }

        $pcm = [EarVad]::Pcm
        $ms = [EarVad]::DurationMs
        Add-Content -LiteralPath $LevelFile -Value ((Get-Date -Format 'HH:mm:ss') + "`traw=" + [EarVad]::RawPeak + "`tms=" + $ms) -Encoding UTF8
        if ($pcm.Length -lt 3200) { continue }
        if ($ms -lt 400 -or [EarVad]::RawPeak -lt $SilenceGate) { continue }

        Add-Content -LiteralPath $OutFile -Value ((Get-Date -Format 'HH:mm:ss') + "`tH`t(听到声音 " + $ms + "ms)") -Encoding UTF8
        $wav = Join-Path $DataDir ('chunk-' + [guid]::NewGuid().ToString('N') + '.wav')
        Write-Wav $wav $pcm
        try { Copy-Item $wav (Join-Path $DataDir 'last-chunk.wav') -Force } catch { }

        $engine = if ($script:engine) { $script:engine } else { 'auto' }
        $confMin = if ($script:localConf) { $script:localConf } else { 0.55 }
        # 没 key 时 cloud 退到本机识别，避免整只耳朵空转（只提示一次）
        if (-not $key -and $engine -eq 'cloud') {
            $engine = 'local'
            if (-not $script:keyWarned) {
                $script:keyWarned = $true
                Add-Content -LiteralPath $OutFile -Value ((Get-Date -Format 'HH:mm:ss') + "`tK`t(未配置 SiliconFlow key，暂用本机识别；放入 siliconflow.key 后自动切回云端)") -Encoding UTF8
            }
        }
        $text = $null
        $via = ''
        if ($engine -ne 'cloud') {
            $lr = Try-Local $wav
            if ($lr -and $lr.text) {
                if ($engine -eq 'local' -or $lr.conf -ge $confMin) { $text = $lr.text; $via = 'local' }
            }
        }
        if (-not $text -and $engine -ne 'local' -and $key) {
            if ($null -eq $script:http) {
                $script:http = New-Object System.Net.Http.HttpClient
                $script:http.Timeout = [TimeSpan]::FromSeconds(30)
                $script:http.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
            }
            $json = ''
            try {
                $mp = New-Object System.Net.Http.MultipartFormDataContent
                $bytes = [IO.File]::ReadAllBytes($wav)
                $bc = New-Object System.Net.Http.ByteArrayContent((,$bytes))
                $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('audio/wav')
                $mp.Add($bc, 'file', 'a.wav')
                $mp.Add((New-Object System.Net.Http.StringContent('Qwen/Qwen3-ASR-1.7B')), 'model')
                # 语言锁定：跟随主程序当前语言模式（zh/en）；auto 时保持自动判断
                $langHint = ''
                try {
                    $cj2 = Get-Content -LiteralPath $CfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
                    if ($cj2.persona -and $cj2.persona.lang) {
                        $lm = [string]$cj2.persona.lang
                        if ($lm -eq 'zh' -or $lm -eq 'en') { $langHint = $lm }
                    }
                } catch { }
                if ($langHint) { $mp.Add((New-Object System.Net.Http.StringContent($langHint)), 'language') }
                $resp = $script:http.PostAsync('https://api.siliconflow.cn/v1/audio/transcriptions', $mp).GetAwaiter().GetResult()
                $json = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                try { $resp.Dispose(); $mp.Dispose() } catch { }
            } catch { try { Add-Content -LiteralPath $ErrFile -Value ((Get-Date -Format 'HH:mm:ss') + '  HTTP ' + $_.Exception.Message) -Encoding UTF8 } catch { } }
            if ($json) {
                try { $obj = $json | ConvertFrom-Json; $text = [string]$obj.text; $via = 'cloud' } catch { }
            }
        }
        Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue
        Add-Content -LiteralPath $LevelFile -Value ((Get-Date -Format 'HH:mm:ss') + "`tengine=" + $via + "`ttext=" + $text) -Encoding UTF8
        if ($text) { $text = $text.Trim() }
        # 过滤乱语种：泰文/日文假名/西里尔/阿拉伯等说明识别跑偏了，当没听清
        if ($text -and ($text -match '[\u0e00-\u0eff\u3040-\u30ff\u0400-\u04ff\u0600-\u06ff]')) {
            Add-Content -LiteralPath $OutFile -Value ((Get-Date -Format 'HH:mm:ss') + "`t?`t(识别跑偏：" + $text + ")") -Encoding UTF8
            $text = ''
        }
        if (-not $text -and [EarVad]::RawPeak -ge 800) {
            Add-Content -LiteralPath $OutFile -Value ((Get-Date -Format 'HH:mm:ss') + "`t?`t(没听清)") -Encoding UTF8
        }
        if ($text -and ($text -match '[\u4e00-\u9fa5]' -or $text.Length -ge 4)) {
            Add-Content -LiteralPath $OutFile -Value ((Get-Date -Format 'HH:mm:ss') + "`t1`t" + $text) -Encoding UTF8
        }
        Start-Sleep -Milliseconds 60
    } catch {
        Add-Content -LiteralPath $ErrFile -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $_.Exception.Message) -Encoding UTF8
        Start-Sleep -Milliseconds 800
    }
}
