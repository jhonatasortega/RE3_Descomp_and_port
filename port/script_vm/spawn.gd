class_name Spawn
extends RefCounted
## Personagem colocado pelo script: `sce_em_set`, opcode `0x7d` (P2-06).
##
## É por aqui que os 1136 inimigos + 80 NPCs entram nas 137 salas — instalados pelo SCRIPT, não
## por lista externa. Layout de 24 B lido do handler `0x80056a2c` (docs/decomp/notes/sce_em_set.md):
##
##     +0x02 s8  slot           índice no array de personagens (-1 = especial)
##     +0x03 u8  CLASSE         -> char+0x4a (id de espécie; indexa a tabela de dano)
##     +0x04 u16 arma           -> char+0x46
##     +0x06 u16 status inicial -> char+0xd2
##     +0x0b u8  MODEL id       -> char+0x147 (0xff = sem modelo dedicado: NPC/PLD)
##     +0x0c s16 X · +0x0e s16 Y · +0x10 s16 Z · +0x12 s16 direção
##     +0x14 u16 yaw de mira · +0x16 u16 pitch de mira
##
## **Espécie vem com CONFIANÇA declarada.** O mapa canônico classe↔espécie não existe no EXE
## nem publicado: `data/sce_enemies.json` traz `class_to_species` com `conf` ALTA/MÉDIA/BAIXA
## (ALTA+MÉDIA = 43,5% das classes; categoria-ou-melhor = 81,2%). O port usa o rótulo e diz a
## confiança — não inventa nome.

var slot := 0
var classe := 0
var arma := 0
var status := 0
var model_id := 0
var pos := Vector3i.ZERO
var dir := 0
var aim_yaw := 0
var aim_pitch := 0

## Preenchido por `resolver_especie()`.
var especie := ""
var conf := ""
var emd := ""

static var _tabela: Dictionary = {}
static var _carregada := false


static func _carregar() -> void:
	if _carregada:
		return
	_carregada = true
	var d: Variant = AssetIO.json("sce_enemies.json")
	if d is Dictionary and (d as Dictionary).has("class_to_species"):
		_tabela = (d as Dictionary)["class_to_species"]


func resolver_especie() -> void:
	_carregar()
	var chave := "0x%02x" % classe
	if not _tabela.has(chave):
		especie = "(classe 0x%02x sem anotação)" % classe
		conf = "NENHUMA"
		return
	var e: Dictionary = _tabela[chave]
	especie = str(e.get("species", "?"))
	conf = str(e.get("conf", "?"))
	var ann: Variant = e.get("emd_annotation")
	if ann is Dictionary:
		emd = str((ann as Dictionary).get("emd_file", "")).get_basename().to_lower()


func modelo_rel() -> String:
	## Caminho do `.glb` (nomeados `em10.glb`… pelo emd2gltf). "" se não houver anotação.
	if emd == "":
		resolver_especie()
	return "ENEMY/%s.glb" % emd if emd != "" else ""


func resumo() -> String:
	if especie == "":
		resolver_especie()
	return "slot %d classe 0x%02x (%s, conf %s) pos %s dir %d modelo %s" % [
		slot, classe, especie, conf, pos, dir,
		modelo_rel() if modelo_rel() != "" else "(sem)"]
