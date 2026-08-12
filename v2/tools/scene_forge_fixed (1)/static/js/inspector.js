/**
 * inspector.js — Painel direito com propriedades da sala e objetos selecionados.
 */
const WORLD_SCALE = 808
const M = v => (v / WORLD_SCALE).toFixed(2)

export class Inspector {
  constructor({ onCameraSelect, onDoorNavigate }) {
    this._el = document.getElementById('inspectorContent')
    this._onCameraSelect = onCameraSelect
    this._onDoorNavigate = onDoorNavigate
    this._roomData = null
  }

  setRoom(data) {
    this._roomData = data
    const src = data.room
    const b   = src.bounds || {}
    const bgUrls = data.bg_urls || {}

    const w = b.size?.[0] ?? 0
    const d = b.size?.[1] ?? 0
    const h = b.ceiling_h ?? 0

    this._el.innerHTML = `
      <div class="insp-section">
        <div class="insp-title">Sala</div>
        <div class="insp-row">
          <span class="insp-key">ID</span>
          <span class="insp-val accent">${src.room}</span>
        </div>
        <div class="insp-row">
          <span class="insp-key">Área</span>
          <span class="insp-val">${src.area || '—'}</span>
        </div>
        <div class="insp-row">
          <span class="insp-key">Descrição</span>
          <span class="insp-val">${src.desc || '—'}</span>
        </div>
        <div class="insp-row">
          <span class="insp-key">Stage</span>
          <span class="insp-val">${src.stage}</span>
        </div>
      </div>

      <div class="insp-section">
        <div class="insp-title">Dimensões</div>
        <div class="insp-row">
          <span class="insp-key">Largura (X)</span>
          <span class="insp-val">${M(w)} m <span style="color:var(--text-muted);font-size:10px">(${w} un)</span></span>
        </div>
        <div class="insp-row">
          <span class="insp-key">Profund. (Z)</span>
          <span class="insp-val">${M(d)} m <span style="color:var(--text-muted);font-size:10px">(${d} un)</span></span>
        </div>
        <div class="insp-row">
          <span class="insp-key">Pé-direito</span>
          <span class="insp-val">${M(h)} m</span>
        </div>
        <div class="insp-row">
          <span class="insp-key">Y piso (PS1)</span>
          <span class="insp-val amber">${b.y_floor ?? '—'}</span>
        </div>
      </div>

      <div class="insp-section">
        <div class="insp-title">Contagens</div>
        ${this._countsRows(src.counts || {})}
      </div>

      <div class="insp-section">
        <div class="insp-title">Câmeras (${src.cameras?.length || 0})</div>
        <div class="cam-list" id="insp-cam-list"></div>
      </div>

      <div class="insp-section">
        <div class="insp-title">Portas (${src.doors?.length || 0})</div>
        <div class="door-list" id="insp-door-list"></div>
      </div>

      <div class="insp-section">
        <div class="insp-title">Máscaras de Profundidade</div>
        ${this._maskInfo(src.cameras || [])}
      </div>
    `

    this._renderCameras(src.cameras || [], bgUrls)
    this._renderDoors(src.doors || [])
  }

  _countsRows(c) {
    const rows = [
      ['Rects colisão', c.rects, ''],
      ['Paredes', c.rects_wall, ''],
      ['Câmeras', c.cameras, ''],
      ['Portas', c.doors, ''],
      ['Itens', c.gp_items, ''],
      ['Inimigos', c.gp_enemies, ''],
      ['Gatilhos', c.gp_triggers, ''],
      ['Luzes', c.lights, ''],
    ]
    return rows.map(([key, val]) =>
      val ? `<div class="insp-row">
        <span class="insp-key">${key}</span>
        <span class="insp-val">${val ?? 0}</span>
      </div>` : ''
    ).join('')
  }

  _maskInfo(cameras) {
    if (!cameras.length) return '<div class="insp-row"><span class="insp-key">—</span></div>'
    return cameras.map(cam => {
      const mask = cam.mask
      if (!mask) return ''
      const depths = [mask.primary_depth, ...(mask.group_depths || [])].filter(Boolean)
      return `<div class="insp-row">
        <span class="insp-key">Cam ${cam.index}</span>
        <span class="insp-val" style="font-size:10px">${depths.map(d => `${(d*16/WORLD_SCALE).toFixed(1)}m`).join(' · ')}</span>
      </div>`
    }).join('')
  }

