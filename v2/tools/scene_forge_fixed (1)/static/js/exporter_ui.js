/**
 * exporter_ui.js — UI do modal de exportação.
 */
export class ExporterUI {
  constructor({ getCurrentRoom, getCurrentStage, getAllRooms, getCustomBoxes }) {
    this._getCurrentRoom  = getCurrentRoom
    this._getCurrentStage = getCurrentStage
    this._getAllRooms      = getAllRooms
    this._getCustomBoxes   = getCustomBoxes

    this._modal   = document.getElementById('exportModal')
    this._btnOpen = document.getElementById('btnExport')
    this._btnClose = document.getElementById('closeExportModal')
    this._btnCancel = document.getElementById('cancelExport')
    this._btnConfirm = document.getElementById('confirmExport')

    this._btnOpen.addEventListener('click', () => this.open())
    this._btnClose.addEventListener('click', () => this.close())
    this._btnCancel.addEventListener('click', () => this.close())
    this._btnConfirm.addEventListener('click', () => this._doExport())

    this._modal.addEventListener('click', e => {
      if (e.target === this._modal) this.close()
    })
  }

  open() { this._modal.classList.remove('hidden') }
  close() { this._modal.classList.add('hidden') }

  async _doExport() {
    const scope  = document.querySelector('input[name="exportScope"]:checked')?.value || 'current'
    const fmt    = document.querySelector('input[name="exportFmt"]:checked')?.value || 'obj'
    const includeCams  = document.getElementById('exportCams')?.checked ?? true
    const includeDoors = document.getElementById('exportDoors')?.checked ?? true

    let rooms = []
    if (scope === 'current') {
      const r = this._getCurrentRoom?.()
      if (r) rooms = [r]
    } else if (scope === 'stage') {
      rooms = this._getAllRooms?.() || []
    } else {
      rooms = this._getAllRooms?.() || []
    }

    if (!rooms.length) {
      alert('Nenhuma sala selecionada.')
      return
    }

    this._btnConfirm.textContent = '⏳ Exportando...'
    this._btnConfirm.disabled = true

    const customBoxes = this._getCustomBoxes ? this._getCustomBoxes() : []

    try {
      const res = await fetch('/api/export', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rooms, format: fmt, include_cameras: includeCams, custom_boxes: customBoxes }),
      })

      if (!res.ok) throw new Error(await res.text())

      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `re3_export.${fmt}`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)

      this.close()
    } catch (e) {
      alert(`Erro ao exportar: ${e.message}`)
    } finally {
      this._btnConfirm.textContent = '⬇ Exportar'
      this._btnConfirm.disabled = false
    }
  }
}
