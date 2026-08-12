/**
 * layers.js — Gerencia a visibilidade das camadas na cena.
 */
export class LayerManager {
  constructor(sceneManager) {
    this._scene = sceneManager
    this._roomGroups = new Map()   // roomId -> THREE.Group (todas as salas carregadas do stage)
    this._activeRoomId = null
    this._linksObj  = null

    this._layerMap = {
      shell:      { names: ['shell'],      default: true  },
      // Colisão = volumes de física/gameplay do jogo original, não a
      // arquitetura visual da sala. Fica OFF por padrão (liga manualmente
      // se quiser inspecionar blockout de colisão).
      rects:      { names: ['rects'],      default: false },
      stairs:     { names: ['stairs'],     default: true  },
      doors:      { names: ['doors'],      default: true  },
      links:      { names: ['links'],      default: true  },
      cams:       { names: ['cams'],       default: false },
      lights:     { names: ['lights'],     default: false },
      items:      { names: ['entities'],   default: true  },
      enemies:    { names: ['entities'],   default: true  },
      triggers:   { names: ['triggers'],   default: false },
      maskPlanes: { names: ['maskPlanes'], default: false },
      projection: { names: ['shell'],      default: true  },
      // NOVO: mostra as demais salas do stage além da selecionada. OFF por
      // padrão — muitas salas do RE3 compartilham quase a mesma posição
      // (variantes/estados alternativos do mesmo ambiente), então mostrar
      // todas juntas produz uma pilha de caixas sobrepostas e desconexas.
      otherRooms: { names: [],             default: false },
    }

    this._states = {}
    for (const [key, cfg] of Object.entries(this._layerMap)) {
      this._states[key] = cfg.default
    }

    this._initUI()
  }

  _initUI() {
    document.querySelectorAll('.layer-toggle input[type=checkbox]').forEach(cb => {
      const key = this._mapCheckboxId(cb.id)
      if (key in this._states) {
        cb.checked = this._states[key]
      }
      cb.addEventListener('change', () => {
        const k = this._mapCheckboxId(cb.id)
        this._states[k] = cb.checked
        this._apply()
      })
    })
  }

  _mapCheckboxId(id) {
    // e.g. 'layerMaskPlanes' → 'maskPlanes'
    return id.replace('layer', '').replace(/^(.)/, c => c.toLowerCase())
  }

  /** Registra TODAS as salas carregadas do stage (chamado depois de loadStage). */
  setAllRoomGroups(map) {
    this._roomGroups = map
    this._apply()
  }

  /** Define qual sala está "ativa" (a que foi selecionada pelo usuário). */
  setActiveRoom(roomId) {
    this._activeRoomId = roomId
    this._apply()
  }

  /** Compat: mantém a API antiga (usada quando só uma sala está carregada). */
  setRoomGroup(group) {
    if (group) {
      const roomId = group.userData?.roomId
      if (roomId) {
        this._activeRoomId = roomId
        if (!this._roomGroups.has(roomId)) this._roomGroups.set(roomId, group)
      }
    }
    this._apply()
  }

  setLinks(obj) {
    this._linksObj = obj
    this._apply()
  }

  _apply() {
    if (!this._roomGroups.size) return

    const show = (root, name, visible) => {
      root.traverse(child => {
        if (child.name === name) child.visible = visible
      })
    }

    for (const [roomId, group] of this._roomGroups.entries()) {
      const isActive = roomId === this._activeRoomId

      // Sala não-ativa: some inteira, a menos que "Outras salas" esteja ligado.
      if (!isActive && !this._states.otherRooms) {
        group.visible = false
        continue
      }

      group.visible = true
      show(group, 'shell',      this._states.shell)
      show(group, 'doors',      this._states.doors)
      show(group, 'stairs',     this._states.stairs)
      show(group, 'cams',       this._states.cams)
      show(group, 'lights',     this._states.lights)
      show(group, 'triggers',   this._states.triggers)
      show(group, 'entities',   this._states.items || this._states.enemies)
      show(group, 'maskPlanes', this._states.maskPlanes)
      // Colisão só aparece na sala ativa mesmo com "Outras salas" ligado,
      // senão a poluição visual volta quando o stage inteiro está visível.
      show(group, 'rects', isActive ? this._states.rects : false)
    }

    if (this._linksObj) {
      this._linksObj.visible = this._states.links
    }
  }

  get states() { return { ...this._states } }
}
