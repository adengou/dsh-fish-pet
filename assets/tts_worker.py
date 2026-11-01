"""常驻 TTS 工作进程（并发版）

从 stdin 读 JSON 请求（一行一个，或 "@文件路径"），并发合成 + 转码成 WAV，
把结果追加到状态文件：
    <id> OK <wav 或 mp3 路径>
    <id> ERR <原因>

相对串行版的变化：
- 最多 4 路并发合成（信号量），多段回复不再排队等
- 合成有超时（默认 25 秒），超时写 ERR 而不是把进程卡死
- 合成完直接调 ffmpeg 转 22050Hz 单声道 WAV，主程序播放时无需再转码
- ffmpeg 找不到时退回 mp3，不阻塞主程序
"""
import sys
import os
import json
import shutil
import asyncio

try:
    import edge_tts
except Exception as exc:  # 依赖缺失时直接退出，让主程序回退到 SAPI
    sys.stderr.write("NO_EDGE_TTS: %s\n" % exc)
    sys.exit(3)

MAX_CONCURRENT = 4
SYNTH_TIMEOUT = 25.0
CONV_TIMEOUT = 10.0
STATUS_MAX_BYTES = 2 * 1024 * 1024

FFMPEG = os.environ.get("DSH_FISH_FFMPEG") or shutil.which("ffmpeg")

_seen_status = set()


def write_status(path, req_id, text):
    if not path:
        return
    try:
        if path not in _seen_status:
            _seen_status.add(path)
            try:
                if os.path.exists(path) and os.path.getsize(path) > STATUS_MAX_BYTES:
                    open(path, "w", encoding="utf-8").close()
            except Exception:
                pass
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("%s %s\n" % (req_id, text))
            fh.flush()
    except Exception:
        pass


async def convert_to_wav(mp3, wav):
    if not FFMPEG:
        return False
    try:
        proc = await asyncio.create_subprocess_exec(
            FFMPEG, "-y", "-loglevel", "error", "-i", mp3,
            "-af", "volume=0.75", "-ar", "22050", "-ac", "1", wav,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
    except Exception:
        return False
    try:
        await asyncio.wait_for(proc.wait(), CONV_TIMEOUT)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except Exception:
            pass
        return False
    try:
        return proc.returncode == 0 and os.path.getsize(wav) > 1000
    except Exception:
        return False


async def synth(req, sem):
    rid = str(req.get("id") or "?")
    status = req.get("status")
    async with sem:
        try:
            text = req.get("text") or ""
            out = req.get("out") or ""
            if not text or not out:
                raise ValueError("missing text/out")
            voice = req.get("voice") or "zh-CN-XiaoxiaoNeural"
            rate = req.get("rate") or "+0%"
            pitch = req.get("pitch") or "+0Hz"
            wav = req.get("wav") or (os.path.splitext(out)[0] + ".wav")
            communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
            await asyncio.wait_for(communicate.save(out), SYNTH_TIMEOUT)
            ok = await convert_to_wav(out, wav)
            write_status(status, rid, "OK " + (wav if ok else out))
        except asyncio.TimeoutError:
            write_status(status, rid, "ERR timeout")
        except Exception as exc:
            write_status(status, rid, "ERR " + str(exc).replace("\n", " ")[:200])


async def main():
    loop = asyncio.get_event_loop()
    sem = asyncio.Semaphore(MAX_CONCURRENT)
    pending = set()
    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        req = None
        if line.startswith("@"):
            try:
                with open(line[1:], "r", encoding="utf-8") as fh:
                    req = json.loads(fh.read())
            except Exception:
                continue
        else:
            try:
                req = json.loads(line)
            except Exception:
                continue
        if not req:
            continue
        if req.get("cmd") == "quit":
            break
        task = asyncio.ensure_future(synth(req, sem))
        pending.add(task)
        task.add_done_callback(pending.discard)
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)


if __name__ == "__main__":
    asyncio.run(main())
