/**
 * main.js — Bootstrap da RE3 Scene Forge.
 * Cola: cena, blockout, projeção, navegador, camadas, inspector, exportação.
 */
import { SceneManager }  from './scene.js'
import { buildRoom, buildLinks, selectionBox, WORLD_SCALE } from './blockout.js'
import { loadBackgrounds, applyProjection, removeProjection, createBgPlane, clearProjectionCache } from './projection.js'
import { Navigator }     from './navigator.js'
import { LayerManager }  from './layers.js'
import { Inspector }     from './inspector.js'
import { ExporterUI }    from './exporter_ui.js'

// ── Estado global ─────────────────────────────────────────────────────────────
const state = {
  currentRoom:    null,  // dados de room.src.json
  currentStage:   null,  // número do stage
  stageData:      null,  // dados do stage (todas as salas + layout)
  roomGroup:      null,  // THREE.Group da sala atual
  allRoomGroups:  new Map(),  // Map<roomId, THREE.Group> do stage
  allRoomsData:   {},    // Map<roomId, room.src.json>
  linksObj:       null,  // linhas de grafo
  selBox:         null,  // caixa de seleção
  currentRoom: null,
  texMap: new Map(),
  projEnabled: true
}

// ── Inicialização ─────────────────────────────────────────────────────────────
const canvas = document.getElementById('canvas3d')
const scene  = new SceneManager(canvas)

// Splash
const splash     = document.getElementById('splash')
const splashBar  = document.getElementById('splashBar')
const splashStat = document.getElementById('splashStatus')
const appEl      = document.getElementById('app')

function splashProgress(pct, msg) {
  splashBar.style.width = `${pct}%`
  splashStat.textContent = msg
}

// Layer manager
const layers = new LayerManager(scene)

// Inspector
const inspector = new Inspector({
  onCameraSelect: (idx) => {
    scene.setMode('original')
    scene._camIndex = idx
    scene._applyOriginalCam(idx)
    updateCamControls()
  },
  onDoorNavigate: (roomId) => nav.navigateToDoor(roomId),
})

// Navigator
splashProgress(10, 'Conectando ao servidor...')

const nav = new Navigator({
  onStageChange: async (data) => {
    splashProgress(30, `Carregando Stage ${data.stage}...`)
    state.currentStage = data.stage
    state.stageData    = data
    await loadStage(data)
    splashProgress(100, 'Pronto!')
    setTimeout(() => {
      splash.style.opacity = '0'
      splash.style.transition = 'opacity 0.4s'
      setTimeout(() => {
        splash.classList.add('hidden')
        appEl.classList.remove('hidden')
      }, 400)
    }, 300)
  },
  onRoomChange: async (data) => {
    await loadRoom(data)
  },
})

const exporter = new ExporterUI({
  getCurrentRoom:  () => state.currentRoom?.room?.room ? [state.currentRoom.room.room] : [],
  getCurrentStage: () => nav.currentStage,
  getAllRooms:     () => Object.keys(state.allRoomsData),
  getCustomBoxes:  () => {
    const boxes = []
    state.allRoomGroups.forEach((group, roomId) => {
      group.children.forEach(c => {
        if (c.userData.kind === 'customBox') {
          boxes.push({
            roomId,
            pos: [c.position.x, c.position.y, c.position.z],
            scale: [c.scale.x, c.scale.y, c.scale.z],
            rot: [c.rotation.x, c.rotation.y, c.rotation.z]
          })
        }
      })
    })
    return boxes
  }
})

// ── Carregamento de stage ─────────────────────────────────────────────────────
async function loadStage(data) {
  scene.clear()
  state.allRoomGroups.clear()
  state.allRoomsData = {}

  const layout = data.layout?.rooms || {}
  const rooms  = data.rooms || []
  let loaded = 0

  for (const roomSummary of rooms) {
    try {
      const res = await fetch(`/api/room/${roomSummary.id}`)
      const roomData = await res.json()
      const src  = roomData.room
      const pose = layout[roomSummary.id] || { tx: 0, tz: 0, rot_deg: 0 }

      state.allRoomsData[roomSummary.id] = src
      const group = buildRoom(src, pose)
      state.allRoomGroups.set(roomSummary.id, group)
      scene.stageRoot.add(group)

      loaded++
      splashProgress(30 + (loaded / rooms.length) * 55, `Sala ${roomSummary.id}...`)
    } catch (e) {
      console.warn(`Falha ao carregar sala ${roomSummary.id}:`, e)
    }
  }

  // Links (grafo de portas)
  if (state.linksObj) scene.scene.remove(state.linksObj)
  state.linksObj = buildLinks(state.allRoomGroups, state.allRoomsData)
  if (state.linksObj) {
    scene.scene.add(state.linksObj)
    layers.setLinks(state.linksObj)
  }

  scene.focusStage()
  updateStatus()
}

