/**
 * blockout.js — Converte dados de room.src.json em geometria Three.js.
 * Inclui: colisão, shell, portas, câmeras, itens, inimigos, escadas com degraus,
 *         e planos de referência de profundidade das máscaras.
 */
import * as THREE from 'three'

export const WORLD_SCALE = 808
const M = v => v / WORLD_SCALE

// ── Paleta de cores ──────────────────────────────────────────────────────────
export const COLORS = {
  floor:       0x2a3140,
  shell:       0x8a90a0,
  ceiling:     0x7d8494,
  wall:        0x6b7488,
  prop:        0xa2762f,
  sentinel:    0x503a5a,
  door:        0x3fa7d6,
  doorOneway:  0xd6733f,
  cam:         0x7ee081,
  link:        0x4ea3ff,
  sel:         0xffcf5c,
  trigger:     0x9b6bd6,
  message:     0x5c8fb8,
  flag:        0xd65c9b,
  item:        0x63d67a,
  enemy:       0xd64f4f,
  light:       0xffe08a,
  stair:       0x00c9a7,
  maskPlane:   0xffffff,
}

// ── Geometrias compartilhadas ────────────────────────────────────────────────
const GEO = {
  box:    new THREE.BoxGeometry(1, 1, 1),
  plane:  new THREE.PlaneGeometry(1, 1),
  sphere: new THREE.SphereGeometry(0.35, 8, 6),
  cone:   new THREE.ConeGeometry(0.25, 0.6, 4),
}

// ── Fábrica de materiais ─────────────────────────────────────────────────────
function mat(color, opts = {}) {
  return new THREE.MeshLambertMaterial({
    color,
    transparent: (opts.opacity ?? 1) < 1,
    opacity: opts.opacity ?? 1,
    depthWrite: (opts.opacity ?? 1) > 0.9,
    side: opts.side ?? THREE.FrontSide,
    wireframe: opts.wireframe ?? false,
  })
}

const MATS = {
  shell:     mat(COLORS.shell,    { side: THREE.DoubleSide }),
  ceiling:   mat(COLORS.ceiling,  { side: THREE.BackSide }),
  floor:     mat(COLORS.floor,    { side: THREE.DoubleSide }),
  wall:      mat(COLORS.wall,     { opacity: 0.65, side: THREE.DoubleSide }),
  prop:      mat(COLORS.prop,     { opacity: 0.80 }),
  sentinel:  mat(COLORS.sentinel, { opacity: 0.22, side: THREE.DoubleSide }),
  door:      mat(COLORS.door,     { opacity: 0.55, side: THREE.DoubleSide }),
  doorOW:    mat(COLORS.doorOneway, { opacity: 0.55, side: THREE.DoubleSide }),
  trigger:   mat(COLORS.trigger,  { opacity: 0.30, side: THREE.DoubleSide }),
  message:   mat(COLORS.message,  { opacity: 0.28, side: THREE.DoubleSide }),
  flag:      mat(COLORS.flag,     { opacity: 0.32, side: THREE.DoubleSide }),
  item:      new THREE.MeshBasicMaterial({ color: COLORS.item }),
  enemy:     new THREE.MeshBasicMaterial({ color: COLORS.enemy }),
  light:     new THREE.MeshBasicMaterial({ color: COLORS.light }),
  stair:     mat(COLORS.stair,    { opacity: 0.80, side: THREE.DoubleSide }),
  sel:       new THREE.MeshBasicMaterial({ color: COLORS.sel, wireframe: true }),
  maskPlane: new THREE.MeshBasicMaterial({
    color: COLORS.maskPlane, transparent: true, opacity: 0.07,
    side: THREE.DoubleSide, depthWrite: false,
  }),
}

// ── Helpers de geometria ─────────────────────────────────────────────────────

function box(cx, cy, cz, sx, sy, sz, material) {
  const m = new THREE.Mesh(GEO.box, material)
  m.scale.set(sx, sy, sz)
  m.position.set(cx, cy, cz)
  return m
}

function pointMarker(x, y, z, material, scale = 1) {
  const m = new THREE.Mesh(GEO.sphere, material)
  m.position.set(M(x), M(-y), M(z))
  m.scale.setScalar(scale)
  return m
}

/**
 * Cria degraus de escada.
 * @param {object} r  - rect de colis ão com form==8
 * @param {number} floorY - Y do piso da sala
 * @param {number} topY  - Y do topo da escada (rect do nível superior)
 */
