/**
 * main.js — cola tudo: carrega o stage, monta o blockout, liga UI e interacao.
 */
import { Store, WORLD_SCALE } from './store.js'
import { Viewport } from './scene.js'
import { buildRoom, buildLinks, applyPose, selectionBox } from './blockout.js'
import { CameraProjection } from './projection.js'
import { UI } from './ui.js'

const store = new Store()
const view = new Viewport(document.getElementById('view'))
const ui = new UI(store)
const projection = new CameraProjection(view.scene, {
  store,
  getRoomGroup: (id) => roomGroups.get(id),
  viewport: view,
  // ao isolar, some também com as ligações e os rótulos das outras salas
  onIsolation: (roomId) => {
    if (links) links.visible = ui.layers.links && !roomId
    ui.setLabelFilter(roomId)
  },
})

const roomGroups = new Map()   // id -> THREE.Group
let links = null
let selection = null           // id da sala selecionada
let selHelper = null
let dragging = null            // { id, grabPS1: {x,z}, startPose }

// ------------------------------------------------------------------ montagem

function clearStage() {
  projection.exit()
  for (const g of roomGroups.values()) view.root.remove(g)
  roomGroups.clear()
  if (links) { view.root.remove(links); links = null }
  if (selHelper) { view.scene.remove(selHelper); selHelper = null }
  selection = null
}

function buildStage() {
  clearStage()
  for (const id of store.ids) {
    const g = buildRoom(store, id)
    roomGroups.set(id, g)
    view.root.add(g)
  }
  rebuildLinks()
  applyLayers()
  view.focus(view.root, 1.15)
}

function rebuildLinks() {
  if (links) view.root.remove(links)
  links = buildLinks(store, roomGroups)
  links.visible = ui.layers.links
  view.root.add(links)
}

function rebuildRoom(id) {
  // o modo câmera guarda referências à malha antiga: sai antes de trocar
  if (projection.isActive && projection.active.roomId === id) exitCameraMode()
  const old = roomGroups.get(id)
  if (old) view.root.remove(old)
  const g = buildRoom(store, id)
  roomGroups.set(id, g)
  view.root.add(g)
  applyLayers()
  rebuildLinks()
  if (selection === id) updateSelectionHelper()
}

function applyLayers() {
  const L = ui.layers

  // "Isolar seleção": ver uma sala sozinha — no meio das 38 sobrepostas,
  // é a única forma de enxergar o volume de um cômodo.
  if (!projection.isActive) {
    const solo = L.isolate && selection ? selection : null
    for (const [id, g] of roomGroups) g.visible = !solo || id === solo
    ui.setLabelFilter(solo)
    if (links) links.visible = L.links && !solo
  }

  for (const g of roomGroups.values()) {
    for (const [name, on] of [
      ['shell', L.shell], ['floor', L.floor], ['doors', L.doors], ['cams', L.cams],
      ['triggers', L.triggers], ['entities', L.entities], ['lights', L.lights],
    ]) {
      const child = g.getObjectByName(name)
      if (child) child.visible = on
    }
    const rects = g.getObjectByName('rects')
    if (rects) {
      for (const m of rects.children) {
        const k = m.userData.kind
        m.visible = k === 'wall' ? L.walls : k === 'prop' ? L.props : L.sat
      }
    }
  }
  if (links) links.visible = L.links
  view.grid.visible = L.grid
  view.cardinals.visible = L.grid
  ui.setLabelsVisible(L.labels)
}

// ------------------------------------------------------------------ selecao

function select(id, { focus = false } = {}) {
  selection = id
  updateSelectionHelper()
  ui.setSelection(id)
  if (ui.layers.isolate) applyLayers()
  if (focus && id && roomGroups.has(id)) view.focus(roomGroups.get(id))
}

function updateSelectionHelper() {
  if (selHelper) { view.scene.remove(selHelper); selHelper = null }
  if (!selection) return
  const g = roomGroups.get(selection)
  if (!g) return
  selHelper = selectionBox(g)
  if (selHelper) view.scene.add(selHelper)
}

// ------------------------------------------------------------------ input

view.canvas.addEventListener('pointerdown', (e) => {
  if (e.button !== 0) return
  if (dragging) return
  const hits = view.pick(e)
  const hit = hits.find((h) => h.object.userData?.roomId)
  if (!hit) return
  if (hit.object.userData.roomId !== selection) {
    select(hit.object.userData.roomId)
  }
})

// duplo clique = entra na sala pelas câmeras originais, com a foto projetada
view.canvas.addEventListener('dblclick', async (e) => {
  const hits = view.pick(e)
  const hit = hits.find((h) => h.object.userData?.roomId)
  if (!hit) return
  const id = hit.object.userData.roomId
  select(id)
  await enterCameraMode(id, 0)
})

let lastFloorY = 0

async function enterCameraMode(id, camIndex) {
  // Os rects `prop` do RDT são VOLUMES DE COLISÃO de altura cheia (em R100 cada
  // um tem os 5,0 m de pé-direito e até 12x5 m de área), não móveis. Como
  // geometria visível eles entulham a sala e tapam a câmera. Dentro da sala a
  // superfície que vale é a casca; a colisão fica escondida por padrão.
  if (ui.layers.props) {
    ui.setLayerSilent('props', false)
    applyLayers()
  }

  const r = await projection.enter(id, camIndex)
  if (!r) {
    ui.status(`${id}: sem background HD para projetar`, 'warn')
    return
  }
  lastFloorY = r.floorY
  ui.setCameraMode(r)
  ui.status(
    `${id} · câmera ${r.camIndex + 1}/${r.total} · ${r.projectors} projetor(es)`
    + ' — [ ] troca, V anda, Esc sai', 'ok'
  )
}

