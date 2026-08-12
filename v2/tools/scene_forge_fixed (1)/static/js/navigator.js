/**
 * navigator.js — Navegador de stages e salas.
 * Carrega a lista de stages/salas via API e mantém o estado de seleção.
 */

export class Navigator {
  constructor({ onStageChange, onRoomChange }) {
    this._onStageChange = onStageChange
    this._onRoomChange = onRoomChange
    this._stages = []
    this._currentStage = null
    this._currentRoom = null
    this._stageData = {}

    this._elStageSelector = document.getElementById('stageSelector')
    this._elRoomList      = document.getElementById('roomList')
    this._elSearch        = document.getElementById('roomSearch')

    this._elSearch.addEventListener('input', () => this._filterRooms())
    this._init()
  }

  async _init() {
    try {
      const res = await fetch('/api/stages')
      this._stages = await res.json()
      this._renderStages()
      if (this._stages.length > 0) {
        await this.selectStage(this._stages[0].stage)
      }
    } catch (e) {
      console.error('Navigator: erro ao carregar stages', e)
    }
  }

  _renderStages() {
    this._elStageSelector.innerHTML = ''
    for (const s of this._stages) {
      const btn = document.createElement('button')
      btn.className = 'stage-btn'
      btn.textContent = `S${s.stage}`
      btn.title = `Stage ${s.stage} — ${s.room_count} salas`
      btn.dataset.stage = s.stage
      btn.addEventListener('click', () => this.selectStage(s.stage))
      this._elStageSelector.appendChild(btn)
    }
  }

  async selectStage(stageNum) {
    if (this._currentStage === stageNum && this._stageData[stageNum]) {
      this._renderRooms(this._stageData[stageNum].rooms)
      return
    }
    this._currentStage = stageNum

    // Destaca botão ativo
    this._elStageSelector.querySelectorAll('.stage-btn').forEach(b => {
      b.classList.toggle('active', parseInt(b.dataset.stage) === stageNum)
    })

    try {
      const res = await fetch(`/api/stage/${stageNum}`)
      const data = await res.json()
      this._stageData[stageNum] = data
      this._renderRooms(data.rooms)
      this._onStageChange(data)
    } catch (e) {
      console.error(`Navigator: erro ao carregar stage ${stageNum}`, e)
    }
  }

  _renderRooms(rooms) {
    this._elRoomList.innerHTML = ''
    this._allRooms = rooms
    this._filterRooms()
  }

  _filterRooms() {
    const q = (this._elSearch.value || '').toUpperCase().trim()
    const rooms = this._allRooms || []
    this._elRoomList.innerHTML = ''

    for (const room of rooms) {
      if (q && !room.id.includes(q) && !room.desc.toUpperCase().includes(q)) continue

      const item = document.createElement('div')
      item.className = 'room-item'
      item.dataset.roomId = room.id

      // Thumbnail
      if (room.thumb) {
        const img = document.createElement('img')
        img.className = 'room-thumb'
        img.src = room.thumb
        img.alt = room.id
        img.loading = 'lazy'
        item.appendChild(img)
      } else {
        const ph = document.createElement('div')
        ph.className = 'room-thumb-placeholder'
        item.appendChild(ph)
      }

      // Info
      const info = document.createElement('div')
      info.className = 'room-info'

      const idEl = document.createElement('div')
      idEl.className = 'room-id'
      idEl.textContent = room.id

      const descEl = document.createElement('div')
      descEl.className = 'room-desc'
      descEl.textContent = room.desc || room.area || '—'

      const badges = document.createElement('div')
      badges.className = 'room-badges'
      if (room.camera_count) {
        const b = document.createElement('span')
        b.className = 'badge'
        b.textContent = `📷 ${room.camera_count}`
        badges.appendChild(b)
      }
      if (room.door_count) {
        const b = document.createElement('span')
        b.className = 'badge'
        b.textContent = `🚪 ${room.door_count}`
        badges.appendChild(b)
      }

      info.append(idEl, descEl, badges)
      item.appendChild(info)

      item.addEventListener('click', () => this.selectRoom(room.id))
      this._elRoomList.appendChild(item)
    }
  }

  async selectRoom(roomId) {
    this._currentRoom = roomId

    // Destaca item ativo
    this._elRoomList.querySelectorAll('.room-item').forEach(el => {
      el.classList.toggle('active', el.dataset.roomId === roomId)
    })

    // Scrolls o item para o centro
    const activeEl = this._elRoomList.querySelector(`.room-item[data-room-id="${roomId}"]`)
    activeEl?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })

    try {
      const res = await fetch(`/api/room/${roomId}`)
      const data = await res.json()
      this._onRoomChange(data)
    } catch (e) {
      console.error(`Navigator: erro ao carregar sala ${roomId}`, e)
    }
  }

  navigateToDoor(toRoomId) {
    // Verifica se a sala está no stage atual; se não, muda de stage primeiro
    const stageNum = this._currentStage
    const stageRooms = this._stageData[stageNum]?.rooms || []
    const inStage = stageRooms.some(r => r.id === toRoomId)

    if (!inStage) {
      // Procura em outros stages
      for (const [s, data] of Object.entries(this._stageData)) {
        if (data.rooms.some(r => r.id === toRoomId)) {
          this.selectStage(parseInt(s)).then(() => this.selectRoom(toRoomId))
          return
        }
      }
      // Stage não carregado ainda — tenta detectar pelo ID
      const stageGuess = this._guessStage(toRoomId)
      if (stageGuess) {
        this.selectStage(stageGuess).then(() => this.selectRoom(toRoomId))
        return
      }
    }
    this.selectRoom(toRoomId)
  }

  _guessStage(roomId) {
    // R1xx → 1, R2xx → 2, etc.
    const hex = roomId[1]
    const n = parseInt(hex, 16)
    if (n >= 1 && n <= 7) return n
    return null
  }

  get currentStage() { return this._currentStage }
  get currentRoom()  { return this._currentRoom }
  get stageData()    { return this._stageData[this._currentStage] }
}
