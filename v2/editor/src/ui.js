/**
 * ui.js — painel lateral: seletor de stage, camadas, lista de salas,
 * inspetor (pose + rects + portas) e persistencia.
 *
 * A UI nao toca em three.js diretamente: pede tudo ao main.js pelos callbacks
 * onStageChange / onSelect / onLayersChange / getRoomGroup.
 */
import * as THREE from 'three'
import { WORLD_SCALE } from './store.js'

const $ = (sel) => document.querySelector(sel)
const el = (tag, props = {}, ...kids) => {
  const n = Object.assign(document.createElement(tag), props)
  for (const k of kids) n.append(k)
  return n
}
const m = (u) => (u / WORLD_SCALE).toFixed(1)

export class UI {
  constructor(store) {
    this.store = store
    this.selection = null
    this.labels = new Map()      // id -> div
    this.layers = {
      shell: true, walls: true, props: true, floor: true, sat: false,
      doors: true, links: true, cams: false, labels: true,
      triggers: false, entities: false, lights: false, isolate: false, grid: true,
    }
    // callbacks preenchidos pelo main.js
    this.onStageChange = null
    this.onLayersChange = null
    this.onSelect = null
    this.onEnterCamera = null
    this.onStepCamera = null
    this.onExitCamera = null
    this.onToggleWalk = null
    this.onProjectionOption = null
    this.getProjection = null
    this.camMode = null
    this.labelFilter = null
    this.getRoomGroup = null
    this.getCamera = null
    this.getCanvas = null

    this.labelRoot = el('div', { className: 'label-layer' })
    document.getElementById('stage').append(this.labelRoot)
  }

  async init() {
    const stages = await (await fetch('/api/stages')).json()
    const sel = $('#stageSel')
    for (const s of stages) {
      sel.append(el('option', { value: String(s.stage), textContent: `STAGE${s.stage} (${s.rooms})` }))
    }
    sel.onchange = () => this.onStageChange?.(Number(sel.value))

    for (const [key, id] of Object.entries({
      shell: '#lyShell',
      walls: '#lyWalls', props: '#lyProps', floor: '#lyFloor', sat: '#lySat',
      doors: '#lyDoors', links: '#lyLinks', cams: '#lyCams', labels: '#lyLabels',
      triggers: '#lyTriggers', entities: '#lyEntities', lights: '#lyLights',
      isolate: '#lyIsolate', grid: '#lyGrid',
    })) {
      const box = $(id)
      box.checked = this.layers[key]
      box.onchange = () => { this.layers[key] = box.checked; this.onLayersChange?.() }
      ;(this.layerBoxes ||= {})[key] = box
    }

    $('#roomFilter').oninput = () => this.refreshRoomList()
    $('#saveBtn').onclick = () => this.save()
    $('#resetBtn').onclick = () => {
      if (!this.selection) return
      this.store.resetPose(this.selection)
      this.status(`${this.selection} voltou à pose do solver`)
    }

    this.store.on((evt) => {
      if (evt === 'pose' || evt === 'rect' || evt === 'opening') this.updateSaveButton()
    })

    await this.onStageChange?.(stages[0]?.stage ?? 1)
  }

  afterStageLoad() {
    this.renderQuality()
    this.refreshRoomList()
    this.buildLabels()
    this.updateSaveButton()
    this.setSelection(null)
  }

  // ------------------------------------------------------------- qualidade

  renderQuality() {
    const L = this.store.layout
    const box = $('#quality')
    if (!L) { box.innerHTML = '<span class="dim">sem stage_layout.json</span>'; return }
    const q = L.quality || {}
    const err = q.err_after_relax?.translation_m ?? '?'
    const comps = (L.components || []).map((c) => c.size).join(' + ')
    const susp = (q.suspect_doors || []).length
    const cls = err > 3 ? 'warn' : 'ok'
    box.innerHTML = ''
    const g = el('div', { className: 'rows' })
    const kv = (k, v, cls2) => g.append(
      el('span', { className: 'k', textContent: k }),
      el('span', { className: `v ${cls2 || ''}`, textContent: v })
    )
    kv('modo', `${L.convention?.rot_mode ?? '?'} / ${L.convention?.anchor ?? '?'}`)
    kv('fechamento', `${err} m`, cls)
    kv('componentes', comps)
    kv('sobreposição', `${L.overlap?.pct ?? '?'}%`)
    if (susp) kv('portas suspeitas', String(susp), 'warn')
    box.append(g)
  }

