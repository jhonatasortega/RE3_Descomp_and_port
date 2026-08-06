/**
 * store.js — dados do stage + edicoes do usuario + persistencia.
 *
 * Tres camadas, nesta ordem de precedencia:
 *   1. room.src.json     dado do jogo (gerado, read-only)
 *   2. stage_layout.json pose calculada pelo solver de portas (gerado, read-only)
 *   3. stage_edits.json / room3d.json   ajuste manual (escrito por aqui)
 *
 * A camada 3 nunca e sobrescrita pelos scripts Python: regerar 1 e 2 preserva
 * o trabalho manual.
 */

export const WORLD_SCALE = 808     // unidades PS1 por metro
export const SCHEMA_EDITS = 're3.stage.edits/1'
export const SCHEMA_ROOM3D = 're3.room3d/1'

/** PS1 -> three.js (Y-up). O Y do PS1 aponta para BAIXO, dai o sinal. */
export function ps1ToWorld(x, y, z) {
  return [x / WORLD_SCALE, -y / WORLD_SCALE, z / WORLD_SCALE]
}

export class Store {
  constructor() {
    this.stage = null
    this.rooms = {}          // id -> room.src.json
    this.geom = {}           // id -> room.geom.json (paredes/vãos gerados)
    this.layout = null       // stage_layout.json
    this.edits = null        // stage_edits.json (poses ajustadas)
    this.roomEdits = {}      // id -> room3d.json
    this.dirty = new Set()   // 'stage' | id da sala
    this.listeners = new Set()
  }

  on(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn) }
  emit(evt, data) { for (const fn of this.listeners) fn(evt, data) }

  get ids() { return Object.keys(this.rooms).sort() }
  get isDirty() { return this.dirty.size > 0 }

  async loadStage(n) {
    const r = await fetch(`/api/stage/${n}`)
    if (!r.ok) throw new Error(`falha ao carregar STAGE${n}`)
    const d = await r.json()
    this.stage = n
    this.rooms = d.rooms || {}
    this.geom = d.geom || {}
    this.layout = d.layout
    this.roomEdits = d.roomEdits || {}
    this.edits = d.stageEdits || {
      schema: SCHEMA_EDITS,
      note: 'Ajustes manuais de pose. Sobrepoe stage_layout.json (gerado).',
      stage: n,
      rooms: {},
    }
    if (!this.edits.rooms) this.edits.rooms = {}
    this.dirty.clear()
    this.emit('stage', n)
    return d
  }

  /** Pose efetiva de uma sala: edicao manual, senao solver, senao origem. */
  pose(id) {
    const manual = this.edits?.rooms?.[id]
    if (manual && manual.tx !== undefined) {
      return { tx: manual.tx, tz: manual.tz, rot_deg: manual.rot_deg ?? 0, source: 'manual' }
    }
    const solved = this.layout?.rooms?.[id]
    if (solved) {
      return { tx: solved.tx, tz: solved.tz, rot_deg: solved.rot_deg ?? 0, source: 'solver' }
    }
    return { tx: 0, tz: 0, rot_deg: 0, source: 'none' }
  }

  setPose(id, { tx, tz, rot_deg }) {
    const cur = this.pose(id)
    const next = {
      tx: Math.round((tx ?? cur.tx) * 10) / 10,
      tz: Math.round((tz ?? cur.tz) * 10) / 10,
      rot_deg: Math.round((rot_deg ?? cur.rot_deg) * 100) / 100,
    }
    this.edits.rooms[id] = { ...(this.edits.rooms[id] || {}), ...next }
    this.dirty.add('stage')
    this.emit('pose', id)
  }

  /** Devolve a sala ao que o solver calculou (remove so a pose manual). */
  resetPose(id) {
    if (!this.edits?.rooms?.[id]) return
    const { tx, tz, rot_deg, ...rest } = this.edits.rooms[id]
    if (Object.keys(rest).length) this.edits.rooms[id] = rest
    else delete this.edits.rooms[id]
    this.dirty.add('stage')
    this.emit('pose', id)
  }

  isEdited(id) { return Boolean(this.edits?.rooms?.[id]) || Boolean(this.roomEdits[id]) }

  /**
   * room3d.json — geometria editavel da sala. Criado sob demanda a partir do
   * dado do jogo; e aqui que entram larguras ajustadas e as aberturas
   * (portas/janelas) desenhadas a mao.
   */
  roomEdit(id) {
    if (!this.roomEdits[id]) {
      const src = this.rooms[id]
      this.roomEdits[id] = {
        schema: SCHEMA_ROOM3D,
        note: 'Ajustes manuais da sala. Nunca sobrescrito pelos scripts Python.',
        room: id,
        stage: this.stage,
        ceiling_h: src?.bounds ? src.bounds.y_ceiling : null,
        rects: {},        // indice do rect -> { rect?, y?, h?, hidden?, kind? }
        openings: [],     // { wall_rect, kind: 'door'|'window', u, w, h, sill }
      }
    }
    return this.roomEdits[id]
  }

  rectOverride(id, i) { return this.roomEdits[id]?.rects?.[i] || null }

  setRectOverride(id, i, patch) {
    const ed = this.roomEdit(id)
    ed.rects[i] = { ...(ed.rects[i] || {}), ...patch }
    this.dirty.add(id)
    this.emit('rect', { id, i })
  }

  clearRectOverride(id, i) {
    const ed = this.roomEdits[id]
    if (ed?.rects?.[i]) {
      delete ed.rects[i]
      this.dirty.add(id)
      this.emit('rect', { id, i })
    }
  }

  addOpening(id, opening) {
    const ed = this.roomEdit(id)
    ed.openings.push({ kind: 'window', u: 0.5, w: 1000, h: 1400, sill: 900, ...opening })
    this.dirty.add(id)
    this.emit('opening', id)
    return ed.openings.length - 1
  }

  removeOpening(id, idx) {
    const ed = this.roomEdits[id]
    if (!ed?.openings?.[idx]) return
    ed.openings.splice(idx, 1)
    this.dirty.add(id)
    this.emit('opening', id)
  }

  /** Rect efetivo (com override aplicado) — a fonte para montar a geometria. */
  effectiveRect(id, rect) {
    const ov = this.rectOverride(id, rect.i)
    if (!ov) return rect
    return { ...rect, ...ov }
  }

  async save() {
    const wrote = []
    if (this.dirty.has('stage')) {
      const r = await fetch(`/api/stage/${this.stage}/edits`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(this.edits),
      })
      if (!r.ok) throw new Error('falha ao salvar stage_edits.json')
      wrote.push((await r.json()).wrote)
    }
    for (const id of this.dirty) {
      if (id === 'stage') continue
      const r = await fetch(`/api/stage/${this.stage}/room/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(this.roomEdits[id]),
      })
      if (!r.ok) throw new Error(`falha ao salvar ${id}/room3d.json`)
      wrote.push((await r.json()).wrote)
    }
    this.dirty.clear()
    this.emit('saved', wrote)
    return wrote
  }
}
