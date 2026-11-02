#!/usr/bin/env node
// session-digest.mjs · 汇总最近 N 小时内 DSH 会话的标题，供桌宠“今日简报”使用
// 用法: node session-digest.mjs [today|小时数]（默认 today：今天 0 点起）
// 输出: JSON 数组 [{ title, cwd, sessionId, mtime }]

import { readdirSync, statSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { zstdDecompressSync } from 'node:zlib'

// 参数：today = 今天 0 点起；数字 = 最近 N 小时；默认 today
const arg = String(process.argv[2] || 'today')
let since
if (arg === 'today') {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  since = d.getTime()
} else {
  since = Date.now() - Number(arg) * 3600 * 1000
}
const root = path.join(process.env.USERPROFILE || '', '.dsh', 'sessions')
const MAGIC = Buffer.from([0x28, 0xB5, 0x2F, 0xFD])

function decodeLines(file) {
  const raw = readFileSync(file)
  const idx = []
  let pos = 0
  while ((pos = raw.indexOf(MAGIC, pos)) !== -1) { idx.push(pos); pos += 1 }
  let out = ''
  for (let i = 0; i < idx.length; i++) {
    const start = idx[i]
    const end = i + 1 < idx.length ? idx[i + 1] : raw.length
    try { out += zstdDecompressSync(raw.subarray(start, end)).toString('utf8') + '\n' } catch { /* 坏帧跳过 */ }
  }
  return out.split('\n').filter(Boolean)
}

const result = []
let dirs = []
try { dirs = readdirSync(root) } catch { console.log('[]'); process.exit(0) }

for (const dirName of dirs) {
  const dirPath = path.join(root, dirName)
  let st
  try { st = statSync(dirPath) } catch { continue }
  if (!st.isDirectory()) continue
  let subs = []
  try { subs = readdirSync(dirPath) } catch { continue }
  for (const sub of subs) {
    const file = path.join(dirPath, sub, 'session.v4.jsonl.zstd')
    let fst
    try { fst = statSync(file) } catch { continue }
    if (fst.mtimeMs < since) continue
    let title = ''
    let cwd = ''
    let sessionId = ''
    let userMsgs = []
    try {
      for (const line of decodeLines(file)) {
        let o
        try { o = JSON.parse(line) } catch { continue }
        if (o.type === 'session') { sessionId = o.id || ''; cwd = o.cwd || '' }
        if (o.type === 'user/message' && o.data && o.data.source && o.data.source.kind === 'user') {
          const t = (o.data.content || []).filter((c) => c.type === 'text').map((c) => c.text).join(' ')
          if (t && t.length < 300) userMsgs.push(t)
        }
        // 同一会话会写多条 title（fallback 短标题 + LLM 标题），后写的为准
        if (o.type === 'session/title' && o.data && o.data.title) title = String(o.data.title)
      }
    } catch { /* 解压失败就跳过这个会话 */ }
    if (!title) title = cwd ? path.basename(cwd) : dirName
    result.push({
      title: title.trim(),
      cwd,
      sessionId,
      mtime: new Date(fst.mtimeMs).toISOString(),
      msgs: userMsgs.slice(-20),
    })
  }
}

result.sort((a, b) => b.mtime.localeCompare(a.mtime))
console.log(JSON.stringify(result))
