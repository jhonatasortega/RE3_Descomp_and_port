/**
 * blockout.js — monta a geometria 3D de um stage a partir dos dados do jogo.
 *
 * Cada sala vira um THREE.Group posicionado pela pose (solver ou ajuste manual).
 * Dentro do grupo, tudo fica em coordenadas LOCAIS da sala convertidas para
 * metros — assim mover a sala nunca mexe na geometria interna.
 *
 * Hierarquia:
 *   stageRoot
 *     └─ room:<id>            (Group, pose da sala)
 *         ├─ floor            (piso = AABB da colisao)
 *         ├─ rect:<i>         (parede ou movel, do bloco de colisao do RDT)
 *         ├─ door:<i>         (gatilho de porta, do room_graph)
 *         └─ cam:<i>          (frustum da camera original)
 */
import * as THREE from 'three'
import { WORLD_SCALE } from './store.js'

const M = (u) => u / WORLD_SCALE

export const COLORS = {
  floor: 0x2a3140,
  wall: 0x6b7488,
  prop: 0xa2762f,
  sat: 0x503a5a,
  door: 0x3fa7d6,
  doorOneway: 0xd6733f,
  cam: 0x7ee081,
  link: 0x4ea3ff,
  sel: 0xffcf5c,
  trigger: 0x9b6bd6,
  message: 0x5c8fb8,
  flag: 0xd65c9b,
  item: 0x63d67a,
  enemy: 0xd64f4f,
  light: 0xffe08a,
}

const geoBox = new THREE.BoxGeometry(1, 1, 1)
const geoPlane = new THREE.PlaneGeometry(1, 1)

function mat(color, opts = {}) {
  return new THREE.MeshLambertMaterial({
    color,
    transparent: opts.opacity !== undefined,
    opacity: opts.opacity ?? 1,
    depthWrite: (opts.opacity ?? 1) > 0.9,
    side: opts.side ?? THREE.FrontSide,
    ...opts.extra,
  })
}

const MATS = {
  // vista por dentro: as faces de fora não atrapalham quem olha a sala de longe
  // paredes e chão: vistos dos dois lados
  shell: mat(0x8a90a0, { side: THREE.DoubleSide }),
  // teto: só visível DE BAIXO — assim olhar a sala de cima mostra o interior
  // em vez de uma tampa cinza
  ceiling: mat(0x7d8494, { side: THREE.BackSide }),
  floor: mat(COLORS.floor, { side: THREE.DoubleSide }),
  wall: mat(COLORS.wall, { opacity: 0.62, side: THREE.DoubleSide }),
  prop: mat(COLORS.prop, { opacity: 0.78 }),
  sat: mat(COLORS.sat, { opacity: 0.22, side: THREE.DoubleSide }),
  door: mat(COLORS.door, { opacity: 0.55, side: THREE.DoubleSide }),
  doorOneway: mat(COLORS.doorOneway, { opacity: 0.55, side: THREE.DoubleSide }),
  sel: new THREE.MeshBasicMaterial({ color: COLORS.sel, wireframe: true }),
  trigger: mat(COLORS.trigger, { opacity: 0.3, side: THREE.DoubleSide }),
  message: mat(COLORS.message, { opacity: 0.28, side: THREE.DoubleSide }),
  flag: mat(COLORS.flag, { opacity: 0.32, side: THREE.DoubleSide }),
  item: new THREE.MeshBasicMaterial({ color: COLORS.item }),
  enemy: new THREE.MeshBasicMaterial({ color: COLORS.enemy }),
  light: new THREE.MeshBasicMaterial({ color: COLORS.light }),
}

const geoSphere = new THREE.SphereGeometry(0.35, 10, 8)

/** Caixa baixa marcando uma area de gatilho (AOT) no chao. */
function aotMesh(a, floorY, material, height = 600) {
  const b = a.box
  if (!b) return null
  const m = new THREE.Mesh(geoBox, material)
  m.scale.set(M(Math.max(b.w, 40)), M(height), M(Math.max(b.d, 40)))
  m.position.set(M(b.x + b.w / 2), M(-floorY) + M(height / 2), M(b.z + b.d / 2))
  return m
}

/** Marcador pontual (item, inimigo, luz). */
function pointMesh(x, y, z, material, scale = 1) {
  const m = new THREE.Mesh(geoSphere, material)
  m.position.set(M(x), M(-y), M(z))
  m.scale.setScalar(scale)
  return m
}