function stairMesh(r, floorY, topY) {
  const [x0, z0, x1, z1] = r.rect
  const w = Math.abs(x1 - x0)
  const d = Math.abs(z1 - z0)
  const totalH = Math.abs((topY ?? r.y - r.h) - floorY)
  const stepH = 200 // ~25 cm em unidades PS1
  const nSteps = Math.max(1, Math.ceil(totalH / stepH))

  const group = new THREE.Group()
  for (let i = 0; i < nSteps; i++) {
    const frac = i / nSteps
    const nextFrac = (i + 1) / nSteps
    const y0 = floorY - totalH * frac
    const y1 = floorY - totalH * nextFrac
    const stepDepth = d / nSteps

    const stepY = M(-(y0 + y1) / 2)
    const stepH_m = M(Math.abs(y1 - y0))

    // Degrau deslocado ao longo do eixo Z
    const zOff = M((z0 + z1) / 2 + (i - nSteps / 2 + 0.5) * stepDepth - stepDepth * nSteps / 2)

    const step = new THREE.Mesh(GEO.box, MATS.stair)
    step.scale.set(M(w), stepH_m, M(stepDepth))
    step.position.set(M((x0 + x1) / 2), stepY, zOff)
    group.add(step)
  }
  return group
}

/**
 * Cria planos semi-transparentes de profundidade a partir das máscaras.
 * Cada depth value vira um plano horizontal no espaço 3D, referenciado
 * à posição da câmera.
 */
function maskDepthPlanes(cam, roomBounds) {
  const group = new THREE.Group()
  const mask = cam.mask
  if (!mask) return group

  const depths = new Set()
  if (mask.primary_depth) depths.add(mask.primary_depth)
  ;(mask.group_depths || []).forEach(d => depths.add(d))

  const camPos = new THREE.Vector3(M(cam.pos[0]), -M(cam.pos[1]), M(cam.pos[2]))
  const camDir = new THREE.Vector3(...cam.forward).normalize()

  const b = roomBounds
  const planeW = b ? M(b.size[0] + 2000) : 20
  const planeD = b ? M(b.size[1] + 2000) : 20

  for (const depth of depths) {
    const dist = M(depth * 16) // z_depth em unidades PS1 (fator 16 conforme blueprint 07)
    const planePos = camPos.clone().addScaledVector(camDir, dist)

    const plane = new THREE.Mesh(GEO.plane, MATS.maskPlane.clone())
    plane.position.copy(planePos)
    plane.lookAt(camPos) // perpendicular ao vetor câmera→plano
    plane.scale.set(planeW, planeD, 1)
    plane.userData = { kind: 'maskPlane', depth, camIndex: cam.index }
    group.add(plane)
  }
  return group
}

// ── Construtor principal ─────────────────────────────────────────────────────

/**
 * Constrói o Group THREE.js de uma sala a partir de room.src.json.
 * @param {object} src - conteúdo de room.src.json
 * @param {object} pose - { tx, tz, rot_deg }
 * @param {boolean} opts.showMaskPlanes
 * @returns {THREE.Group}
 */
