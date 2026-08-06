/**
 * projection.js — veste a sala com os backgrounds pré-renderizados.
 *
 * Técnica: PROJECTIVE TEXTURE MAPPING MULTI-CÂMERA. Cada câmera original do RE3
 * (posição + alvo, do bloco RID) vira um projetor: no shader, o vértice passa
 * pela matriz view-projection dela e, dividindo por w, cai direto na UV da foto.
 * É um slide projetado numa maquete — parede fora de lugar aparece torta na hora.
 *
 * Por que TODAS as câmeras de uma vez: uma câmera só enxerga uma fatia do cômodo,
 * então projetar só a dela deixa quase tudo cinza. Com todos os projetores ativos,
 * cada fragmento escolhe o que melhor o vê:
 *
 *     score = dot(normal, direção até o projetor) / distância²
 *
 * ou seja, ganha quem olha a superfície mais de frente e mais de perto. Como
 * WebGL não deixa indexar array de sampler com índice variável, o laço é
 * DESENROLADO ao gerar o shader — um bloco por câmera, até MAX_PROJECTORS.
 *
 * LIMITE: não há teste de oclusão. A foto atravessa a geometria e pinta também o
 * que estaria escondido atrás de uma parede; o descarte por `dot <= 0` (face de
 * costas) atenua, mas resolver de verdade pede um shadow map por projetor.
 * O teto quase nunca tem cobertura: as câmeras do RE3 olham para baixo.
 *
 * FOV: não sabemos o valor por câmera. O campo `attr` do RID tem 24 valores
 * distintos e provavelmente o codifica, mas não foi decodificado. A v1 usa 55° e
 * o script Blender do projeto usa 58,5° — por isso o FOV é ajustável na UI.
 */
import * as THREE from 'three'
import { WORLD_SCALE } from './store.js'

const M = (u) => u / WORLD_SCALE
export const DEFAULT_FOV = 55
const ASPECT = 320 / 240          // proporção original do PS1
const MAX_PROJECTORS = 12         // teto de uniforms; salas com mais usam as melhores

const VERT = /* glsl */ `
  varying vec3 vWorldPos;
  varying vec3 vWorldNormal;
  void main() {
    vec4 world = modelMatrix * vec4(position, 1.0);
    vWorldPos = world.xyz;
    vWorldNormal = normalize(mat3(modelMatrix) * normal);
    gl_Position = projectionMatrix * viewMatrix * world;
  }
`

/** Gera o fragment shader com N blocos desenrolados (um por câmera). */
function makeFragment(n) {
  const samplers = Array.from({ length: n }, (_, i) => `uniform sampler2D map${i};`).join('\n')

  const blocks = Array.from({ length: n }, (_, i) => `
    {
      vec4 clip = projMat[${i}] * vec4(vWorldPos, 1.0);
      if (clip.w > 0.0) {
        vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
        if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
          vec3 delta = projPos[${i}] - vWorldPos;
          float dist2 = max(dot(delta, delta), 0.0001);
          float facing = dot(normal, normalize(delta));
          if (facing > 0.02) {
            float score = facing / dist2;
            if (score > bestScore) {
              bestScore = score;
              bestColor = texture2D(map${i}, uv).rgb;
            }
          }
        }
      }
    }`).join('\n')

  return /* glsl */ `
    ${samplers}
    uniform mat4 projMat[${n}];
    uniform vec3 projPos[${n}];
    uniform vec3 fallback;
    uniform float opacity;
    varying vec3 vWorldPos;
    varying vec3 vWorldNormal;

    void main() {
      // gl_FrontFacing: a casca é vista por dentro (BackSide), então a normal
      // precisa ser invertida para apontar para o observador.
      vec3 normal = normalize(vWorldNormal) * (gl_FrontFacing ? 1.0 : -1.0);

      float bestScore = 0.0;
      vec3 bestColor = fallback;

      ${blocks}

      gl_FragColor = vec4(bestColor, opacity);
      #include <colorspace_fragment>
    }
  `
}

export class CameraProjection {
  constructor(scene, deps) {
    this.scene = scene
    this.deps = deps
    this.active = null
    this.fov = DEFAULT_FOV
    this.showBackdrop = false      // com multi-câmera, o gabarito atrapalha mais que ajuda
    this.showProjection = true
    this.isolate = true
    this.lockCamera = false        // solto por padrão: dá para andar pela sala
    this.allCameras = true         // projetar todas as câmeras, não só a atual
    this.loader = new THREE.TextureLoader()
    this.textures = new Map()
  }

  get isActive() { return Boolean(this.active) }

  async loadTexture(url) {
    if (this.textures.has(url)) return this.textures.get(url)
    const tex = await this.loader.loadAsync(url)
    tex.colorSpace = THREE.SRGBColorSpace
    tex.minFilter = THREE.LinearFilter
    tex.generateMipmaps = false
    this.textures.set(url, tex)
    return tex
  }

  /** Câmera three equivalente à original, já no espaço do mundo. */
  makeProjector(roomGroup, camData) {
    const cam = new THREE.PerspectiveCamera(this.fov, ASPECT, 0.05, 2000)
    cam.position.set(M(camData.pos[0]), M(-camData.pos[1]), M(camData.pos[2]))
    const target = new THREE.Vector3(
      M(camData.target[0]), M(-camData.target[1]), M(camData.target[2])
    )
    roomGroup.updateMatrixWorld(true)
    roomGroup.add(cam)
    cam.lookAt(roomGroup.localToWorld(target.clone()))   // lookAt é em WORLD
    cam.updateMatrixWorld(true)
    cam.updateProjectionMatrix()
    return { cam, targetLocal: target }
  }