/** Altura do olho no mundo: piso da sala + 1,6 m (Y do PS1 aponta p/ baixo). */
function eyeYForRoom(id) {
  const y = store.rooms[id]?.bounds?.y_floor ?? lastFloorY
  return -y / WORLD_SCALE + view.eyeHeight
}

function toggleWalk() {
  if (view.walk) {
    view.setWalk(false)
    ui.status('modo andar desligado')
    return
  }
  const id = projection.isActive ? projection.active.roomId : selection
  if (!id) {
    ui.status('selecione uma sala antes de andar', 'warn')
    return
  }
  view.setWalk(true, eyeYForRoom(id))
  ui.status('andando: WASD move, mouse olha, QE ajusta altura, V sai', 'ok')
}

async function stepCamera(delta) {
  const r = await projection.step(delta)
  if (r) {
    ui.setCameraMode(r)
    ui.status(`${r.roomId} · câmera ${r.camIndex + 1}/${r.total}`, 'ok')
  }
}

function exitCameraMode() {
  view.setWalk(false)
  projection.exit()
  ui.setCameraMode(null)
  view.camera.fov = 55
  view.camera.updateProjectionMatrix()
  ui.status('modo câmera encerrado')
}

// G = agarrar a sala e arrastar no plano do chao
addEventListener('keydown', (e) => {
  if (e.target.matches('input, select, textarea')) return

  if (e.code === 'KeyF' && selection) {
    view.focus(roomGroups.get(selection))
  }
  if (e.code === 'Escape') {
    if (dragging) cancelDrag()
    else if (view.walk) toggleWalk()
    else if (projection.isActive) exitCameraMode()
    else select(null)
  }
  if (e.code === 'KeyV') toggleWalk()
  if (projection.isActive) {
    if (e.code === 'BracketRight') stepCamera(1)
    if (e.code === 'BracketLeft') stepCamera(-1)
  } else if (e.code === 'KeyC' && selection) {
    enterCameraMode(selection, 0)
  }
  if (e.code === 'KeyG' && selection && !dragging) {
    const p = view.pointOnPlane(lastMouse, 0)
    if (!p) return
    dragging = {
      id: selection,
      grab: p.clone(),
      startPose: { ...store.pose(selection) },
    }
    view.controls.enabled = false
    ui.status(`arrastando ${selection} — clique para soltar, Esc cancela`)
  }
})

let lastMouse = { clientX: 0, clientY: 0 }
view.canvas.addEventListener('pointermove', (e) => {
  lastMouse = e
  if (!dragging) return
  const p = view.pointOnPlane(e, 0)
  if (!p) return
  const dx = (p.x - dragging.grab.x) * WORLD_SCALE
  const dz = (p.z - dragging.grab.z) * WORLD_SCALE
  const snap = e.ctrlKey ? 808 : 1        // Ctrl = passo de 1 m
  const tx = Math.round((dragging.startPose.tx + dx) / snap) * snap
  const tz = Math.round((dragging.startPose.tz + dz) / snap) * snap
  store.setPose(dragging.id, { tx, tz })
})

view.canvas.addEventListener('click', () => { if (dragging) endDrag() })

function endDrag() {
  const id = dragging.id
  dragging = null
  view.controls.enabled = true
  ui.status(`${id} movida`, 'ok')
}

function cancelDrag() {
  store.setPose(dragging.id, dragging.startPose)
  dragging = null
  view.controls.enabled = true
  ui.status('arraste cancelado')
}

// ------------------------------------------------------------------ eventos

store.on((evt, data) => {
  if (evt === 'pose') {
    const g = roomGroups.get(data)
    if (g) applyPose(g, store.pose(data))
    if (selection === data) updateSelectionHelper()
    rebuildLinks()
    ui.refreshInspector()
    ui.refreshRoomList()
  }
  if (evt === 'rect' || evt === 'opening') {
    rebuildRoom(typeof data === 'string' ? data : data.id)
    ui.refreshRoomList()
  }
})

ui.onStageChange = async (n) => {
  ui.status(`carregando STAGE${n}…`)
  await store.loadStage(n)
  buildStage()
  ui.afterStageLoad()
  ui.status(`STAGE${n}: ${store.ids.length} salas`, 'ok')
}
ui.onLayersChange = applyLayers
ui.onSelect = (id, focus) => select(id, { focus })
ui.onFocus = () => selection && view.focus(roomGroups.get(selection))
ui.onEnterCamera = (id, i) => enterCameraMode(id, i)
ui.onStepCamera = (d) => stepCamera(d)
ui.onExitCamera = () => exitCameraMode()
ui.onToggleWalk = () => toggleWalk()
ui.onProjectionOption = async (key, value) => {
  projection[key] = value
  if (key === 'fov') {
    const r = await projection.refresh()
    if (r) ui.setCameraMode(r)
  } else if (projection.isActive) {
    const r = await projection.refresh()
    if (r) ui.setCameraMode(r)
  }
}
ui.getProjection = () => projection
ui.getRoomGroup = (id) => roomGroups.get(id)
ui.getCamera = () => view.camera
ui.getCanvas = () => view.canvas

// ------------------------------------------------------------------ start

await ui.init()
view.start(() => ui.updateLabels())

// Porta de automação (usada por tools/shoot.mjs para renderizar e conferir).
// Não muda o comportamento do app; só dá acesso ao estado para inspeção.
window.__re3 = {
  store, view, projection, ui,
  roomGroups,
  select: (id) => select(id),
  enterCameraMode,
  stepCamera,
  exitCameraMode,
  toggleWalk,
  applyLayers,
  setLayer(name, on) { ui.layers[name] = on; applyLayers() },
  ready: true,
}