/**
 * Caixa a partir de um rect de colisao.
 *
 * rect = [x0,z0,x1,z1] no plano XZ; `y` e o piso e **`h` e a ALTURA**, nao a
 * coordenada do topo. Medido nos 5.289 rects: como altura, mediana 4,9 m e
 * maximo 10,1 m, nenhuma negativa; interpretado como topo (`|h-y|`), o maximo
 * ia a 50,6 m — as "colunas gigantes" que apareciam no blockout.
 *
 * O Y do PS1 aponta para BAIXO, entao subir `h` e SUBTRAIR de `y`.
 */
function rectMesh(r, material) {
  const [x0, z0, x1, z1] = r.rect
  const w = Math.max(Math.abs(x1 - x0), 1)
  const d = Math.max(Math.abs(z1 - z0), 1)
  const hgt = Math.max(Math.abs(r.h), 1)

  const m = new THREE.Mesh(geoBox, material)
  m.scale.set(M(w), M(hgt), M(d))
  m.position.set(M((x0 + x1) / 2), M(-r.y) + M(hgt / 2), M((z0 + z1) / 2))
  return m
}

function doorMesh(door, floorY) {
  const b = door.box
  if (!b) return null
  // box.x/z e o CANTO (medido: |arrival - canto| mediano 1,8 m vs 3,0 m do centro)
  const m = new THREE.Mesh(geoBox, door.reciprocal ? MATS.door : MATS.doorOneway)
  m.scale.set(M(Math.max(b.w, 40)), M(2000), M(Math.max(b.d, 40)))
  m.position.set(M(b.x + b.w / 2), M(-floorY) + M(1000), M(b.z + b.d / 2))
  return m
}

function camHelper(cam) {
  const g = new THREE.Group()
  const from = new THREE.Vector3(M(cam.pos[0]), M(-cam.pos[1]), M(cam.pos[2]))
  const to = new THREE.Vector3(M(cam.target[0]), M(-cam.target[1]), M(cam.target[2]))

  const body = new THREE.Mesh(
    new THREE.ConeGeometry(0.25, 0.6, 4),
    new THREE.MeshBasicMaterial({ color: COLORS.cam })
  )
  body.position.copy(from)
  body.lookAt(to)
  body.rotateX(Math.PI / 2)
  g.add(body)

  const line = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints([from, to]),
    new THREE.LineBasicMaterial({ color: COLORS.cam, transparent: true, opacity: 0.5 })
  )
  g.add(line)
  return g
}

/** Aplica pose (unidades PS1 + graus) ao grupo da sala. */
export function applyPose(group, pose) {
  group.position.set(M(pose.tx), 0, M(pose.tz))
  // O solver compoe (x,z) com rotacao matematica; em three, girar em torno de
  // +Y percorre o sentido oposto no plano XZ — dai o sinal invertido.
  group.rotation.y = -THREE.MathUtils.degToRad(pose.rot_deg || 0)
}

/**
 * Casca da sala: chão, teto e as 4 paredes do perímetro, como uma caixa vista
 * POR DENTRO (`BackSide`).
 *
 * Os retângulos de colisão sozinhos são barreiras soltas — não fecham um cômodo,
 * e a câmera dentro deles não tem em que projetar a foto. A casca dá as
 * superfícies que faltavam: é nela que a textura do background se aplica.
 *
 * É uma aproximação: usa o AABB da colisão, então salas em L viram retângulo.
 * Serve de ponto de partida para o ajuste manual.
 */
function shellMesh(bounds, material) {
  const [x0, z0, x1, z1] = bounds.aabb
  const w = Math.max(x1 - x0, 1)
  const d = Math.max(z1 - z0, 1)
  // pé-direito típico (mediana), não o rect mais alto da sala
  const h = Math.max(bounds.ceiling_h ?? Math.abs(bounds.y_floor - bounds.y_ceiling), 1)

  const mesh = new THREE.Mesh(geoBox, material)
  mesh.scale.set(M(w), M(h), M(d))
  mesh.position.set(
    M((x0 + x1) / 2),
    M(-bounds.y_floor) + M(h / 2),
    M((z0 + z1) / 2)
  )
  return mesh
}

/**
 * Uma parede da geometria, com os vãos recortados.
 *
 * Sem CSG: o vão é feito partindo a parede em pedaços — os trechos cheios entre
 * as aberturas, mais a verga acima de cada vão e o peitoril abaixo (janela).
 * Mais barato e mais robusto que boolean, e dá exatamente o mesmo resultado
 * para aberturas retangulares.
 */
