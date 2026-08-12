/**
 * projection.js — Projective texture mapping dos backgrounds HD nas paredes.
 * Multi-câmera: cada fragmento escolhe a câmera com melhor score.
 * Baseado na técnica do editor Three.js existente (v2/editor/src/projection.js).
 */
import * as THREE from 'three'

const WORLD_SCALE = 808
const M = v => v / WORLD_SCALE
const MAX_CAMS = 12

let _textureCache = {}

/**
 * Limpa o cache de texturas (ao trocar de sala).
 */
export function clearProjectionCache() {
  for (const t of Object.values(_textureCache)) t.dispose()
  _textureCache = {}
}

/**
 * Carrega as texturas de background para uma sala.
 * @param {Array} cameras - câmeras com bg_url
 * @returns {Promise<Map<number, THREE.Texture>>}
 */
export async function loadBackgrounds(cameras) {
  const loader = new THREE.TextureLoader()
  const texMap = new Map()

  await Promise.all(cameras.map(cam => {
    if (!cam.bg_url) return Promise.resolve()
    const url = cam.bg_url
    if (_textureCache[url]) {
      texMap.set(cam.index, _textureCache[url])
      return Promise.resolve()
    }
    return new Promise(resolve => {
      loader.load(url, tex => {
        tex.colorSpace = THREE.SRGBColorSpace
        _textureCache[url] = tex
        texMap.set(cam.index, tex)
        resolve()
      }, undefined, () => resolve())
    })
  }))

  return texMap
}

/**
 * Aplica projeção multi-câmera aos meshes do shellGroup.
 * Gera um ShaderMaterial que escolhe o melhor projetor por fragmento.
 *
 * @param {THREE.Group} shellGroup - grupo com os meshes da casca da sala
 * @param {Array} cameras          - câmeras com pos, target, fov
 * @param {Map} texMap             - mapa camIndex → THREE.Texture
 * @param {number} fovDeg          - FOV em graus
 * @param {object} opts
 * @param {boolean} opts.allCams   - usar todas as câmeras ou só a ativa
 * @param {number}  opts.activeCam - índice da câmera ativa (se !allCams)
 */