  // ----------------------------------------------------------- lista salas

  refreshRoomList() {
    const q = ($('#roomFilter').value || '').toLowerCase()
    const list = $('#roomList')
    list.innerHTML = ''
    let n = 0
    for (const id of this.store.ids) {
      const r = this.store.rooms[id]
      const text = `${id} ${r.area || ''} ${r.desc || ''}`.toLowerCase()
      if (q && !text.includes(q)) continue
      n++
      const li = el('li', {},
        el('span', { className: 'rid', textContent: id }),
        el('span', { className: 'rdesc', textContent: r.desc || r.area || '' })
      )
      if (id === this.selection) li.classList.add('sel')
      if (this.store.isEdited(id)) li.classList.add('edited')
      li.onclick = (e) => this.onSelect?.(id, e.detail > 1)
      list.append(li)
    }
    $('#roomCount').textContent = `${n}/${this.store.ids.length}`
  }

  // ----------------------------------------------------------- modo câmera

  /** @param {{roomId,camIndex,total}|null} info */
  setCameraMode(info) {
    this.camMode = info
    const section = $('#camModeWrap')
    const body = $('#camModeBody')
    section.hidden = !info
    body.innerHTML = ''
    if (!info) return

    const proj = this.getProjection?.()
    const src = this.store.rooms[info.roomId]
    const cam = src?.cameras?.[info.camIndex]

    body.append(el('div', {},
      el('b', { textContent: `${info.roomId} · câmera ${info.camIndex + 1}/${info.total}` }),
      el('span', {
        className: 'dim',
        textContent: ` · ${info.projectors} projetor(es)`,
      })
    ))

    const nav = el('div', { className: 'btnrow' })
    const prev = el('button', { textContent: '‹' })
    const next = el('button', { textContent: '›' })
    const walk = el('button', { textContent: 'andar (V)' })
    const out = el('button', { textContent: 'sair' })
    prev.onclick = () => this.onStepCamera?.(-1)
    next.onclick = () => this.onStepCamera?.(1)
    walk.onclick = () => this.onToggleWalk?.()
    out.onclick = () => this.onExitCamera?.()
    nav.append(prev, next, walk, out)
    body.append(nav)

    // FOV: não sabemos o valor por câmera (o `attr` do RID provavelmente o
    // codifica, mas não foi decodificado). Ajustar aqui até a foto encaixar é o
    // caminho prático — e o dado para correlacionar com o `attr`.
    const fovRow = el('div', { className: 'rows' })
    const slider = el('input', {
      type: 'range', min: '30', max: '90', step: '0.5',
      value: String(proj?.fov ?? 55), style: 'flex:1',
    })
    const out2 = el('span', { className: 'dim', textContent: `${proj?.fov ?? 55}°` })
    slider.oninput = () => { out2.textContent = `${slider.value}°` }
    slider.onchange = () => this.onProjectionOption?.('fov', Number(slider.value))
    fovRow.append(el('span', { className: 'k', textContent: 'FOV' }),
                  el('span', { className: 'v' }, slider, out2))
    body.append(fovRow)

    const opts = el('div', { className: 'grid2', style: 'margin-top:6px' })
    for (const [key, label] of [
      ['allCameras', 'Todas as câmeras'],
      ['showProjection', 'Projetar na malha'],
      ['showBackdrop', 'Foto de fundo'],
      ['isolate', 'Isolar sala'],
      ['lockCamera', 'Travar na câmera'],
    ]) {
      const cb = el('input', { type: 'checkbox' })
      cb.checked = Boolean(proj?.[key])
      cb.onchange = () => this.onProjectionOption?.(key, cb.checked)
      opts.append(el('label', {}, cb, label))
    }
    body.append(opts)

    if (cam) {
      body.append(el('div', {
        className: 'dim', style: 'margin-top:8px;font-size:11px',
        textContent: `attr=${cam.attr ?? '—'} · ${cam.hd || 'sem HD'}`,
      }))
    }
    body.append(el('div', {
      className: 'dim', style: 'margin-top:6px;font-size:11px',
      textContent: 'A projeção não testa oclusão: pinta também o que estaria escondido.',
    }))
  }

