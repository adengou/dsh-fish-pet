/**
 * dsh-fish-pet · host half
 *
 * 把桌面蓝鱼托管进 DeepSeek Harness：
 *   - apply 时确认没有第二只在游，再拉起 assets/fish-pet.ps1（WinForms 分层窗口）；
 *   - 插件被卸载 / 配置禁用 / Harness 正常退出时，把插件自己拉起的那只收回去；
 *   - 若进程是上一次 Harness 崩溃后留下的孤儿（pet.pid 还活着），直接沿用，不双开。
 *
 * 只动 Windows：脚本依赖 System.Windows.Forms 与 user32 的分层窗口。
 */
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const SCRIPT = path.resolve(HERE, '..', 'assets', 'fish-pet.ps1')
const DATA_DIR = path.join(homedir(), '.dsh', 'fish-pet')
const PID_FILE = path.join(DATA_DIR, 'pet.pid')

/** Cordis 插件名。 */
export const name = 'fish-pet'

function log(message) {
  console.log(`[fish-pet] ${message}`)
}

function clamp(value, min, max, fallback) {
  const number = Number(value)
  if (!Number.isFinite(number)) return fallback
  return Math.min(max, Math.max(min, number))
}

function readPid() {
  try {
    const parsed = JSON.parse(readFileSync(PID_FILE, 'utf8'))
    const pid = Number(parsed?.pid)
    return Number.isInteger(pid) && pid > 0 ? pid : null
  } catch {
    return null
  }
}

function isAlive(pid) {
  if (!pid) return false
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
}

/** 脚本会自己写 pet.pid，等它落盘拿到真实 PID（拿不到就退回子进程 PID）。 */
function waitForPid(fallback, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const pid = readPid()
    if (isAlive(pid)) return pid
    sleep(120)
  }
  return isAlive(fallback) ? fallback : null
}

function startPet(cfg) {
  mkdirSync(DATA_DIR, { recursive: true })

  const existing = readPid()
  if (isAlive(existing)) {
    log(`桌面上已经有一只在游（pid ${existing}），沿用它，不重复放鱼`)
    return { pid: existing, owned: false }
  }

  try { rmSync(PID_FILE, { force: true }) } catch (error) { log(`清理 pet.pid 失败（忽略）：${error.message}`) }
  const child = spawn('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden',
    '-File', SCRIPT,
    '-Scale', String(cfg.scale),
    '-Speed', String(cfg.speed),
  ], { stdio: 'ignore', windowsHide: true })
  child.on('error', (error) => log(`拉起脚本失败：${error.message}`))
  child.unref()

  const pid = waitForPid(child.pid)
  if (!pid) {
    log('蓝鱼没有起来：脚本 20 秒内未写入 pet.pid，请查看 %USERPROFILE%\\.dsh\\fish-pet\\error.log')
    return { pid: null, owned: false }
  }
  log(`蓝鱼已放出（pid ${pid}，scale ${cfg.scale}，speed ${cfg.speed}）`)
  return { pid, owned: true }
}

function stopPet(state) {
  if (!state || !state.owned) return
  try { writeFileSync(path.join(DATA_DIR, 'asr.stop'), new Date().toISOString()) } catch { }
  const pid = readPid() ?? state.pid
  if (isAlive(pid)) {
    spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true })
    log(`蓝鱼已收起（pid ${pid}）`)
  }
  try { rmSync(PID_FILE, { force: true }) } catch (error) { log(`清理 pet.pid 失败（忽略）：${error.message}`) }
}

export function apply(ctx, config = {}) {
  const cfg = {
    enabled: true,
    scale: clamp(config.scale, 0.5, 2, 1),
    speed: clamp(config.speed, 5, 120, 26),
  }

  if (!cfg.enabled) {
    log('配置 enabled=false，本次不启动')
    return
  }
  if (process.platform !== 'win32') {
    log('只支持 Windows，本次跳过')
    return
  }
  if (!existsSync(SCRIPT)) {
    log(`找不到桌面脚本：${SCRIPT}`)
    return
  }

  ctx.effect(() => {
    let current = startPet(cfg)

    // 守护：脚本被误关、崩溃或被任务管理器结束，10 秒内自动补一只。
    // 定时器 unref，避免拖住 node 退出。
    const guard = setInterval(() => {
      if (isAlive(readPid())) return
      log('蓝鱼不在了（闪退或被关掉），重新放一只')
      current = startPet(cfg)
    }, 10000)
    guard.unref?.()

    return () => {
      clearInterval(guard)
      stopPet(current)
    }
  })
}