export function applyProjection(shellGroup, cameras, texMap, fovDeg = 55, opts = {}) {
  const activeCams = opts.allCams !== false
    ? cameras
    : cameras.slice(opts.activeCam ?? 0, (opts.activeCam ?? 0) + 1)

  const usedCams = activeCams.slice(0, MAX_CAMS).filter(c => texMap.has(c.index))
  if (!usedCams.length) return

  const nCams = usedCams.length

  const roomGroup = opts.roomGroup

  // Monta arrays de uniforms
  const camPositions = usedCams.map(c => {
    const v = new THREE.Vector3(M(c.pos[0]), -M(c.pos[1]), M(c.pos[2]))
    if (roomGroup) roomGroup.localToWorld(v)
    return v
  })
  
  const camTargets = usedCams.map(c => {
    const v = new THREE.Vector3(M(c.target[0]), -M(c.target[1]), M(c.target[2]))
    if (roomGroup) roomGroup.localToWorld(v)
    return v
  })

  // Matrizes de projeção por câmera
  const projMatrices = usedCams.map((cam, i) => {
    const camObj = new THREE.PerspectiveCamera(fovDeg, 4 / 3, 0.01, 2000)
    camObj.position.copy(camPositions[i])
    camObj.lookAt(camTargets[i])
    camObj.updateMatrixWorld()
    camObj.updateProjectionMatrix()
    const vp = new THREE.Matrix4()
    vp.multiplyMatrices(camObj.projectionMatrix, camObj.matrixWorldInverse)
    return vp
  })

  // Samplers
  const samplers = usedCams.map(c => texMap.get(c.index))

  // Gera GLSL dinâmico (desenrola laço por câmera)
  const uniformsDef = Array.from({ length: nCams }, (_, i) =>
    `uniform sampler2D uTex${i};\nuniform mat4 uVP${i};\nuniform vec3 uCamPos${i};`
  ).join('\n')

  const scoreBlock = Array.from({ length: nCams }, (_, i) => `
  {
    vec4 clip = uVP${i} * vec4(vWorldPos, 1.0);
    vec3 ndc  = clip.xyz / clip.w;
    if (clip.w > 0.0 && abs(ndc.x) < 1.0 && abs(ndc.y) < 1.0) {
      vec3  toP  = normalize(uCamPos${i} - vWorldPos);
      float score = dot(vNorm, toP) / (distance(uCamPos${i}, vWorldPos) + 0.001);
      if (score > bestScore) {
        bestScore = score;
        bestUV    = ndc.xy * 0.5 + 0.5;
        bestTex   = ${i};
      }
    }
  }`).join('\n')

  const sampleBlock = Array.from({ length: nCams }, (_, i) =>
    `if (bestTex == ${i}) color = texture2D(uTex${i}, bestUV);`
  ).join('\nelse ')

  const vertexShader = `
    varying vec3 vWorldPos;
    varying vec3 vNorm;
    void main() {
      vec4 wp = modelMatrix * vec4(position, 1.0);
      vWorldPos = wp.xyz;
      vNorm = normalize(normalMatrix * normal);
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `

  const fragmentShader = `
    precision highp float;
    varying vec3 vWorldPos;
    varying vec3 vNorm;
    ${uniformsDef}
    void main() {
      float bestScore = -1.0;
      vec2  bestUV    = vec2(0.0);
      int   bestTex   = -1;
      ${scoreBlock}
      vec4 color = vec4(0.12, 0.14, 0.18, 1.0);
      if (bestTex >= 0) { ${sampleBlock} }
      gl_FragColor = color;
    }
  `

  // Monta uniforms
  const uniforms = {}
  usedCams.forEach((_, i) => {
    uniforms[`uTex${i}`]    = { value: samplers[i] }
    uniforms[`uVP${i}`]     = { value: projMatrices[i] }
    uniforms[`uCamPos${i}`] = { value: camPositions[i] }
  })

  const shaderMat = new THREE.ShaderMaterial({
    uniforms,
    vertexShader,
    fragmentShader,
    side: THREE.BackSide,
  })

  shellGroup.traverse(child => {
    if (child.isMesh && child.userData.kind === 'shell') {
      child.material = shaderMat
    }
  })
}

/**
 * Restaura o material padrão da casca (sem projeção).
 */
export function removeProjection(shellGroup) {
  const defaultMat = new THREE.MeshLambertMaterial({
    color: 0x8a90a0, side: THREE.DoubleSide,
  })
  shellGroup.traverse(child => {
    if (child.isMesh && child.userData.kind === 'shell') {
      child.material = defaultMat
    }
  })
}

/**
 * Cria um plano de background (foto ao fundo do viewport).
 */
export function createBgPlane(cam, texture, fovDeg, roomGroup) {
  if (!texture) return null
  const dist = 60
  const h = dist * Math.tan(THREE.MathUtils.degToRad(fovDeg / 2)) * 2
  const w = h * (4 / 3)

  const geo = new THREE.PlaneGeometry(w, h)
  const mat = new THREE.MeshBasicMaterial({ map: texture, depthWrite: false, side: THREE.FrontSide })
  const plane = new THREE.Mesh(geo, mat)

  const pos = new THREE.Vector3(M(cam.pos[0]), -M(cam.pos[1]), M(cam.pos[2]))
  const tgt = new THREE.Vector3(M(cam.target[0]), -M(cam.target[1]), M(cam.target[2]))
  
  if (roomGroup) {
    roomGroup.localToWorld(pos)
    roomGroup.localToWorld(tgt)
  }

  const dir = tgt.clone().sub(pos).normalize()

  plane.position.copy(pos).addScaledVector(dir, dist)
  plane.lookAt(pos)
  plane.name = 'bgPlane'
  return plane
}
