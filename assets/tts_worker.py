"""常驻 TTS 工作进程：从 stdin 读 JSON 请求，合成后把结果追加到状态文件。
请求格式（一行一个 JSON）：
  {"id":"abc","text":"要念的话","voice":"zh-CN-XiaoxiaoNeural","rate":"+12%","pitch":"+10Hz","out":"C:/.../x.mp3","status":"C:/.../status.txt"}
状态文件行格式： <id> OK <out路径>   或   <id> ERR <错误信息>
"""
import sys
import json
import asyncio
import traceback

try:
    import edge_tts
except Exception as exc:  # 依赖缺失时直接退出，让主程序回退到 SAPI
    sys.stderr.write("NO_EDGE_TTS: %s\n" % exc)
    sys.exit(3)


def write_status(path, req_id, text):
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("%s %s\n" % (req_id, text))
            fh.flush()
    except Exception:
        pass


async def synth(req):
    voice = req.get("voice") or "zh-CN-XiaoxiaoNeural"
    rate = req.get("rate") or "+0%"
    pitch = req.get("pitch") or "+0Hz"
    communicate = edge_tts.Communicate(req["text"], voice, rate=rate, pitch=pitch)
    await communicate.save(req["out"])
    write_status(req["status"], req["id"], "OK " + req["out"])


async def main():
    loop = asyncio.get_event_loop()
    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        # 支持"@文件路径"形式：避免 Windows PowerShell 写 stdin 时的编码问题
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
        if req.get("cmd") == "quit":
            break
        try:
            await synth(req)
        except Exception as exc:
            write_status(req["status"], req["id"], "ERR " + str(exc).replace("\n", " ")[:200])
            traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())
