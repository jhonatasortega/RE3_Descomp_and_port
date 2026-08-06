/**
 * server.mjs — servidor local do editor de stages.
 *
 * Serve o app, os dados de v2/reconstruction (JSON + backgrounds HD) e grava as
 * edicoes de volta no disco. Sem bundler: o browser carrega ES modules direto e
 * o three.js sai de node_modules via importmap.
 *
 * Escrita permitida SOMENTE dentro de v2/reconstruction (ver assertInsideRecon).
 *
 *   npm start   ->   http://localhost:5173
 */
import http from 'node:http'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const V2 = path.resolve(HERE, '..')
const RECON = path.join(V2, 'reconstruction')
const THREE_DIR = path.join(HERE, 'node_modules', 'three')
const PORT = Number(process.env.PORT || 5173)

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
}

/** Barreira de escrita: nada fora de v2/reconstruction e gravavel. */
function assertInsideRecon(p) {
  const abs = path.resolve(p)
  if (abs !== RECON && !abs.startsWith(RECON + path.sep)) {
    throw new Error(`escrita bloqueada fora de reconstruction/: ${abs}`)
  }
  return abs
}

async function readJson(p) {
  try {
    return JSON.parse(await fs.readFile(p, 'utf-8'))
  } catch {
    return null
  }
}

async function writeJson(p, data) {
  const abs = assertInsideRecon(p)
  await fs.mkdir(path.dirname(abs), { recursive: true })
  await fs.writeFile(abs, JSON.stringify(data, null, 1), 'utf-8')
  return abs
}

function send(res, status, body, type = 'application/json; charset=utf-8') {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' })
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body))
}

async function listStages() {
  const out = []
  for (const e of await fs.readdir(RECON, { withFileTypes: true })) {
    if (!e.isDirectory() || !/^STAGE\d+$/.test(e.name)) continue
    const n = Number(e.name.slice(5))
    const rooms = (await fs.readdir(path.join(RECON, e.name), { withFileTypes: true }))
      .filter((d) => d.isDirectory() && d.name.startsWith('R'))
    out.push({ stage: n, name: e.name, rooms: rooms.length })
  }
  return out.sort((a, b) => a.stage - b.stage)
}

/** Payload completo de um stage: fonte + layout resolvido + edicoes do usuario. */
async function loadStage(n) {
  const dir = path.join(RECON, `STAGE${n}`)
  const entries = (await fs.readdir(dir, { withFileTypes: true }))
    .filter((d) => d.isDirectory() && d.name.startsWith('R'))
    .map((d) => d.name)
    .sort()

  const rooms = {}
  const geom = {}
  const edits = {}
  for (const id of entries) {
    const src = await readJson(path.join(dir, id, 'room.src.json'))
    if (src) rooms[id] = src
    const g = await readJson(path.join(dir, id, 'room.geom.json'))
    if (g) geom[id] = g
    const ed = await readJson(path.join(dir, id, 'room3d.json'))
    if (ed) edits[id] = ed
  }
  return {
    stage: n,
    layout: await readJson(path.join(dir, 'stage_layout.json')),
    stageEdits: await readJson(path.join(dir, 'stage_edits.json')),
    rooms,
    geom,
    roomEdits: edits,
  }
}

async function body(req) {
  const chunks = []
  for await (const c of req) chunks.push(c)
  return JSON.parse(Buffer.concat(chunks).toString('utf-8') || '{}')
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`)
  const p = decodeURIComponent(url.pathname)

  try {
    // ---------------------------------------------------------------- API
    if (p === '/api/stages') return send(res, 200, await listStages())

    let m = p.match(/^\/api\/stage\/(\d+)$/)
    if (m) return send(res, 200, await loadStage(Number(m[1])))

    m = p.match(/^\/api\/stage\/(\d+)\/edits$/)
    if (m && req.method === 'PUT') {
      const data = await body(req)
      const file = path.join(RECON, `STAGE${m[1]}`, 'stage_edits.json')
      await writeJson(file, data)
      return send(res, 200, { ok: true, wrote: path.relative(V2, file) })
    }

    m = p.match(/^\/api\/stage\/(\d+)\/room\/(R[0-9A-F]+)$/)
    if (m && req.method === 'PUT') {
      const data = await body(req)
      const file = path.join(RECON, `STAGE${m[1]}`, m[2], 'room3d.json')
      await writeJson(file, data)
      return send(res, 200, { ok: true, wrote: path.relative(V2, file) })
    }

    // ------------------------------------------------------------ estaticos
    let file = null
    if (p.startsWith('/data/')) file = path.join(RECON, p.slice(6))
    else if (p.startsWith('/vendor/three/')) file = path.join(THREE_DIR, p.slice(14))
    else file = path.join(HERE, p === '/' ? 'index.html' : p.slice(1))

    const abs = path.resolve(file)
    const allowed = [RECON, THREE_DIR, HERE].some((r) => abs.startsWith(r))
    if (!allowed) return send(res, 403, { error: 'forbidden' })

    const data = await fs.readFile(abs)
    return send(res, 200, data, MIME[path.extname(abs).toLowerCase()] || 'application/octet-stream')
  } catch (err) {
    if (err.code === 'ENOENT') return send(res, 404, { error: 'not found', path: p })
    console.error(err)
    return send(res, 500, { error: String(err.message || err) })
  }
})

server.listen(PORT, () => {
  console.log(`RE3 stage editor  ->  http://localhost:${PORT}`)
  console.log(`  dados:   ${RECON}`)
  console.log(`  escrita: somente dentro de reconstruction/`)
})
