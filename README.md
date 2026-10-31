# dsh-fish-pet · 桌面蓝鱼

[![Gitee Star](https://gitee.com/adengou/dsh-fish-pet/badge/star.svg?theme=dark)](https://gitee.com/adengou/dsh-fish-pet/stargazers)
[![Gitee Fork](https://gitee.com/adengou/dsh-fish-pet/badge/fork.svg?theme=dark)](https://gitee.com/adengou/dsh-fish-pet/members)
[![GitHub Stars](https://img.shields.io/github/stars/adengou/dsh-fish-pet?style=social)](https://github.com/adengou/dsh-fish-pet/stargazers)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

![dsh-fish-pet](https://gitee.com/adengou/dsh-fish-pet/raw/main/docs/banner.png)


给 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 养一条住在 Windows 桌面上的蓝鱼。
它不是网页贴图：是一个**逐像素透明的置顶窗口**，用 PowerShell + WinForms 逐帧绘制，还能**听你说话、跟你聊天、用中文语音回你**。

## 一分钟了解

| 它能做什么 | 说明 |
| --- | --- |
| 🐟 **住在桌面上** | 逐像素透明置顶窗口，程序不到 100KB——纯 PowerShell + WinForms 手写逐帧绘制 |
| 🎤 **听你说话** | WASAPI 连续采集 + 自研 VAD，说完自动识别（硅基流动 Qwen3-ASR） |
| 💬 **跟你聊天** | 接 DeepSeek，带人设、记得上下文、情绪会写在语气里 |
| 🔊 **念给你听** | 微软 Edge 免费音色（默认晓晓），中英文自动切换音色 |
| 😊 **有情绪** | 饥饿值 / 亲密度 / 心情，开心睁眼、委屈半垂带泪、生气压低 |
| 📝 **记事与提醒** | 说"十分钟后提醒我喝水"，到点主动喊你 |
| 🍚 **能喂** | 点一下就喂白饭，会冒爱心、撒娇 |

> 个人作品，与 DeepSeek 官方无关。需要自备两个 API key（对话 + 语音识别），不是免费服务。

## 速览

```powershell
# 1) 装成 DSH 插件（推荐）
dsh plugin --profile web add "git+https://gitee.com/adengou/dsh-fish-pet.git"

# 2) 配两个 key（各写一行，只放 key 本身）
mkdir "$env:USERPROFILE\.dsh\fish-pet" -Force
Set-Content "$env:USERPROFILE\.dsh\fish-pet\deepseek.key"    -Value "sk-..." -NoNewline
Set-Content "$env:USERPROFILE\.dsh\fish-pet\siliconflow.key" -Value "sk-..." -NoNewline

# 3) 想要更自然的朗读音色（可选，免费）
python -m pip install --upgrade edge-tts

# 4) 重启 dsh web，鱼就来了
```

不装 DSH 也能单独跑：

```powershell
wscript.exe assets\start-pet.vbs   # 桌面鱼
wscript.exe assets\start-ear.vbs   # 语音耳朵（可选）
```


## 特性

- 桌面常驻：全屏随机游动、随机停歇、眨眼、吐泡泡、尾巴与鱼鳍摆动
- 交互：拖动换位置、左键喂食、右键菜单（大小 / 回家 / 语音朗读 / 提醒 / 清除记忆 / 退出）
- 聊天：输入框打字或语音 → 调 `deepseek-flash` → 气泡回复 + 语音朗读
- **语音对话**：独立"耳朵"进程用 WASAPI 采集麦克风 → 云端 Qwen3-ASR 识别 → 自动接话（说完约 1 秒内开始回）
- **语音朗读**：默认用微软 Edge 的 `zh-CN-XiaoyiNeural` 少女音（免费、无需 Key，可换音色/语速/音调）
- **情绪系统**：饥饿值、亲密度、心情（开心/委屈/饿/被冷落），会体现在语气、表情和配音上
- **记忆**：最近 24 条对话 + 长期摘要 + 主人交代的便签 + 定时提醒（到点主动开口）
- 单实例守卫、异常落盘（不弹框）、耳朵掉线自动重启、位置记忆、开机自启

## 环境要求

| 依赖 | 是否必需 | 用途 |
| --- | --- | --- |
| Windows 10 / 11 | **必需** | 桌面窗口与 PowerShell 运行环境 |
| PowerShell 5.1 | 必需（系统自带） | 运行鱼和耳朵脚本 |
| Node.js ≥ 22 | 作为 DSH 插件时必需 | 插件宿主 |
| 麦克风 | 语音对话需要 | WASAPI 采集 |
| **Python 3.8+** | **可选** | 仅用于「微软 Edge 云语音」（音色更自然） |
| **edge-tts**（pip 包） | 可选 | 同上，缺它就自动退回本机 SAPI 语音 |

### 关于 Python / edge-tts（语音朗读）

鱼默认用微软 Edge 的云音色朗读（免费、无需 API Key），需要本机有 Python 3 和 `edge-tts`：

```powershell
python -m pip install --upgrade edge-tts
```

- **没装也没关系**：鱼会自动退回 Windows 自带的 SAPI 语音（`Microsoft Huihui`），能听，但音色比较生硬
- 启动时如果检测到缺 Python 或 `edge-tts`，鱼会冒泡提示一次，并把 `config.json` 的 `tts.engine` 自动切到 `sapi`
- 装好 Python 后把 `tts.engine` 改回 `edge`、重启鱼，就能用少女音

## 安装

### 方式一：作为 DSH 插件

`dsh plugin` 把参数原样转给 pnpm，所以下面几种来源都能用，装完**重启 `dsh web`** 生效。

**① 直接从仓库装（推荐，已验证）**

```powershell
dsh plugin --profile web add "git+https://gitee.com/adengou/dsh-fish-pet.git"
```

**② 从 npm 装（快照版，可能落后于仓库）**

```powershell
dsh plugin --profile web add dsh-fish-pet
```

> npm 页面：https://www.npmjs.com/package/dsh-fish-pet
>
> ⚠️ npm 上是 **0.2.4 快照**，之后仓库里的修复（Python 依赖说明、启动自检等）尚未同步到 npm。想要最新功能请用 ① 从仓库装。

**③ 从本地目录 / 离线 tgz 装**

```powershell
dsh plugin --profile web add "file:C:/path/to/dsh-fish-pet"
dsh plugin --profile web add "file:C:/path/to/dsh-fish-pet-0.2.0.tgz"
```

**④ 从服务器上的 tgz 直链装**（把 tgz 传到 Release / 图床等可直链的地方）

```powershell
dsh plugin --profile web add "https://你的地址/dsh-fish-pet-0.2.0.tgz"
```

**⑤ 从 GitHub 装**

```powershell
dsh plugin --profile web add github:adengou/dsh-fish-pet
```

> 仓库地址：https://github.com/adengou/dsh-fish-pet（与 Gitee 同步维护）

> 版本要求：DSH `>= 0.2.1-rc.5`。版本不符时插件行会被判不兼容而禁用。

### 方式二：独立运行（不装 DSH 也能用）

```powershell
wscript.exe assets\start-pet.vbs   # 桌面鱼
wscript.exe assets\start-ear.vbs   # 云端耳朵（语音对话用）
```

## 配置密钥（重要）

本仓库**不包含任何密钥**。两个 key 的读取顺序：

| 用途 | 环境变量（优先） | 文件（次选） |
| --- | --- | --- |
| 对话模型（DeepSeek） | `DEEPSEEK_API_KEY` | `<数据目录>\deepseek.key` |
| 语音识别（SiliconFlow） | `SILICONFLOW_API_KEY` | `<数据目录>\siliconflow.key` |

- `<数据目录>` 默认 `%USERPROFILE%\.dsh\fish-pet`
- 兼容 DSH：DeepSeek key 找不到时还会读 `%USERPROFILE%\.dsh\.credentials.yaml` 的 `DEEPSEEK_API_KEY`
- 密钥文件已在 `.gitignore` 里，请勿提交

### 快速配置（PowerShell）

```powershell
mkdir "$env:USERPROFILE\.dsh\fish-pet" -Force

Set-Content "$env:USERPROFILE\.dsh\fish-pet\deepseek.key"    -Value "sk-你的DeepSeek密钥"    -NoNewline
Set-Content "$env:USERPROFILE\.dsh\fish-pet\siliconflow.key" -Value "sk-你的硅基流动密钥" -NoNewline
```

注意事项：

- 文件里**只放 key 本身**，一行、不加引号、不加说明文字
- 用记事本也行：`Win+R` → `%USERPROFILE%\.dsh\fish-pet` → 新建 `deepseek.key` / `siliconflow.key`（注意扩展名别留 `.txt`）
- 想改用环境变量：`setx DEEPSEEK_API_KEY "sk-..."` 和 `setx SILICONFLOW_API_KEY "sk-..."`，之后重开进程生效
- 验证：`Get-ChildItem "$env:USERPROFILE\.dsh\fish-pet\*.key" | Select-Object Name, Length`

> ⚠️ 不要把真实 key 写进 README 或任何提交到仓库的文件——仓库是公开的。

### 加密保存 key（可选，更安全）

明文 key 文件容易被别的程序读走。项目自带一个工具，可以把它们换成 **Windows DPAPI 加密**（只能在本机当前用户下解开）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\encrypt-keys.ps1
```

之后鱼和耳朵会优先读 `deepseek.key.enc` / `siliconflow.key.enc`，明文文件会被自动删除。

## 配置文件

首次启动会生成 `%USERPROFILE%\.dsh\fish-pet\config.json`，可以改：

```json
{
  "persona": {
    "name": "大肥鱼",
    "nameEn": "Mia",
    "dad": "光光",
    "mom": "丽丽",
    "birthday": "2026年10月30日",
    "birthplace": "中国广西北海",
    "likes": "白饭、被摸头、主人夸它",
    "dislikes": "被说胖、被冷落、吵",
    "lang": "auto",
    "extra": "你说话简短、俏皮、微微傲娇，称呼用户为\"主人\"，每次回复不超过30个字，不要用表情符号。"
  },
  "bubble": { "opacity": 0.15 },
  "voice": { "silenceGate": 600, "silenceMs": 900, "boost": 1, "engine": "cloud", "localConf": 0.55 },
  "tts": {
    "engine": "edge",
    "voice": "zh-CN-XiaoxiaoNeural",
    "rate": "+12%",
    "pitch": "+10Hz",
    "voiceEn": "en-US-AnaNeural",
    "rateEn": "+8%",
    "pitchEn": "+15Hz"
  }
}
```

- `persona.name`：中文名（说中文时自称）
- `persona.nameEn`：**英文名**（说英文时自称，默认 `Mia`／米娅）
- `persona.dad` / `mom` / `birthday` / `birthplace`：家人、生日、出生地
- `persona.likes` / `dislikes`：喜好、厌恶
- `persona.lang`：语言模式，`zh`（只用中文）/ `en`（只用英文）/ `auto`（跟着你说，默认）
- `persona.extra`：说话风格与长度限制（默认 30 字以内，回复越短开口越快）
- `bubble.opacity`：气泡文字透明度（0 = 全透明，1 = 不透明）
- `voice.silenceGate`：说话要多响才算"开始说话"（越小越灵敏，默认 600）
- `voice.silenceMs`：说完后等多久算"讲完了"（英文建议 900~1100，太小会把句子切断）
- `voice.boost`：麦克风增益倍数
- `voice.engine`：语音识别引擎，`cloud`（硅基流动 Qwen3-ASR，最准）/ `local`（Windows 自带，免费但吃字）/ `auto`（本地优先、云端兜底）
- `voice.localConf`：`auto` 模式下本地识别置信度门槛，低于它就转云端

### 语音朗读（TTS）

默认音色 **温柔姐姐·晓晓**（`zh-CN-XiaoxiaoNeural`），用**微软 Edge 在线语音**：完全免费、不用任何 API Key，音色比 Windows 自带的 SAPI 自然得多。

需要本机装有 Python 3 并安装 `edge-tts`：

```powershell
python -m pip install --upgrade edge-tts
```

> 注意：`edge-tts` 需 7.3.1 及以上，旧版会出现 403 握手失败。

`tts` 段各项含义：

| 字段 | 说明 |
| --- | --- |
| `engine` | `edge`（免费云端音色）/ `sapi`（Windows 本机语音） |
| `voice` | 音色名，见下表 |
| `rate` | 语速，如 `+12%`（快）、`-10%`（慢） |
| `pitch` | 音调，如 `+10Hz`（更高更"萝"）、`-10Hz`（更低） |

可选中文音色（`edge` 引擎）：

| 音色 | 特点 |
| --- | --- |
| `zh-CN-XiaoyiNeural` | 活泼少女 |
| `zh-CN-XiaoxiaoNeural` | **温暖柔和，像邻家姐姐**（默认） |
| `zh-CN-liaoning-XiaobeiNeural` | 东北话，幽默 |
| `zh-CN-shaanxi-XiaoniNeural` | 陕西话，明亮 |
| `zh-CN-YunxiNeural` | 男声，阳光 |
| `zh-CN-YunxiaNeural` | 男声，可爱 |

换音色：改 `config.json` 的 `tts.voice` → 重启鱼。若 `edge` 调用失败（没装 Python、断网等），会自动退回本机 SAPI 语音。
### 中英文聊天模式

鱼支持三种语言模式，右键菜单 **语言模式** 可即时切换（会写回 `config.json` 的 `persona.lang`）：

| 模式 | 值 | 行为 |
| --- | --- | --- |
| 中文 | `zh` | 始终用中文回 |
| English | `en` | 始终用英文回 |
| **自动模式**（默认） | `auto` | 你用中文它用中文，你用英文它用英文 |

语言判断依据：统计中文字符数与英文字母数的比例，英文字母明显更多（且≥4个）就按英文处理。

**朗读也会跟着换音色**：英文回复用 `en-US-AnaNeural`（童声），中文回复用你配置的中文音色。英文音色可在 `tts.voiceEn` 里改，例如：

| 英文音色 | 特点 |
| --- | --- |
| `en-US-AnaNeural` | 童声，可爱（默认） |
| `en-US-AvaNeural` | 年轻女声，自然 |
| `en-US-AriaNeural` | 女声，温柔 |
| `en-US-EmmaNeural` | 女声，明快 |
| `en-GB-MaisieNeural` | 英式童声 |

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

### 获取 SiliconFlow key

1. 打开 <https://cloud.siliconflow.cn>，手机号注册登录
2. 控制台 → API 密钥 → 新建密钥
3. 写入 `%USERPROFILE%\.dsh\fish-pet\siliconflow.key`，或设为环境变量

### 获取 DeepSeek key

<https://platform.deepseek.com> → API keys。

## 隐私

- 麦克风音频按约 5 秒切片，**上传 SiliconFlow 做识别**；识别出的文字再发 DeepSeek 生成回复
- 其余数据（位置、日志、密钥）只存本机
- 不想用语音：别启动 `start-ear.vbs`，只用打字聊天

## 目录结构

```
dsh-fish-pet/
├─ lib/index.js              # DSH 插件宿主：拉起/守护桌宠进程
├─ assets/
│  ├─ fish-pet.ps1           # 桌宠主体（绘制 + 聊天 + 语音朗读）
│  ├─ asr-listener.ps1       # 云端耳朵（WASAPI → SiliconFlow）
│  ├─ start-pet.vbs          # 独立启动器
│  └─ start-ear.vbs
├─ cordis.patch.yml          # DSH 插件插入行
└─ package.json
```

## 运行数据（`%USERPROFILE%\.dsh\fish-pet\`）

| 文件 | 作用 |
| --- | --- |
| `state.json` | 位置 / 大小 |
| `pet.pid` | 单实例守卫 |
| `error.log` | 桌宠异常 |
| `asr.log` | 识别结果（`H`=听到声音，`1`=识别成功） |
| `asr.level` | 每段麦克风峰值（排查“听不见”先看它） |
| `asr.err` | 耳朵异常 |

## 常见问题

**叫它没反应？**
1. 看 `asr.level`：说话时峰值应明显变大；一直是几十说明麦克风没进来
2. 看 `asr.log`：出现 `H` 说明听到了，出现 `1` 说明识别成功
3. Windows 设置 → 隐私和安全性 → 麦克风，允许桌面应用访问

**识别不准？**
- 安静环境、靠近麦克风最好
- 可调 `asr-listener.ps1` 顶部参数：`-ChunkMs`（片段长度）、`-SilenceGate`（静音门限）

**它会接别人的话？**
- 它是持续监听的；不想要时停掉 `start-ear.vbs`，或调高 `SilenceGate`

## 开发

纯 PowerShell + WinForms，无第三方依赖。语法检查：

```powershell
powershell -NoProfile -Command "$e=$null;$t=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('assets\fish-pet.ps1',[ref]$t,[ref]$e);$e"
```

> 脚本是 UTF-8 **带 BOM**；编辑器保存时保留 BOM，否则 PowerShell 5.1 会按 ANSI 读成乱码。

## 插件配置

```yaml
- insert:
    - id: fish-pet
      name: dsh-fish-pet
      config:
        enabled: true   # false 则不启动
        scale: 1        # 0.5 ~ 2
        speed: 26       # 5 ~ 120 像素/秒
```

## 许可

MIT，见 [LICENSE](LICENSE)。