  _renderCameras(cameras, bgUrls) {
    const list = document.getElementById('insp-cam-list')
    if (!list) return
    list.innerHTML = ''

    for (const cam of cameras) {
      const item = document.createElement('div')
      item.className = 'cam-item'

      const bgUrl = cam.bg_url || bgUrls[cam.index]
      if (bgUrl) {
        const img = document.createElement('img')
        img.className = 'cam-thumb'
        img.src = bgUrl
        img.alt = `Câmera ${cam.index}`
        img.loading = 'lazy'
        item.appendChild(img)
      }

      const info = document.createElement('div')
      info.className = 'cam-info'
      info.innerHTML = `
        <div class="cam-id">Câmera ${cam.index}</div>
        <div class="cam-attr">attr: ${cam.attr} · flag: ${cam.flag}</div>
        <div class="cam-attr">dist: ${(cam.distance / WORLD_SCALE).toFixed(1)} m</div>
      `
      item.appendChild(info)

      item.addEventListener('click', () => this._onCameraSelect?.(cam.index))
      list.appendChild(item)
    }
  }

  _renderDoors(doors) {
    const list = document.getElementById('insp-door-list')
    if (!list) return
    list.innerHTML = ''

    for (const door of doors) {
      const item = document.createElement('div')
      item.className = 'door-item'
      item.innerHTML = `
        <div>
          <span class="door-to">→ ${door.to_room}</span>
          ${!door.reciprocal ? '<span class="door-oneway">mão única</span>' : ''}
        </div>
        <div style="font-size:10px;color:var(--text-muted)">
          sce: ${door.sce} · conf: ${((door.dest_conf || 0) * 100).toFixed(0)}%
        </div>
      `
      item.addEventListener('click', () => this._onDoorNavigate?.(door.to_room))
      list.appendChild(item)
    }
  }

  setSelectedObject(obj) {
    if (!obj) return
    const ud = obj.userData
    if (ud.kind === 'rect' || ud.kind === 'wall' || ud.kind === 'prop') {
      this._showRectInfo(ud.rectData)
    } else if (ud.kind === 'door') {
      this._showDoorInfo(ud.door)
    }
  }

  _showRectInfo(r) {
    if (!r) return
    const [x0, z0, x1, z1] = r.rect
    const w = Math.abs(x1 - x0), d = Math.abs(z1 - z0), h = Math.abs(r.h)
    const detail = document.createElement('div')
    detail.className = 'insp-section'
    detail.innerHTML = `
      <div class="insp-title">Rect Selecionado #${r.i}</div>
      <div class="insp-row"><span class="insp-key">Tipo</span>
        <span class="insp-val ${r.wall ? 'amber' : ''}">${r.wall ? 'Parede' : 'Prop'}</span></div>
      <div class="insp-row"><span class="insp-key">Largura</span>
        <span class="insp-val">${M(w)} m <span style="color:var(--text-muted);font-size:10px">(${w})</span></span></div>
      <div class="insp-row"><span class="insp-key">Profund.</span>
        <span class="insp-val">${M(d)} m</span></div>
      <div class="insp-row"><span class="insp-key">Altura</span>
        <span class="insp-val">${M(h)} m</span></div>
      <div class="insp-row"><span class="insp-key">Y</span>
        <span class="insp-val amber">${r.y}</span></div>
    `
    // Insere no topo do conteúdo
    this._el.insertBefore(detail, this._el.firstChild)
    setTimeout(() => detail.remove(), 5000)
  }

  _showDoorInfo(door) {
    if (!door) return
    const detail = document.createElement('div')
    detail.className = 'insp-section'
    detail.innerHTML = `
      <div class="insp-title">Porta Selecionada #${door.i}</div>
      <div class="insp-row"><span class="insp-key">Destino</span>
        <span class="insp-val accent">${door.to_room}</span></div>
      <div class="insp-row"><span class="insp-key">Tipo</span>
        <span class="insp-val">${door.reciprocal ? 'Bidirecional' : 'Mão única'}</span></div>
    `
    this._el.insertBefore(detail, this._el.firstChild)
    setTimeout(() => detail.remove(), 5000)
  }

  clear() {
    this._el.innerHTML = `<div class="inspector-empty"><p>Selecione uma sala para ver os detalhes.</p></div>`
  }
}