export function buildRoom(src, pose = {}, opts = {}) {
  const id = src.room
  const g = new THREE.Group()
  g.name = `room:${id}`
  g.userData = { roomId: id, kind: 'room', src }

  const b = src.bounds || {}
  const floorY = b.y_floor ?? 0

  // ── Casca da sala (shell) ────────────────────────────────────────────────
  const shellGroup = new THREE.Group()
  shellGroup.name = 'shell'

  if (b.aabb) {
    const [x0, z0, x1, z1] = b.aabb
    const w = Math.max(x1 - x0, 1)
    const d = Math.max(z1 - z0, 1)
    const h = Math.max(b.ceiling_h ?? Math.abs((b.y_floor ?? 0) - (b.y_ceiling ?? -4000)), 1)
    const cx = M((x0 + x1) / 2)
    const cz = M((z0 + z1) / 2)
    const cy = M(-floorY) + M(h / 2)

    const shellMesh = new THREE.Mesh(GEO.box, MATS.shell.clone())
    shellMesh.scale.set(M(w), M(h), M(d))
    shellMesh.position.set(cx, cy, cz)
    shellMesh.userData = { roomId: id, kind: 'shell' }
    shellGroup.add(shellMesh)

    // Piso separado
    const floorMesh = new THREE.Mesh(GEO.plane, MATS.floor)
    floorMesh.rotation.x = -Math.PI / 2
    floorMesh.scale.set(M(Math.max(w, 1)), M(Math.max(d, 1)), 1)
    floorMesh.position.set(cx, M(-floorY) - 0.01, cz)
    floorMesh.name = 'floor'
    floorMesh.userData = { roomId: id, kind: 'floor' }
    shellGroup.add(floorMesh)
  }
  g.add(shellGroup)

  // ── Colisão ──────────────────────────────────────────────────────────────
  const rectsGroup = new THREE.Group()
  rectsGroup.name = 'rects'

  const stairs = new THREE.Group()
  stairs.name = 'stairs'

  for (const r of src.collision?.rects || []) {
    if (r.hidden) continue

    const [x0, z0, x1, z1] = r.rect
    const w = Math.max(Math.abs(x1 - x0), 1)
    const d = Math.max(Math.abs(z1 - z0), 1)
    const h = Math.max(Math.abs(r.h ?? 1000), 1)
    const rY = r.y ?? 0

    // Detectar escada pelo tipo (forma == 8 é bit 3 do byte alto de type[0])
    const isStair = r.type && ((r.type[0] >> 8) & 0xFF) === 8

    if (isStair) {
      // Escada: gera degraus
      const stairGroup = stairMesh(r, floorY, rY - h)
      stairGroup.name = `stair:${r.i}`
      stairGroup.userData = { roomId: id, kind: 'stair', rectIndex: r.i }
      stairs.add(stairGroup)
    } else {
      const kind = r.sentinel ? 'sentinel' : r.wall ? 'wall' : 'prop'
      const material = r.sentinel ? MATS.sentinel : r.wall ? MATS.wall : MATS.prop

      const mesh = new THREE.Mesh(GEO.box, material)
      mesh.scale.set(M(w), M(h), M(d))
      mesh.position.set(M((x0 + x1) / 2), M(-rY) + M(h / 2), M((z0 + z1) / 2))
      mesh.name = `rect:${r.i}`
      mesh.userData = { roomId: id, kind, rectIndex: r.i, rectData: r }
      rectsGroup.add(mesh)
    }
  }
  g.add(rectsGroup)
  g.add(stairs)

  // ── Portas ───────────────────────────────────────────────────────────────
  const doorsGroup = new THREE.Group()
  doorsGroup.name = 'doors'

  for (const door of src.doors || []) {
    const bx = door.box
    if (!bx) continue
    const material = door.reciprocal ? MATS.door : MATS.doorOW
    const dm = new THREE.Mesh(GEO.box, material)
    const dw = Math.max(bx.w, 40)
    const dd = Math.max(bx.d, 40)
    dm.scale.set(M(dw), M(2000), M(dd))
    dm.position.set(M(bx.x + bx.w / 2), M(-floorY) + M(1000), M(bx.z + bx.d / 2))
    dm.name = `door:${door.i}`
    dm.userData = { roomId: id, kind: 'door', doorIndex: door.i, door }

    // Seta indicando a sala destino
    const arrowGeo = new THREE.ConeGeometry(M(300), M(600), 4)
    const arrowMat = new THREE.MeshBasicMaterial({ color: door.reciprocal ? COLORS.door : COLORS.doorOneway })
    const arrow = new THREE.Mesh(arrowGeo, arrowMat)
    arrow.position.set(M(bx.x + bx.w / 2), M(-floorY) + M(2200), M(bx.z + bx.d / 2))
    doorsGroup.add(arrow)

    doorsGroup.add(dm)
  }
  g.add(doorsGroup)

  // ── Gameplay: gatilhos, itens, inimigos ──────────────────────────────────
  const gp = src.gameplay || {}

  const triggersGroup = new THREE.Group()
  triggersGroup.name = 'triggers'
  triggersGroup.visible = false

  for (const [list, material] of [
    [gp.triggers, MATS.trigger],
    [gp.messages, MATS.message],
    [gp.flags,    MATS.flag],
  ]) {
    for (const aot of list || []) {
      const bx = aot.box
      if (!bx) continue
      const m = new THREE.Mesh(GEO.box, material)
      m.scale.set(M(Math.max(bx.w, 40)), M(600), M(Math.max(bx.d, 40)))
      m.position.set(M(bx.x + bx.w / 2), M(-floorY) + M(300), M(bx.z + bx.d / 2))
      m.name = `aot:${aot.aot}`
      m.userData = { roomId: id, kind: 'trigger', aot }
      triggersGroup.add(m)
    }
  }
  g.add(triggersGroup)

  const entGroup = new THREE.Group()
  entGroup.name = 'entities'

  for (const it of gp.items || []) {
    const m = pointMarker(it.x ?? 0, it.y ?? floorY, it.z ?? 0, MATS.item)
    m.userData = { roomId: id, kind: 'item', item: it }
    entGroup.add(m)
  }
  for (const en of gp.enemies || []) {
    const m = pointMarker(en.x ?? 0, en.y ?? floorY, en.z ?? 0, MATS.enemy, 1.3)
    m.userData = { roomId: id, kind: 'enemy', enemy: en }
    entGroup.add(m)
  }
  g.add(entGroup)

  // ── Câmeras ──────────────────────────────────────────────────────────────
  const camsGroup = new THREE.Group()
  camsGroup.name = 'cams'
  camsGroup.visible = false

  for (const cam of src.cameras || []) {
    const from = new THREE.Vector3(M(cam.pos[0]), -M(cam.pos[1]), M(cam.pos[2]))
    const to   = new THREE.Vector3(M(cam.target[0]), -M(cam.target[1]), M(cam.target[2]))

    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(0.3, 0.8, 4),
      new THREE.MeshBasicMaterial({ color: COLORS.cam })
    )
    cone.position.copy(from)
    cone.lookAt(to)
    cone.rotateX(Math.PI / 2)

    const lineGeo = new THREE.BufferGeometry().setFromPoints([from, to])
    const line = new THREE.Line(lineGeo,
      new THREE.LineBasicMaterial({ color: COLORS.cam, transparent: true, opacity: 0.5 }))

    const camGroup = new THREE.Group()
    camGroup.name = `cam:${cam.index}`
    camGroup.userData = { roomId: id, kind: 'cam', camIndex: cam.index, cam }
    camGroup.add(cone, line)
    camsGroup.add(camGroup)
  }
  g.add(camsGroup)

  // ── Luzes ────────────────────────────────────────────────────────────────
  const lightsGroup = new THREE.Group()
  lightsGroup.name = 'lights'
  lightsGroup.visible = false

  for (const L of src.lights?.points || []) {
    const m = pointMarker(L.pos[0], L.pos[1], L.pos[2], MATS.light, 1.6)
    m.userData = { roomId: id, kind: 'light', brightness: L.brightness }
    lightsGroup.add(m)
  }
  g.add(lightsGroup)

  // ── Planos de profundidade das máscaras ──────────────────────────────────
  const maskGroup = new THREE.Group()
  maskGroup.name = 'maskPlanes'
  maskGroup.visible = false

  for (const cam of src.cameras || []) {
    const planes = maskDepthPlanes(cam, b.aabb ? b : null)
    planes.name = `maskCam:${cam.index}`
    maskGroup.add(planes)
  }
  g.add(maskGroup)

  // ── Aplicar pose ─────────────────────────────────────────────────────────
  applyPose(g, pose)
  return g
}

