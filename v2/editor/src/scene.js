/**
 * scene.js — three.js: cena, iluminacao de trabalho, camera e navegacao.
 *
 * Dois modos de camera compartilhando a mesma PerspectiveCamera:
 *   orbit  — inspecionar o stage de cima (OrbitControls)
 *   fly    — WASD/QE para andar dentro do cenario (validar navegabilidade)
 */
import * as THREE from 'three'
import { OrbitControls } from 'three/addons/controls/OrbitControls.js'
import { AxisGizmo, cardinalAxes } from './gizmo.js'

export class Viewport {
  constructor(canvas) {
    this.canvas = canvas
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true })
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2))

    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(0x0e1016)
    this.scene.fog = new THREE.Fog(0x0e1016, 80, 400)

    this.camera = new THREE.PerspectiveCamera(55, 1, 0.05, 2000)
    this.camera.position.set(40, 60, 60)

    this.controls = new OrbitControls(this.camera, canvas)
    this.controls.enableDamping = true
    this.controls.dampingFactor = 0.08
    this.controls.maxPolarAngle = Math.PI * 0.95
    this.controls.mouseButtons = {
      LEFT: THREE.MOUSE.ROTATE,
      MIDDLE: THREE.MOUSE.DOLLY,
      RIGHT: THREE.MOUSE.PAN,
    }

    // Luz de TRABALHO (nao e a iluminacao do jogo — o RE3 se passa a noite).
    this.scene.add(new THREE.HemisphereLight(0xa8c0ff, 0x30281f, 1.5))
    const key = new THREE.DirectionalLight(0xffffff, 1.1)
    key.position.set(60, 120, 40)
    this.scene.add(key)

    this.grid = new THREE.GridHelper(600, 120, 0x4a4a4a, 0x333333)
    this.grid.material.transparent = true
    this.grid.material.opacity = 0.5
    this.scene.add(this.grid)

    this.cardinals = cardinalAxes(400)
    this.scene.add(this.cardinals)

    const svg = document.getElementById('gizmo')
    this.gizmo = svg ? new AxisGizmo(svg, this.camera) : null

    this.root = new THREE.Group()
    this.root.name = 'stageRoot'
    this.scene.add(this.root)

    this.raycaster = new THREE.Raycaster()
    this.keys = new Set()
    this.flySpeed = 18
    this.clock = new THREE.Clock()

    // modo andar: primeira pessoa travada na altura dos olhos
    this.walk = null            // { eyeY, yaw, pitch }
    this.walkSpeed = 4.5        // m/s — perto do passo da Jill (2,8 andando)
    this.eyeHeight = 1.6
    this.canvas.addEventListener('click', () => {
      if (this.walk && document.pointerLockElement !== this.canvas) {
        this.canvas.requestPointerLock()
      }
    })
    document.addEventListener('mousemove', (e) => {
      if (!this.walk || document.pointerLockElement !== this.canvas) return
      const s = 0.0022
      this.walk.yaw -= e.movementX * s
      this.walk.pitch = THREE.MathUtils.clamp(
        this.walk.pitch - e.movementY * s, -Math.PI / 2 + 0.01, Math.PI / 2 - 0.01
      )
    })

    addEventListener('resize', () => this.resize())
    addEventListener('keydown', (e) => {
      if (e.target.matches('input, select, textarea')) return
      this.keys.add(e.code)
    })
    addEventListener('keyup', (e) => this.keys.delete(e.code))
    addEventListener('blur', () => this.keys.clear())

    this.resize()
  }

  resize() {
    const w = this.canvas.clientWidth || 1
    const h = this.canvas.clientHeight || 1
    this.renderer.setSize(w, h, false)
    this.camera.aspect = w / h
    this.camera.updateProjectionMatrix()
  }

  /**
   * Entra/sai do modo andar. `eyeY` é a altura do olho em metros no mundo
   * (piso da sala + 1,6 m) — é o que faz a sala ter escala humana.
   */
  setWalk(on, eyeY = 0) {
    if (!on) {
      this.walk = null
      this.controls.enabled = true
      if (document.pointerLockElement === this.canvas) document.exitPointerLock()
      return
    }
    // preserva a direção atual do olhar ao entrar
    const dir = new THREE.Vector3()
    this.camera.getWorldDirection(dir)
    this.walk = {
      eyeY,
      yaw: Math.atan2(-dir.x, -dir.z),
      pitch: Math.asin(THREE.MathUtils.clamp(dir.y, -1, 1)),
    }
    this.camera.position.y = eyeY
    this.controls.enabled = false
    this.canvas.requestPointerLock()
  }

  /** Passo em primeira pessoa: anda no plano, altura do olho travada. */
  step(dt) {
    const w = this.walk
    if (!w) return
    const cam = this.camera

    const euler = new THREE.Euler(w.pitch, w.yaw, 0, 'YXZ')
    cam.quaternion.setFromEuler(euler)

    const k = this.keys
    const fwd = new THREE.Vector3(-Math.sin(w.yaw), 0, -Math.cos(w.yaw))
    const right = new THREE.Vector3(Math.cos(w.yaw), 0, -Math.sin(w.yaw))
    const move = new THREE.Vector3()
    if (k.has('KeyW')) move.add(fwd)
    if (k.has('KeyS')) move.sub(fwd)
    if (k.has('KeyD')) move.add(right)
    if (k.has('KeyA')) move.sub(right)
    if (k.has('KeyE')) w.eyeY += 2 * dt
    if (k.has('KeyQ')) w.eyeY -= 2 * dt

    if (move.lengthSq() > 0) {
      move.normalize().multiplyScalar(this.walkSpeed * (k.has('ShiftLeft') ? 2.5 : 1) * dt)
      cam.position.add(move)
    }
    cam.position.y = w.eyeY
  }

  /** Voo WASD relativo a camera; QE sobe/desce no eixo do mundo. */
  fly(dt) {
    const k = this.keys
    if (!k.size) return
    const dir = new THREE.Vector3()
    const fwd = new THREE.Vector3()
    this.camera.getWorldDirection(fwd)
    const right = new THREE.Vector3().crossVectors(fwd, this.camera.up).normalize()

    if (k.has('KeyW')) dir.add(fwd)
    if (k.has('KeyS')) dir.sub(fwd)
    if (k.has('KeyD')) dir.add(right)
    if (k.has('KeyA')) dir.sub(right)
    if (k.has('KeyE')) dir.y += 1
    if (k.has('KeyQ')) dir.y -= 1
    if (dir.lengthSq() === 0) return

    const speed = this.flySpeed * (k.has('ShiftLeft') ? 3 : 1) * dt
    dir.normalize().multiplyScalar(speed)
    this.camera.position.add(dir)
    this.controls.target.add(dir)
  }

  /** Enquadra um objeto (sala) mantendo o angulo atual. */
  focus(object3d, pad = 1.7) {
    const box = new THREE.Box3().setFromObject(object3d)
    if (box.isEmpty()) return
    const center = box.getCenter(new THREE.Vector3())
    const radius = Math.max(box.getSize(new THREE.Vector3()).length() / 2, 2)
    const dir = new THREE.Vector3()
      .subVectors(this.camera.position, this.controls.target)
      .normalize()
    if (dir.lengthSq() < 1e-6) dir.set(0.5, 0.8, 0.5).normalize()
    this.controls.target.copy(center)
    this.camera.position.copy(center).addScaledVector(dir, radius * pad)
    this.controls.update()
  }

  /** Objetos sob o cursor, do mais proximo ao mais distante. */
  pick(event) {
    const rect = this.canvas.getBoundingClientRect()
    const ndc = new THREE.Vector2(
      ((event.clientX - rect.left) / rect.width) * 2 - 1,
      -((event.clientY - rect.top) / rect.height) * 2 + 1
    )
    this.raycaster.setFromCamera(ndc, this.camera)
    return this.raycaster.intersectObjects(this.root.children, true)
  }

  /** Ponto no plano horizontal Y=y sob o cursor (para arrastar salas). */
  pointOnPlane(event, y = 0) {
    const rect = this.canvas.getBoundingClientRect()
    const ndc = new THREE.Vector2(
      ((event.clientX - rect.left) / rect.width) * 2 - 1,
      -((event.clientY - rect.top) / rect.height) * 2 + 1
    )
    this.raycaster.setFromCamera(ndc, this.camera)
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -y)
    const hit = new THREE.Vector3()
    return this.raycaster.ray.intersectPlane(plane, hit) ? hit : null
  }

  start(onFrame) {
    const loop = () => {
      requestAnimationFrame(loop)
      const dt = Math.min(this.clock.getDelta(), 0.1)
      if (this.walk) {
        this.step(dt)
      } else {
        this.fly(dt)
        this.controls.update()
      }
      this.gizmo?.update()
      onFrame?.(dt)
      this.renderer.render(this.scene, this.camera)
    }
    loop()
  }
}