  // -------------------------------------------------------------- inspetor

  setSelection(id) {
    this.selection = id
    this.refreshRoomList()
    this.refreshInspector()
  }

  refreshInspector() {
    const body = $('#inspectorBody')
    const id = this.selection
    if (!id) {
      body.innerHTML = '<span class="dim">Clique numa sala.</span>'
      return
    }
    const src = this.store.rooms[id]
    const pose = this.store.pose(id)
    body.innerHTML = ''

    const b = src.bounds
    body.append(el('div', {},
      el('b', { textContent: id }), ' ',
      el('span', { className: 'dim', textContent: src.area || '' })
    ))
    if (src.desc) body.append(el('div', { className: 'dim', textContent: src.desc }))

    const t = el('div', { className: 'rows' })
    const row = (label, node) => t.append(
      el('span', { className: 'k', textContent: label }),
      el('span', { className: 'v' }, node)
    )

    const num = (value, onChange, step = 10) => {
      const i = el('input', { type: 'number', value: String(Math.round(value)), step: String(step) })
      i.onchange = () => onChange(Number(i.value))
      return i
    }
    row('tx (PS1)', num(pose.tx, (v) => this.store.setPose(id, { tx: v })))
    row('tz (PS1)', num(pose.tz, (v) => this.store.setPose(id, { tz: v })))
    row('rot (°)', num(pose.rot_deg, (v) => this.store.setPose(id, { rot_deg: v }), 90))
    row('origem da pose', el('span', {
      className: pose.source === 'manual' ? 'ok' : 'dim',
      textContent: pose.source,
    }))
    if (b) {
      row('tamanho', el('span', { className: 'dim', textContent: `${m(b.size[0])} × ${m(b.size[1])} m` }))
      row('pé-direito', el('span', {
        className: 'dim', textContent: `${m(Math.abs(b.y_floor - b.y_ceiling))} m`,
      }))
    }
    row('rects', el('span', {
      className: 'dim',
      textContent: `${src.counts.rects_wall ?? 0} paredes + `
        + `${(src.counts.rects_solid ?? 0) - (src.counts.rects_wall ?? 0)} móveis`
        + (src.counts.rects_sentinel ? ` + ${src.counts.rects_sentinel} sentinela` : ''),
    }))
    if (src.counts.cameras) {
      const btn = el('button', { textContent: `entrar (${src.counts.cameras} câm.)` })
      btn.onclick = () => this.onEnterCamera?.(id, 0)
      row('câmeras', btn)
    } else {
      row('câmeras', el('span', { className: 'dim', textContent: '—' }))
    }

    const gp = src.gameplay?.counts || {}
    const gpTxt = ['triggers', 'messages', 'flags', 'items', 'enemies', 'objects']
      .filter((k) => gp[k]).map((k) => `${gp[k]} ${k}`).join(' · ')
    row('gameplay', el('span', { className: 'dim', textContent: gpTxt || '—' }))

    const nl = src.lights?.points?.length || 0
    row('luzes', el('span', {
      className: nl ? '' : 'dim',
      textContent: nl ? `${nl} (${src.lights.confidence})` : `— (${src.lights?.confidence || 'none'})`,
    }))
    body.append(t)

    // portas
    if (src.doors?.length) {
      body.append(el('h3', { className: 'sub', textContent: `Portas (${src.doors.length})` }))
      const ul = el('div', { className: 'rows' })
      for (const d of src.doors) {
        const to = d.to_room || '?'
        const link = el('a', { href: '#', textContent: to, style: 'color:var(--accent2)' })
        link.onclick = (e) => { e.preventDefault(); this.onSelect?.(to, true) }
        ul.append(
          el('span', { className: 'k', textContent: `#${d.i} →` }),
          el('span', { className: 'v' }, link,
            el('span', { className: 'dim', textContent: d.reciprocal ? '' : ' mão-única' }))
        )
      }
      body.append(ul)
    }

    // aberturas (portas/janelas desenhadas a mao)
    const ed = this.store.roomEdits[id]
    body.append(el('h3', { className: 'sub', textContent: `Aberturas (${ed?.openings?.length || 0})` }))
    if (ed?.openings?.length) {
      const ot = el('div', { className: 'rows' })
      ed.openings.forEach((o, i) => {
        const del = el('button', { textContent: '×', title: 'remover' })
        del.onclick = () => this.store.removeOpening(id, i)
        ot.append(
          el('span', { className: 'k', textContent: `${o.kind} @ ${o.wall_rect ?? '—'}` }),
          el('span', { className: 'v' },
            el('span', { className: 'dim', textContent: `${m(o.w)}×${m(o.h)} m ` }), del)
        )
      })
      body.append(ot)
    } else {
      body.append(el('div', { className: 'dim', textContent: 'nenhuma — selecione uma parede para adicionar' }))
    }
  }

