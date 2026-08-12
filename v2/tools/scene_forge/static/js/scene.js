/**
 * scene.js — Cena Three.js: câmera, controles, loop de render.
 * Modos: Orbital / Voar (WASD+QE) / Câmera Original do jogo
 */
import * as THREE from 'three'
import { OrbitControls } from 'three/addons/controls/OrbitControls.js'
import { TransformControls } from 'three/addons/controls/TransformControls.js'

const WORLD_SCALE = 808

export class SceneManager {
  constructor(canvas) {
    this.canvas = canvas
    this.mode = 'orbit' // 'orbit' | 'fly' | 'original'
    this._listeners = {}
    this._keys = {}
    this._flySpeed = 8
    this._camIndex = 0
    this._currentRoomCams = []
    this._originalCamFov = 55

    this._initRenderer()
    this._initScene()
    this._initCameras()
    this._initOrbit()
    this._initGrid()
    this._initEvents()
    this._loop()
  }

  _initRenderer() {
    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvas,
      antialias: true,
      alpha: false,
    })
    this.renderer.setPixelRatio(window.devicePixelRatio)
    this.renderer.shadowMap.enabled = true
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap
    this.renderer.setClearColor(0x090c10)
    this._resize()
  }

  _initScene() {
    this.scene = new THREE.Scene()
    this.scene.fog = new THREE.FogExp2(0x090c10, 0.0004)

    // Iluminação ambiente
    const ambient = new THREE.AmbientLight(0xffffff, 0.35)
    this.scene.add(ambient)

    // Luz direcional principal
    const dirLight = new THREE.DirectionalLight(0xffffff, 0.9)
    dirLight.position.set(50, 80, 30)
    dirLight.castShadow = true
    dirLight.shadow.mapSize.setScalar(2048)
    this.scene.add(dirLight)

    // Luz de preenchimento (rim azulada)
    const fillLight = new THREE.DirectionalLight(0x3fa7d6, 0.3)
    fillLight.position.set(-30, 20, -50)
    this.scene.add(fillLight)

    // Raiz dos grupos de salas
    this.stageRoot = new THREE.Group()
    this.stageRoot.name = 'stageRoot'
    this.scene.add(this.stageRoot)

    // Grupo de projeção / shell separado
    this.projectionRoot = new THREE.Group()
    this.projectionRoot.name = 'projectionRoot'
    this.scene.add(this.projectionRoot)
  }

  _initCameras() {
    const w = this.canvas.clientWidth || 800
    const h = this.canvas.clientHeight || 600

    this.orbitCam = new THREE.PerspectiveCamera(55, w / h, 0.1, 2000)
    this.orbitCam.position.set(0, 50, 100)

    this.flyCam = new THREE.PerspectiveCamera(75, w / h, 0.1, 2000)
    this.flyCam.position.copy(this.orbitCam.position)

    this.originalCam = new THREE.PerspectiveCamera(55, 4 / 3, 0.1, 2000)

    this.activeCamera = this.orbitCam
  }

  _initOrbit() {
    this.orbit = new OrbitControls(this.orbitCam, this.canvas)
    this.orbit.enableDamping = true
    this.orbit.dampingFactor = 0.08
    this.orbit.minDistance = 1
    this.orbit.maxDistance = 1200
    this.orbit.enablePan = false // Pan desativado para evitar conflito com freelook, ou pode usar keys
    this.orbit.zoomSpeed = 1.2
    
    // Controles estilo Godot: 
    // Esquerdo: Null (usado para seleção)
    // Meio: Orbitar
    // Direito: Null (usado manualmente para Freelook/Voar)
    this.orbit.mouseButtons = {
      LEFT: null,
      MIDDLE: THREE.MOUSE.ROTATE,
      RIGHT: null
    }

    // TransformControls para editar blocos manuais
    this.transformControl = new TransformControls(this.orbitCam, this.canvas)
    this.transformControl.addEventListener('dragging-changed', (e) => {
      if (this.mode === 'orbit') {
        this.orbit.enabled = !e.value && !this._isRightClicking
      }
    })
    this.scene.add(this.transformControl)
  }

  _initGrid() {
    const grid = new THREE.GridHelper(2000, 100, 0x1a2030, 0x141c28)
    grid.name = 'grid'
    this.scene.add(grid)

    // Eixos de referência
    const axes = new THREE.AxesHelper(20)
    axes.name = 'axes'
    this.scene.add(axes)
  }

  _initEvents() {
    window.addEventListener('resize', () => this._resize())

    // Teclado
    window.addEventListener('keydown', (e) => {
      this._keys[e.code] = true
      this._onKey(e)
    })
    window.addEventListener('keyup', (e) => {
      this._keys[e.code] = false
    })

    // Pointer lock para modo voar
    this.canvas.addEventListener('click', () => {
      if (this.mode === 'fly') {
        try { this.canvas.requestPointerLock() } catch (err) {}
      }
    })
    document.addEventListener('pointerlockchange', () => {
      this._pointerLocked = document.pointerLockElement === this.canvas
    })

    // Modo Freelook / Voar estilo Godot (Botão Direito) no modo orbit
    this.canvas.addEventListener('mousedown', (e) => {
      if (e.button === 2 && this.mode === 'orbit') {
        this._isRightClicking = true
        this.orbit.enabled = false
        try { this.canvas.requestPointerLock() } catch (err) {}

        const euler = new THREE.Euler(0, 0, 0, 'YXZ')
        euler.setFromQuaternion(this.orbitCam.quaternion)
        this._yaw = euler.y
        this._pitch = euler.x
      }
    })

    window.addEventListener('mouseup', (e) => {
      if (e.button === 2 && this._isRightClicking) {
        this._isRightClicking = false
        if (this.mode === 'orbit') this.orbit.enabled = true
        if (document.pointerLockElement) document.exitPointerLock()
      }
    })

    this.canvas.addEventListener('mousemove', (e) => {
      if (this.mode === 'fly' && this._pointerLocked) {
        const mx = e.movementX || 0
        const my = e.movementY || 0
        this._flyYaw -= mx * 0.002
        this._flyPitch -= my * 0.002
        this._flyPitch = Math.max(-Math.PI / 2 + 0.01, Math.min(Math.PI / 2 - 0.01, this._flyPitch))
        this.flyCam.rotation.order = 'YXZ'
        this.flyCam.rotation.y = this._flyYaw
        this.flyCam.rotation.x = this._flyPitch
      } else if (this._isRightClicking && this.mode === 'orbit') {
        const mx = e.movementX || 0
        const my = e.movementY || 0
        
        this._yaw -= mx * 0.002
        this._pitch -= my * 0.002
        this._pitch = Math.max(-Math.PI / 2 + 0.01, Math.min(Math.PI / 2 - 0.01, this._pitch))
        
        this.orbitCam.quaternion.setFromEuler(new THREE.Euler(this._pitch, this._yaw, 0, 'YXZ'))
        
        const dist = this.orbitCam.position.distanceTo(this.orbit.target)
        const dir = new THREE.Vector3()
        this.orbitCam.getWorldDirection(dir)
        this.orbit.target.copy(this.orbitCam.position).addScaledVector(dir, dist)
      }
    })

    // Seleção (Botão Esquerdo)
    this.canvas.addEventListener('pointerdown', (e) => {
      if (e.button === 0 && !this._isRightClicking && this.mode !== 'fly') this._onCanvasClick(e)
    })
  }

  _isRightClicking = false
  _yaw = 0
  _pitch = 0
  _flyYaw = 0
  _flyPitch = 0
  _pointerLocked = false

  _onKey(e) {
    switch (e.code) {
      case 'KeyO': this.setMode('orbit'); break
      case 'KeyF': this.setMode('fly'); break
      case 'KeyC':
        if (this._currentRoomCams.length > 0)
          this.setMode(this.mode === 'original' ? 'orbit' : 'original')
        break
      case 'BracketLeft':
        this.prevOriginalCam(); break
      case 'BracketRight':
        this.nextOriginalCam(); break
      case 'Escape':
        if (this.mode !== 'orbit') this.setMode('orbit')
        this._emit('escape')
        break
    }
  }

  _onCanvasClick(e) {
    if (this.mode !== 'orbit') return
    const rect = this.canvas.getBoundingClientRect()
    const x = ((e.clientX - rect.left) / rect.width) * 2 - 1
    const y = -((e.clientY - rect.top) / rect.height) * 2 + 1
    const raycaster = new THREE.Raycaster()
    raycaster.setFromCamera({ x, y }, this.activeCamera)
    const hits = raycaster.intersectObjects(this.stageRoot.children, true)
    if (hits.length > 0) {
      let obj = hits[0].object
      while (obj.parent && obj.parent !== this.stageRoot) obj = obj.parent
      this._emit('select', obj)
    }
  }

  setMode(mode) {
    if (this.mode === mode) return
    const oldCam = this.activeCamera
    this.mode = mode

    if (mode === 'orbit') {
      this.activeCamera = this.orbitCam
      this.orbit.enabled = true
      if (document.pointerLockElement) document.exitPointerLock()
      if (oldCam && oldCam !== this.orbitCam) {
        this.orbitCam.position.copy(oldCam.position)
        this.orbitCam.rotation.copy(oldCam.rotation)
        // Adjust orbit target to be a bit in front of the camera
        const fwd = new THREE.Vector3(0, 0, -1).applyQuaternion(oldCam.quaternion)
        this.orbit.target.copy(oldCam.position).addScaledVector(fwd, 20)
        this.orbit.update()
      }
    } else if (mode === 'fly') {
      this.activeCamera = this.flyCam
      this.orbit.enabled = false
      if (oldCam && oldCam !== this.flyCam) {
        this.flyCam.position.copy(oldCam.position)
        this.flyCam.rotation.copy(oldCam.rotation)
      }
      if (document.pointerLockElement !== this.canvas) {
        this.canvas.requestPointerLock()
      }
    } else if (mode === 'original') {
      this.activeCamera = this.originalCam
      this.orbit.enabled = false
      if (document.pointerLockElement) document.exitPointerLock()
      this._applyOriginalCam(this._camIndex)
    }

    if (this.transformControl) {
      this.transformControl.camera = this.activeCamera
      if (mode !== 'orbit') this.transformControl.detach()
    }

    this._resize()
    this._emit('modeChange', mode)
  }

  setOriginalCams(cams, roomGroup) {
    this._currentRoomCams = cams || []
    this._currentRoomGroup = roomGroup
    this._camIndex = 0
  }

  _applyOriginalCam(index) {
    const cams = this._currentRoomCams
    if (!cams.length) return
    const cam = cams[Math.min(index, cams.length - 1)]
    if (!cam) return

    const M = v => v / WORLD_SCALE
    const pos = new THREE.Vector3(M(cam.pos[0]), -M(cam.pos[1]), M(cam.pos[2]))
    const tgt = new THREE.Vector3(M(cam.target[0]), -M(cam.target[1]), M(cam.target[2]))

    if (this._currentRoomGroup) {
      this._currentRoomGroup.localToWorld(pos)
      this._currentRoomGroup.localToWorld(tgt)
    }

    this.originalCam.position.copy(pos)
    this.originalCam.lookAt(tgt)
    this.originalCam.fov = this._originalCamFov
    this.originalCam.updateProjectionMatrix()

    this._emit('camChange', { index, total: cams.length, cam })
  }

  prevOriginalCam() {
    if (!this._currentRoomCams.length) return
    this._camIndex = (this._camIndex - 1 + this._currentRoomCams.length) % this._currentRoomCams.length
    this._applyOriginalCam(this._camIndex)
  }

  nextOriginalCam() {
    if (!this._currentRoomCams.length) return
    this._camIndex = (this._camIndex + 1) % this._currentRoomCams.length
    this._applyOriginalCam(this._camIndex)
  }

  setFov(deg) {
    this._originalCamFov = deg
    this.orbitCam.fov = deg
    this.orbitCam.updateProjectionMatrix()
    this.flyCam.fov = deg + 10
    this.flyCam.updateProjectionMatrix()
    if (this.mode === 'original') {
      this.originalCam.fov = deg
      this.originalCam.updateProjectionMatrix()
    }
  }

  focusOn(object) {
    const box = new THREE.Box3().setFromObject(object)
    if (box.isEmpty()) return
    const center = box.getCenter(new THREE.Vector3())
    const size = box.getSize(new THREE.Vector3())
    const maxDim = Math.max(size.x, size.y, size.z)
    const dist = maxDim * 1.5 + 5

    this.orbit.target.copy(center)
    this.orbitCam.position.set(
      center.x + dist * 0.4,
      center.y + dist * 0.5,
      center.z + dist
    )
    this.orbit.update()
  }

  focusStage() {
    if (!this.stageRoot.children.length) return
    const box = new THREE.Box3().setFromObject(this.stageRoot)
    const center = box.getCenter(new THREE.Vector3())
    const size = box.getSize(new THREE.Vector3())
    const maxDim = Math.max(size.x, size.z)
    const dist = maxDim * 0.8

    this.orbit.target.copy(center)
    this.orbitCam.position.set(center.x, center.y + dist * 0.6, center.z + dist * 0.8)
    this.orbit.update()
  }

  _resize() {
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    if (!w || !h) return
    this.renderer.setSize(w, h, false)

    if (this.mode === 'original') {
      // Força 4:3 e letterbox
      const targetAspect = 4 / 3
      const windowAspect = w / h
      let vw = w, vh = h
      if (windowAspect > targetAspect) {
        vw = h * targetAspect
      } else {
        vh = w / targetAspect
      }
      const vx = (w - vw) / 2
      const vy = (h - vh) / 2

      this.renderer.setViewport(vx, vy, vw, vh)
      this.renderer.setScissor(vx, vy, vw, vh)
      this.renderer.setScissorTest(true)
      
      this.originalCam.aspect = targetAspect
      this.originalCam.updateProjectionMatrix()
    } else {
      this.renderer.setViewport(0, 0, w, h)
      this.renderer.setScissorTest(false)
      const aspect = w / h
      this.orbitCam.aspect = aspect
      this.orbitCam.updateProjectionMatrix()
      this.flyCam.aspect = aspect
      this.flyCam.updateProjectionMatrix()
    }
  }

  _clock = new THREE.Clock()

  _loop() {
    requestAnimationFrame(() => this._loop())
    const dt = this._clock.getDelta()

    if (this.mode === 'orbit') {
      if (this._isRightClicking) {
        this._updateFly(this.orbitCam, dt)
      } else {
        this.orbit.update()
      }
    } else if (this.mode === 'fly') {
      this._updateFly(this.flyCam, dt)
    }

    this.renderer.render(this.scene, this.activeCamera)
  }

  _updateFly(camera, dt) {
    const speed = this._flySpeed * (this._keys['ShiftLeft'] || this._keys['ShiftRight'] ? 5 : 1)
    const dir = new THREE.Vector3()
    const right = new THREE.Vector3()
    const up = new THREE.Vector3(0, 1, 0)

    camera.getWorldDirection(dir)
    right.crossVectors(dir, up).normalize()

    const move = new THREE.Vector3()

    if (this._keys['KeyW']) move.addScaledVector(dir, speed * dt)
    if (this._keys['KeyS']) move.addScaledVector(dir, -speed * dt)
    if (this._keys['KeyA']) move.addScaledVector(right, -speed * dt)
    if (this._keys['KeyD']) move.addScaledVector(right, speed * dt)
    if (this._keys['KeyQ']) move.y -= speed * dt
    if (this._keys['KeyE']) move.y += speed * dt

    if (move.lengthSq() > 0) {
      camera.position.add(move)
      if (camera === this.orbitCam) {
        this.orbit.target.add(move)
      }
    }
  }

  // Event emitter simples
  on(event, fn) {
    if (!this._listeners[event]) this._listeners[event] = []
    this._listeners[event].push(fn)
  }
  _emit(event, data) {
    ;(this._listeners[event] || []).forEach(fn => fn(data))
  }

  clear() {
    while (this.stageRoot.children.length) {
      this.stageRoot.remove(this.stageRoot.children[0])
    }
    while (this.projectionRoot.children.length) {
      this.projectionRoot.remove(this.projectionRoot.children[0])
    }
  }
}