function wallMeshes(wall, material) {
  const [ax, az] = wall.a
  const [bx, bz] = wall.b
  const len = Math.hypot(bx - ax, bz - az)
  if (len < 1) return []

  const angle = Math.atan2(bz - az, bx - ax)
  const th = wall.thickness
  const H = wall.height
  const baseY = -wall.y                     // Y do PS1 aponta para baixo

  // vãos ordenados, em unidades de comprimento ao longo da parede
  const gaps = (wall.openings || [])
    .map((o) => {
      const c = o.u * len
      const w = Math.min(o.width, len)
      return { ...o, start: Math.max(0, c - w / 2), end: Math.min(len, c + w / 2) }
    })
    .sort((a, b) => a.start - b.start)

  const parts = []          // { s, e, y0, y1 } em coords da parede
  let cursor = 0
  for (const g of gaps) {
    if (g.start > cursor) parts.push({ s: cursor, e: g.start, y0: 0, y1: H })
    const top = g.sill + g.height
    if (top < H) parts.push({ s: g.start, e: g.end, y0: top, y1: H })   // verga
    if (g.sill > 0) parts.push({ s: g.start, e: g.end, y0: 0, y1: g.sill })  // peitoril
    cursor = Math.max(cursor, g.end)
  }
  if (cursor < len) parts.push({ s: cursor, e: len, y0: 0, y1: H })

  const out = []
  for (const p of parts) {
    const segLen = p.e - p.s
    const segH = p.y1 - p.y0
    if (segLen < 1 || segH < 1) continue
    const mid = (p.s + p.e) / 2
    const m = new THREE.Mesh(geoBox, material)
    m.scale.set(M(segLen), M(segH), M(th))
    m.position.set(
      M(ax + Math.cos(angle) * mid),
      M(baseY) + M(p.y0 + segH / 2),
      M(az + Math.sin(angle) * mid)
    )
    m.rotation.y = -angle
    out.push(m)
  }
  return out
}

/** Chão e teto como planos, a partir da geometria gerada. */
function slab(aabb, y, material, faceUp) {
  const [x0, z0, x1, z1] = aabb
  const m = new THREE.Mesh(geoPlane, material)
  m.rotation.x = faceUp ? -Math.PI / 2 : Math.PI / 2
  m.scale.set(M(Math.max(x1 - x0, 1)), M(Math.max(z1 - z0, 1)), 1)
  m.position.set(M((x0 + x1) / 2), M(-y), M((z0 + z1) / 2))
  return m
}