  // ---------------------------------------------------------------- labels

  buildLabels() {
    this.labelRoot.innerHTML = ''
    this.labels.clear()
    for (const id of this.store.ids) {
      const d = el('div', { className: 'label3d', textContent: id, style: 'position:absolute' })
      this.labelRoot.append(d)
      this.labels.set(id, d)
    }
  }

  setLabelsVisible(v) {
    this.labelRoot.style.display = v ? '' : 'none'
  }

  /** null = todos; um id = só o rótulo daquela sala (usado ao isolar). */
  setLabelFilter(roomId) {
    this.labelFilter = roomId
  }

  /** Muda uma camada e reflete no checkbox, sem disparar onLayersChange. */
  setLayerSilent(name, on) {
    this.layers[name] = on
    const box = this.layerBoxes?.[name]
    if (box) box.checked = on
  }

  /** Projeta o centro de cada sala na tela — chamado a cada frame. */
  updateLabels() {
    if (!this.layers.labels) return
    const cam = this.getCamera?.()
    const canvas = this.getCanvas?.()
    if (!cam || !canvas) return
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    const v = new THREE.Vector3()
    for (const [id, node] of this.labels) {
      const g = this.getRoomGroup?.(id)
      if (!g || !g.visible || (this.labelFilter && id !== this.labelFilter)) {
        node.style.display = 'none'
        continue
      }
      v.set(0, 0, 0)
      const box = new THREE.Box3().setFromObject(g)
      if (box.isEmpty()) { node.style.display = 'none'; continue }
      box.getCenter(v)
      v.project(cam)
      if (v.z > 1) { node.style.display = 'none'; continue }
      node.style.display = ''
      node.style.left = `${(v.x * 0.5 + 0.5) * w}px`
      node.style.top = `${(-v.y * 0.5 + 0.5) * h}px`
      node.style.opacity = id === this.selection ? '1' : '0.55'
    }
  }

  // ----------------------------------------------------------- persistencia

  updateSaveButton() {
    const btn = $('#saveBtn')
    const n = this.store.dirty.size
    btn.disabled = n === 0
    btn.textContent = n ? `Salvar (${n})` : 'Salvar edições'
  }

  async save() {
    try {
      const wrote = await this.store.save()
      this.status(`salvo: ${wrote.join(', ')}`, 'ok')
    } catch (err) {
      this.status(String(err.message || err), 'warn')
    }
    this.updateSaveButton()
    this.refreshRoomList()
  }

  status(msg, cls = 'dim') {
    const s = $('#status')
    s.className = cls
    s.textContent = msg
  }
}
