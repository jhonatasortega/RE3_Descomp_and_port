/**
 * gizmo.js — indicador de orientação no canto do viewport, como o do Blender.
 *
 * Desenha os três eixos projetados pela rotação atual da câmera. Sem isso não
 * há como saber para onde se está olhando num mapa onde todas as salas são
 * caixas cinzas parecidas.
 *
 * Convenção deste projeto (mundo em metros, Y para cima):
 *   +X  leste   ·  +Z  sul  ·  +Y  cima
 * Os rótulos cardeais vêm daí: o RE3 não tem norte, mas fixar um dá referência
 * estável para conversar sobre o mapa ("a porta na face oeste da R100").
 */
import * as THREE from 'three'

const SVG = 'http://www.w3.org/2000/svg'
const R = 34          // raio do gizmo em unidades do viewBox

const AXES = [
  { key: 'X', dir: new THREE.Vector3(1, 0, 0), color: 'var(--axis-x)', pos: 'L', neg: 'O' },
  { key: 'Y', dir: new THREE.Vector3(0, 1, 0), color: 'var(--axis-y)', pos: '↑', neg: '↓' },
  { key: 'Z', dir: new THREE.Vector3(0, 0, 1), color: 'var(--axis-z)', pos: 'S', neg: 'N' },
]

export class AxisGizmo {
  constructor(svg, camera) {
    this.svg = svg
    this.camera = camera
    this.parts = []

    for (const axis of AXES) {
      for (const sign of [1, -1]) {
        const line = document.createElementNS(SVG, 'line')
        line.setAttribute('stroke', axis.color)
        line.setAttribute('stroke-width', sign > 0 ? '2' : '1.2')
        line.setAttribute('stroke-linecap', 'round')
        line.setAttribute('x1', '0')
        line.setAttribute('y1', '0')

        const dot = document.createElementNS(SVG, 'circle')
        dot.setAttribute('r', sign > 0 ? '8' : '5.5')
        dot.setAttribute('fill', sign > 0 ? axis.color : 'transparent')
        dot.setAttribute('stroke', axis.color)
        dot.setAttribute('stroke-width', '1.2')

        const label = document.createElementNS(SVG, 'text')
        label.setAttribute('text-anchor', 'middle')
        label.setAttribute('dominant-baseline', 'central')
        label.setAttribute('fill', sign > 0 ? '#101010' : axis.color)
        label.textContent = sign > 0 ? axis.pos : axis.neg

        svg.append(line, dot, label)
        this.parts.push({ axis, sign, line, dot, label })
      }
    }
  }

  update() {
    const q = this.camera.quaternion.clone().invert()
    const v = new THREE.Vector3()

    // ordena por profundidade: o que aponta para trás é desenhado primeiro
    const drawn = this.parts.map((p) => {
      v.copy(p.axis.dir).multiplyScalar(p.sign).applyQuaternion(q)
      return { ...p, x: v.x * R, y: -v.y * R, z: v.z }
    }).sort((a, b) => a.z - b.z)

    for (const p of drawn) {
      const front = p.z > -0.05
      p.line.setAttribute('x2', p.x.toFixed(1))
      p.line.setAttribute('y2', p.y.toFixed(1))
      p.line.setAttribute('opacity', front ? '0.95' : '0.35')
      p.dot.setAttribute('cx', p.x.toFixed(1))
      p.dot.setAttribute('cy', p.y.toFixed(1))
      p.dot.setAttribute('opacity', front ? '1' : '0.45')
      p.label.setAttribute('x', p.x.toFixed(1))
      p.label.setAttribute('y', p.y.toFixed(1))
      p.label.setAttribute('opacity', front && p.sign > 0 ? '1' : '0.55')
      // reinsere na ordem de profundidade
      this.svg.append(p.line, p.dot, p.label)
    }
  }
}

/**
 * Eixos cardeais no chão do mundo: duas linhas coloridas cruzando a origem,
 * mesma convenção do gizmo. Dão orientação quando se está longe das salas.
 */
export function cardinalAxes(size = 400) {
  const g = new THREE.Group()
  g.name = 'cardinals'
  const mk = (from, to, color) => {
    const geo = new THREE.BufferGeometry().setFromPoints([from, to])
    return new THREE.Line(geo, new THREE.LineBasicMaterial({
      color, transparent: true, opacity: 0.55, depthWrite: false,
    }))
  }
  g.add(mk(new THREE.Vector3(-size, 0, 0), new THREE.Vector3(size, 0, 0), 0xe05c5c))
  g.add(mk(new THREE.Vector3(0, 0, -size), new THREE.Vector3(0, 0, size), 0x5b8ede))
  return g
}