  makeBackdrop(roomGroup, camData, texture, targetLocal) {
    const from = new THREE.Vector3(M(camData.pos[0]), M(-camData.pos[1]), M(camData.pos[2]))
    const dist = from.distanceTo(targetLocal)
    if (dist < 0.01) return null

    const h = 2 * dist * Math.tan(THREE.MathUtils.degToRad(this.fov) / 2)
    const plane = new THREE.Mesh(
      new THREE.PlaneGeometry(h * ASPECT, h),
      new THREE.MeshBasicMaterial({
        map: texture, transparent: true, opacity: 0.85,
        depthWrite: false, side: THREE.DoubleSide,
      })
    )
    plane.name = '__backdrop'
    plane.position.copy(targetLocal)
    plane.renderOrder = -1
    roomGroup.add(plane)
    plane.lookAt(roomGroup.localToWorld(from.clone()))
    return plane
  }

  /** Superfícies que recebem a foto: casca, paredes, móveis e piso. */
  applyMaterial(roomGroup, material) {
    const saved = []
    roomGroup.traverse((o) => {
      if (!o.isMesh || o.name === '__backdrop') return
      const kind = o.userData?.kind
      if (!['shell', 'wall', 'prop', 'floor'].includes(kind)) return
      saved.push([o, o.material])
      o.material = material
    })
    return saved
  }

  async enter(roomId, camIndex = 0) {
    const { store, getRoomGroup, viewport } = this.deps
    const src = store.rooms[roomId]
    const group = getRoomGroup(roomId)
    if (!src) return null

    const cams = (src.cameras || []).filter((c) => c.hd)
    if (!group || !cams.length) return null
    camIndex = ((camIndex % cams.length) + cams.length) % cams.length

    this.exit({ keepIsolation: true })

    // Quais câmeras projetam: todas (limitadas) ou só a atual.
    const chosen = this.allCameras ? cams.slice(0, MAX_PROJECTORS) : [cams[camIndex]]
    // em paralelo: são até 12 imagens de ~400 KB, sequencial trava a entrada
    const loaded = (await Promise.all(chosen.map(async (c) => {
      try {
        const texture = await this.loadTexture(`/data/STAGE${store.stage}/${roomId}/${c.hd}`)
        return { cam: c, texture }
      } catch {
        return null      // sem HD para essa câmera: segue com as outras
      }
    }))).filter(Boolean)
    if (!loaded.length) return null

    const projectors = loaded.map(({ cam }) => this.makeProjector(group, cam))
    const uniforms = {
      fallback: { value: new THREE.Color(0x3a4050) },
      opacity: { value: 1.0 },
      projMat: {
        value: projectors.map((p) =>
          new THREE.Matrix4().multiplyMatrices(
            p.cam.projectionMatrix, p.cam.matrixWorldInverse
          )
        ),
      },
      projPos: {
        value: projectors.map((p) => p.cam.getWorldPosition(new THREE.Vector3())),
      },
    }
    loaded.forEach((l, i) => { uniforms[`map${i}`] = { value: l.texture } })

    const material = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: makeFragment(loaded.length),
      side: THREE.DoubleSide,
      uniforms,
    })

    const saved = this.showProjection ? this.applyMaterial(group, material) : []

    // A câmera "atual" (para o enquadramento e o backdrop) é a pedida.
    const currentIdx = this.allCameras
      ? Math.min(camIndex, loaded.length - 1)
      : 0
    const current = projectors[currentIdx]
    const currentCam = loaded[currentIdx]

    const backdrop = this.showBackdrop
      ? this.makeBackdrop(group, currentCam.cam, currentCam.texture, current.targetLocal)
      : null

    if (this.isolate) this.setIsolation(roomId, true)

    const worldPos = current.cam.getWorldPosition(new THREE.Vector3())
    const worldTarget = group.localToWorld(current.targetLocal.clone())
    viewport.camera.position.copy(worldPos)
    viewport.camera.fov = this.fov
    viewport.camera.updateProjectionMatrix()
    viewport.controls.target.copy(worldTarget)
    viewport.controls.update()
    viewport.controls.enabled = !this.lockCamera

    this.active = {
      roomId, camIndex, material, backdrop, saved, group,
      projectors: projectors.map((p) => p.cam),
      nProjectors: loaded.length,
      totalCameras: cams.length,
    }
    return {
      roomId, camIndex, total: cams.length,
      projectors: loaded.length,
      floorY: src.bounds?.y_floor ?? 0,
    }
  }

  async refresh() {
    if (!this.active) return null
    const { roomId, camIndex } = this.active
    return this.enter(roomId, camIndex)
  }

  async step(delta) {
    if (!this.active) return null
    const { roomId, camIndex } = this.active
    return this.enter(roomId, camIndex + delta)
  }

  setIsolation(roomId, on) {
    const { store, getRoomGroup, onIsolation } = this.deps
    for (const id of store.ids) {
      const g = getRoomGroup(id)
      if (g) g.visible = !on || id === roomId
    }
    onIsolation?.(on ? roomId : null)
  }

  exit({ keepIsolation = false } = {}) {
    if (!this.active) {
      if (!keepIsolation) this.setIsolation(null, false)
      return
    }
    const { material, backdrop, projectors, saved, group } = this.active
    for (const [mesh, mat] of saved) mesh.material = mat
    if (backdrop) {
      group.remove(backdrop)
      backdrop.geometry.dispose()
      backdrop.material.dispose()
    }
    for (const p of projectors) group.remove(p)
    material.dispose()
    this.active = null
    this.deps.viewport.controls.enabled = true
    if (!keepIsolation) this.setIsolation(null, false)
  }
}