// ── Carregamento de sala individual ──────────────────────────────────────────
async function loadRoom(data) {
  state.currentRoom = data
  const src      = data.room
  const bgUrls   = data.bg_urls || {}
  const cameras  = src.cameras || []
  const stageN   = data.stage

  // Destaca a sala no stage
  const layout = state.stageData?.layout?.rooms || {}
  const pose   = layout[src.room] || { tx: 0, tz: 0, rot_deg: 0 }

  // Atualiza ou cria o grupo da sala (em caso de mudança de stage)
  if (!state.allRoomGroups.has(src.room)) {
    const group = buildRoom(src, pose)
    state.allRoomGroups.set(src.room, group)
    scene.stageRoot.add(group)
    state.allRoomsData[src.room] = src
  }

  const group = state.allRoomGroups.get(src.room)
  state.roomGroup = group

  // Foca na sala
  scene.focusOn(group)

  // Caixa de seleção
  if (state.selBox) scene.scene.remove(state.selBox)
  state.selBox = selectionBox(group)
  if (state.selBox) scene.scene.add(state.selBox)

  // Câmeras para modo original
  scene.setOriginalCams(cameras, group)

  // Carrega texturas e aplica projeção
  clearProjectionCache()
  splashProgress(85, 'Carregando backgrounds...')
  state.texMap = await loadBackgrounds(cameras)
  splashProgress(95, 'Projetando...')

  if (state.projEnabled && state.texMap.size > 0) {
    const shellGroup = group.getObjectByName('shell')
    if (shellGroup) {
      applyProjection(shellGroup, cameras, state.texMap, parseFloat(document.getElementById('fovSlider')?.value || 55), { roomGroup: group })
    }
  }

  // Define o background se estiver no modo original
  if (scene.mode === 'original' && cameras[0] && state.texMap.has(0)) {
    scene.scene.background = state.texMap.get(0)
  } else {
    scene.scene.background = null
  }

  // Inspector
  inspector.setRoom(data)

  // Camadas
  layers.setRoomGroup(group)
  layers.setLinks(state.linksObj)

  updateStatus()
  updateCamControls()

  // Habilita botão de câmera original se houver câmeras
  document.getElementById('btnCamOriginal').disabled = cameras.length === 0
}

// ── Controles de UI ───────────────────────────────────────────────────────────

// Modos de câmera
document.getElementById('btnOrbit').addEventListener('click', () => scene.setMode('orbit'))
document.getElementById('btnFly').addEventListener('click', () => scene.setMode('fly'))
document.getElementById('btnCamOriginal').addEventListener('click', () => {
  scene.setMode(scene.mode === 'original' ? 'orbit' : 'original')
})

scene.on('modeChange', (mode) => {
  document.getElementById('btnOrbit').classList.toggle('active', mode === 'orbit')
  document.getElementById('btnFly').classList.toggle('active', mode === 'fly')
  document.getElementById('btnCamOriginal').classList.toggle('active', mode === 'original')
  document.getElementById('fovControls').style.display = mode === 'original' ? 'none' : 'flex'
  
  if (mode === 'original' && state.currentRoom) {
    const tex = state.texMap.get(scene._camIndex)
    scene.scene.background = tex || null
  } else {
    scene.scene.background = null
  }

  document.getElementById('statusCam').textContent = {
    orbit: 'Orbital', fly: 'Voar', original: 'Câmera Original'
  }[mode] || mode
})

// Controles câmera original
document.getElementById('btnPrevCam').addEventListener('click', () => { scene.prevOriginalCam(); updateCamControls() })
document.getElementById('btnNextCam').addEventListener('click', () => { scene.nextOriginalCam(); updateCamControls() })
document.getElementById('btnExitCam').addEventListener('click', () => scene.setMode('orbit'))

document.getElementById('btnAdd').addEventListener('click', () => {
  if (!state.roomGroup || scene.mode !== 'orbit') return
  const s = 1000 / WORLD_SCALE
  const geo = new THREE.BoxGeometry(s, s, s)
  const mat = new THREE.MeshBasicMaterial({ color: 0x00ffaa, transparent: true, opacity: 0.6 })
  const mesh = new THREE.Mesh(geo, mat)
  mesh.userData = { kind: 'customBox', isExportable: true }
  
  // Posiciona onde a câmera orbit está olhando
  mesh.position.copy(scene.orbit.target)
  state.roomGroup.worldToLocal(mesh.position)
  
  state.roomGroup.add(mesh)
  scene._emit('select', mesh)
})