/**
 * Aplica a pose (tx, tz, rot_deg) ao grupo da sala.
 */
export function applyPose(group, pose) {
  group.position.set(M(pose.tx ?? 0), 0, M(pose.tz ?? 0))
  group.rotation.y = -THREE.MathUtils.degToRad(pose.rot_deg ?? 0)
}

/**
 * Linhas ligando as pontas das portas entre salas.
 */
export function buildLinks(roomGroups, roomsData) {
  const pts = []
  const seen = new Set()

  for (const [id, src] of Object.entries(roomsData)) {
    const ga = roomGroups.get(id)
    if (!ga) continue

    for (const door of src.doors || []) {
      const dst = door.to_room
      const gb = roomGroups.get(dst)
      if (!gb || !door.box) continue

      const key = [id, dst].sort().join('>') + ':' + door.i
      if (seen.has(key)) continue
      seen.add(key)

      const back = roomsData[dst]?.doors?.find(x => x.to_room === id)
      if (!back?.box) continue

      const a = new THREE.Vector3(M(door.box.x + door.box.w / 2), 0.5, M(door.box.z + door.box.d / 2))
      const bb = new THREE.Vector3(M(back.box.x + back.box.w / 2), 0.5, M(back.box.z + back.box.d / 2))
      ga.localToWorld(a)
      gb.localToWorld(bb)
      pts.push(a, bb)
    }
  }

  if (!pts.length) return null
  const geo = new THREE.BufferGeometry().setFromPoints(pts)
  const lines = new THREE.LineSegments(
    geo,
    new THREE.LineBasicMaterial({ color: COLORS.link, transparent: true, opacity: 0.45 })
  )
  lines.name = 'links'
  return lines
}

/**
 * Caixa de seleção ao redor de um objeto.
 */
export function selectionBox(obj) {
  const box3 = new THREE.Box3().setFromObject(obj)
  if (box3.isEmpty()) return null
  return new THREE.Box3Helper(box3, COLORS.sel)
}

export { M as toMeters }