export function buildRoom(store, id) {
  const src = store.rooms[id]
  const g = new THREE.Group()
  g.name = `room:${id}`
  g.userData = { roomId: id, kind: 'room' }
  if (!src) return g

  const b = src.bounds
  const floorY = b ? b.y_floor : 0

  // GEOMETRIA: paredes com vãos + chão + teto (de room.geom.json).
  // É esta a superfície que recebe a foto — não os volumes de colisão.
  const geom = store.geom?.[id]
  const shellGroup = new THREE.Group()
  shellGroup.name = 'shell'
  if (geom) {
    for (const wall of geom.walls || []) {
      for (const m of wallMeshes(wall, MATS.shell)) {
        m.userData = { roomId: id, kind: 'shell', wallRect: wall.from_rect }
        shellGroup.add(m)
      }
    }
    if (geom.floor) {
      const f = slab(geom.floor.aabb, geom.floor.y, MATS.shell, true)
      f.userData = { roomId: id, kind: 'shell', part: 'floor' }
      shellGroup.add(f)
    }
    if (geom.ceiling) {
      const c = slab(geom.ceiling.aabb, geom.ceiling.y, MATS.ceiling, false)
      c.name = 'ceiling'
      c.userData = { roomId: id, kind: 'shell', part: 'ceiling' }
      shellGroup.add(c)
    }
  } else if (b) {
    // sem geometria gerada: cai na caixa do AABB
    const shell = shellMesh(b, MATS.shell)
    shell.userData = { roomId: id, kind: 'shell' }
    shellGroup.add(shell)
  }
  g.add(shellGroup)

  // piso — plano separado, para quando a casca está desligada
  if (b) {
    const [x0, z0, x1, z1] = b.aabb
    const f = new THREE.Mesh(geoPlane, MATS.floor)
    f.rotation.x = -Math.PI / 2
    f.scale.set(M(Math.max(x1 - x0, 1)), M(Math.max(z1 - z0, 1)), 1)
    f.position.set(M((x0 + x1) / 2), M(-floorY) - 0.01, M((z0 + z1) / 2))
    f.name = 'floor'
    f.userData = { roomId: id, kind: 'floor' }
    g.add(f)
  }

  // colisao
  const rects = new THREE.Group()
  rects.name = 'rects'
  for (const raw of src.collision?.rects || []) {
    const r = store.effectiveRect(id, raw)
    if (r.hidden) continue
    // `edge` (encosta no limite s16) continua sendo parede real e fica visivel;
    // so o `sentinel` degenerado vai para a camada que nasce desligada.
    const kind = r.sentinel ? 'sat' : r.wall ? 'wall' : 'prop'
    const material = r.sentinel ? MATS.sat : r.wall ? MATS.wall : MATS.prop
    const m = rectMesh(r, material)
    m.name = `rect:${r.i}`
    m.userData = { roomId: id, kind, rectIndex: r.i }
    rects.add(m)
  }
  g.add(rects)

  // portas
  const doors = new THREE.Group()
  doors.name = 'doors'
  for (const d of src.doors || []) {
    const m = doorMesh(d, floorY)
    if (!m) continue
    m.name = `door:${d.i}`
    m.userData = { roomId: id, kind: 'door', doorIndex: d.i, to: d.to_room }
    doors.add(m)
  }
  g.add(doors)

  // gameplay: gatilhos, mensagens, flags, itens, inimigos (de-para do original)
  const gp = src.gameplay || {}
  const mkGroup = (name, visible = false) => {
    const grp = new THREE.Group()
    grp.name = name
    grp.visible = visible
    g.add(grp)
    return grp
  }

  const gTrig = mkGroup('triggers')
  for (const [list, material, kind] of [
    [gp.triggers, MATS.trigger, 'trigger'],
    [gp.messages, MATS.message, 'message'],
    [gp.flags, MATS.flag, 'flag'],
  ]) {
    for (const a of list || []) {
      const mesh = aotMesh(a, floorY, material)
      if (!mesh) continue
      mesh.name = `${kind}:${a.aot}`
      mesh.userData = { roomId: id, kind, aot: a.aot, event: a.event }
      gTrig.add(mesh)
    }
  }

  const gEnt = mkGroup('entities')
  for (const it of gp.items || []) {
    const mesh = pointMesh(it.x ?? 0, it.y ?? floorY, it.z ?? 0, MATS.item)
    mesh.userData = { roomId: id, kind: 'item', item: it.item_name || it.item_id }
    gEnt.add(mesh)
  }
  for (const en of gp.enemies || []) {
    const mesh = pointMesh(en.x ?? 0, en.y ?? floorY, en.z ?? 0, MATS.enemy, 1.3)
    mesh.userData = { roomId: id, kind: 'enemy', species: en.species }
    gEnt.add(mesh)
  }

  const gLights = mkGroup('lights')
  for (const L of src.lights?.points || []) {
    const mesh = pointMesh(L.pos[0], L.pos[1], L.pos[2], MATS.light, 1.6)
    mesh.userData = { roomId: id, kind: 'light', brightness: L.brightness }
    gLights.add(mesh)
  }

  // cameras
  const cams = new THREE.Group()
  cams.name = 'cams'
  cams.visible = false
  for (const c of src.cameras || []) {
    const h = camHelper(c)
    h.name = `cam:${c.index}`
    h.userData = { roomId: id, kind: 'cam', camIndex: c.index }
    cams.add(h)
  }
  g.add(cams)

  applyPose(g, store.pose(id))
  return g
}

/** Linhas ligando as duas pontas de cada porta — mostra o grafo no espaco. */
export function buildLinks(store, roomGroups) {
  const pts = []
  const seen = new Set()
  for (const id of store.ids) {
    const src = store.rooms[id]
    const ga = roomGroups.get(id)
    if (!ga) continue
    for (const d of src.doors || []) {
      const dst = d.to_room
      const gb = roomGroups.get(dst)
      if (!gb || !d.box) continue
      const key = [id, dst].sort().join('>') + ':' + d.i
      if (seen.has(key)) continue
      seen.add(key)

      const back = store.rooms[dst]?.doors?.find((x) => x.to_room === id)
      if (!back?.box) continue

      const a = new THREE.Vector3(M(d.box.x + d.box.w / 2), 0, M(d.box.z + d.box.d / 2))
      const bb = new THREE.Vector3(M(back.box.x + back.box.w / 2), 0, M(back.box.z + back.box.d / 2))
      ga.localToWorld(a)
      gb.localToWorld(bb)
      pts.push(a, bb)
    }
  }
  const geo = new THREE.BufferGeometry().setFromPoints(pts)
  const line = new THREE.LineSegments(
    geo,
    new THREE.LineBasicMaterial({ color: COLORS.link, transparent: true, opacity: 0.45 })
  )
  line.name = 'links'
  line.userData.kind = 'links'
  return line
}

/** Caixa de selecao ao redor da sala. */
export function selectionBox(group) {
  const box = new THREE.Box3().setFromObject(group)
  if (box.isEmpty()) return null
  const helper = new THREE.Box3Helper(box, COLORS.sel)
  helper.name = 'selection'
  return helper
}

export { M as toMeters }
