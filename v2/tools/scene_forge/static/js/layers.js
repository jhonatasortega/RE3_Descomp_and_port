/**
 * layers.js — Gerencia a visibilidade das camadas na cena.
 */
export class LayerManager {
  constructor(sceneManager) {
    this._scene = sceneManager
    this._roomGroup = null
    this._linksObj  = null

    this._layerMap = {
      shell:      { names: ['shell'],      default: true  },
      rects:      { names: ['rects'],      default: true  },
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
      stairs:     { names: ['stairs'],     default: true  },
    }

    this._states = {}
    for (const [key, cfg] of Object.entries(this._layerMap)) {
      this._states[key] = cfg.default
    }

    this._initUI()
  }

  _initUI() {
    document.querySelectorAll('.layer-toggle input[type=checkbox]').forEach(cb => {
      const layer = cb.id.replace('layer', '').replace(/^(.)/, c => c.toLowerCase())
      // Mapeia nomes dos checkboxes (camelCase) para chaves
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

  setRoomGroup(group) {
    this._roomGroup = group
    this._apply()
  }

  setLinks(obj) {
    this._linksObj = obj
    this._apply()
  }

  _apply() {
    if (!this._roomGroup) return

    const show = (name, visible) => {
      this._roomGroup.traverse(child => {
        if (child.name === name || child.userData?.kind === name) {
          child.visible = visible
        }
      })
    }

    // Camadas diretas por nome de grupo
    const nameVis = {
      shell:      this._states.shell,
      rects:      this._states.rects,
      stairs:     this._states.stairs,
      doors:      this._states.doors,
      cams:       this._states.cams,
      lights:     this._states.lights,
      triggers:   this._states.triggers,
      entities:   this._states.items || this._states.enemies,
      maskPlanes: this._states.maskPlanes,
    }

    for (const [name, visible] of Object.entries(nameVis)) {
      this._roomGroup.traverse(child => {
        if (child.name === name) child.visible = visible
      })
    }

    // Links
    if (this._linksObj) {
      this._linksObj.visible = this._states.links
    }

    // Projeção: esconde/mostra o material de projeção (shader) alternando opacidade da casca
    // (gerenciado pelo main.js via evento)
  }

  get states() { return { ...this._states } }
}
