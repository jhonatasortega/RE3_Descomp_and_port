/**
 * shoot.mjs — renderiza o editor num navegador headless e salva PNGs.
 *
 * Serve para conferir o resultado visual sem depender de alguém abrir a página:
 * abre o app, entra numa sala pelas câmeras originais e fotografa o viewport.
 * WebGL roda por SwiftShader (software), então é lento mas fiel.
 *
 *   node tools/shoot.mjs --room R100 --out ../../../tmp/shot
 *   node tools/shoot.mjs --room R100 --cam 1 --layers shell,walls
 *
 * Requer o server.mjs no ar.
 */
import { chromium } from 'playwright'
import path from 'node:path'
import fs from 'node:fs/promises'

const argv = process.argv.slice(2)
const arg = (name, def = null) => {
  const i = argv.indexOf(`--${name}`)
  return i >= 0 && argv[i + 1] ? argv[i + 1] : def
}
const has = (name) => argv.includes(`--${name}`)

const URL = arg('url', 'http://localhost:5173')
const ROOM = arg('room', 'R100')
const CAM = Number(arg('cam', '0'))
const STAGE = Number(arg('stage', '1'))
const OUT = path.resolve(arg('out', 'shots/shot'))
const WAIT = Number(arg('wait', '2500'))

const browser = await chromium.launch({
  args: [
    '--use-gl=angle',
    '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist',
  ],
})
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } })

const logs = []
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`))
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`))

await page.goto(URL, { waitUntil: 'networkidle' })
await page.waitForFunction('window.__re3?.ready === true', null, { timeout: 60000 })

if (STAGE !== 1) {
  await page.selectOption('#stageSel', String(STAGE))
  await page.waitForTimeout(3000)
}

await fs.mkdir(path.dirname(OUT), { recursive: true })

/** Diagnóstico do que efetivamente foi para a GPU. */
const info = await page.evaluate(({ room, cam }) => {
  const R = window.__re3
  const src = R.store.rooms[room]
  if (!src) return { error: `sala ${room} não carregada` }
  const g = R.roomGroups.get(room)
  let meshes = 0
  const kinds = {}
  g?.traverse((o) => {
    if (!o.isMesh) return
    meshes++
    const k = o.userData?.kind || o.name
    kinds[k] = (kinds[k] || 0) + 1
  })
  return {
    room,
    bounds: src.bounds,
    cameras: (src.cameras || []).filter((c) => c.hd).length,
    meshes, kinds,
  }
}, { room: ROOM, cam: CAM })

if (info.error) {
  console.error(info.error)
  await browser.close()
  process.exit(1)
}

// visão geral da sala isolada
await page.evaluate(({ room }) => {
  const R = window.__re3
  R.select(room)
  R.setLayer('isolate', true)
  R.view.focus(R.roomGroups.get(room), 1.4)
}, { room: ROOM })
await page.waitForTimeout(1200)
await page.screenshot({ path: `${OUT}_blockout.png` })

// dentro da sala, pelas câmeras originais, com a foto projetada
const enter = await page.evaluate(async ({ room, cam }) => {
  await window.__re3.enterCameraMode(room, cam)
  const a = window.__re3.projection.active
  return a ? { camIndex: a.camIndex, projectors: a.nProjectors, total: a.totalCameras } : null
}, { room: ROOM, cam: CAM })
await page.waitForTimeout(WAIT)
await page.screenshot({ path: `${OUT}_camera.png` })

// TESTE DE VERDADE: sair do ponto de vista do projetor.
// Visto da própria câmera a projeção sempre encaixa; o erro de geometria só
// aparece quando se desloca o observador (paralaxe).
for (const [name, elev] of [['offset', 0.5], ['wide', 1.1]]) {
  await page.evaluate(({ room, elev }) => {
    const R = window.__re3
    const g = R.roomGroups.get(room)
    // enquadra a sala inteira e sobe: ângulo que revela paredes e chão juntos
    R.view.focus(g, 1.3)
    const cam = R.view.camera
    const t = R.view.controls.target
    const d = cam.position.distanceTo(t)
    cam.position.set(t.x + d * Math.cos(elev) * 0.8, t.y + d * Math.sin(elev), t.z + d * 0.6)
    cam.lookAt(t)
    cam.updateMatrixWorld(true)
  }, { room: ROOM, elev })
  await page.waitForTimeout(1500)
  await page.screenshot({ path: `${OUT}_${name}.png` })
}

// modo andar, dentro da sala na altura dos olhos
await page.evaluate(() => window.__re3.toggleWalk())
await page.waitForTimeout(1500)
await page.screenshot({ path: `${OUT}_walk.png` })

// só a foto, para comparar lado a lado
const hd = await page.evaluate(({ room, cam }) => {
  const src = window.__re3.store.rooms[room]
  const c = (src.cameras || []).filter((x) => x.hd)[cam]
  return c ? `/data/STAGE${window.__re3.store.stage}/${room}/${c.hd}` : null
}, { room: ROOM, cam: CAM })

console.log(JSON.stringify({ info, enter, hd, logs: logs.slice(-25) }, null, 1))

if (!has('keep')) await browser.close()