function updateCamControls() {
  if (!state.currentRoom) return
  const cams = state.currentRoom.room.cameras || []
  const index = scene._camIndex
  document.getElementById('camStatus').textContent = `${index + 1} / ${cams.length}`
  
  // Atualiza background
  const tex = state.texMap.get(index)
  if (scene.mode === 'original') {
    scene.scene.background = tex || null
  }

  // Projeção na malha
  const allCams = document.getElementById('chkAllCams')?.checked !== false
  if (!allCams && state.roomGroup) {
    const shellGroup = state.roomGroup.getObjectByName('shell')
    if (shellGroup) {
      const cameras = state.currentRoom?.room?.cameras || []
      applyProjection(shellGroup, cameras, state.texMap,
        parseFloat(document.getElementById('fovSlider').value),
        { allCams: false, activeCam: index, roomGroup: state.roomGroup }
      )
    }
  }
}

// Checkboxes do modo câmera
document.getElementById('chkAllCams')?.addEventListener('change', () => _reproject())
document.getElementById('chkProjectMesh')?.addEventListener('change', (e) => {
  state.projEnabled = e.target.checked
  _reproject()
})

function _reproject() {
  if (!state.roomGroup || !state.currentRoom) return
  const shellGroup = state.roomGroup.getObjectByName('shell')
  if (!shellGroup) return
  const cameras = state.currentRoom.room?.cameras || []
  const allCams = document.getElementById('chkAllCams')?.checked !== false
  const projMesh = document.getElementById('chkProjectMesh')?.checked !== false

  if (projMesh && state.texMap.size > 0) {
    applyProjection(shellGroup, cameras, state.texMap,
      parseFloat(document.getElementById('fovSlider').value),
      { allCams, activeCam: scene._camIndex, roomGroup: state.roomGroup }
    )
  } else {
    removeProjection(shellGroup)
  }
}

// FOV
document.getElementById('fovSlider')?.addEventListener('input', (e) => {
  const deg = parseFloat(e.target.value)
  document.getElementById('fovValue').textContent = `${deg}°`
  scene.setFov(deg)
  _reproject()
})

// Collapse panels
document.getElementById('btnCollapseLeft')?.addEventListener('click', () => {
  document.getElementById('leftPanel').classList.toggle('collapsed')
})
document.getElementById('btnCollapseRight')?.addEventListener('click', () => {
  document.getElementById('rightPanel').classList.toggle('collapsed')
})

// Seleção de objeto via clique
scene.on('select', (obj) => {
  if (!obj) {
    scene.transformControl?.detach()
    if (state.selBox) { scene.scene.remove(state.selBox); state.selBox = null }
    return
  }
  
  const ud = obj.userData
  if (ud.kind === 'door' && ud.door) {
    inspector.setSelectedObject(obj)
  } else if (ud.rectData || ud.kind === 'customBox') {
    inspector.setSelectedObject(obj)
  }
  
  if ((ud.rectData || ud.kind === 'customBox') && scene.mode === 'orbit') {
    scene.transformControl?.attach(obj)
  } else {
    scene.transformControl?.detach()
  }

  // Caixa de seleção no objeto
  if (state.selBox) scene.scene.remove(state.selBox)
  state.selBox = selectionBox(obj)
  if (state.selBox) scene.scene.add(state.selBox)
})

scene.transformControl?.addEventListener('change', () => {
  if (state.selBox && state.selBox.update) state.selBox.update()
})

window.addEventListener('keydown', (e) => {
  if (!scene.transformControl) return
  if (e.key === 't' || e.key === 'T') scene.transformControl.setMode('translate')
  if (e.key === 'r' || e.key === 'R') scene.transformControl.setMode('rotate')
  if (e.key === 's' || e.key === 'S') scene.transformControl.setMode('scale')
  if (e.key === 'Delete' || e.key === 'Backspace') {
    const obj = scene.transformControl.object
    if (obj && obj.userData.kind === 'customBox') {
      scene.transformControl.detach()
      obj.removeFromParent()
      if (state.selBox) { scene.scene.remove(state.selBox); state.selBox = null }
    }
  }
})

scene.on('escape', () => {
  scene.transformControl?.detach()
  if (state.selBox) { scene.scene.remove(state.selBox); state.selBox = null }
})

// ── Helpers de status ─────────────────────────────────────────────────────────
function updateStatus() {
  const room = state.currentRoom?.room
  document.getElementById('statusRoom').textContent = room ? `${room.room} — ${room.desc || room.area || ''}` : '—'
}

// ── Resize do canvas ──────────────────────────────────────────────────────────
const resizeObs = new ResizeObserver(() => scene._resize())
resizeObs.observe(canvas)
