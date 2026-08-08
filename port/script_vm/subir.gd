class_name SubirObjeto
extends RefCounted
## SUBIR EM OBJETO (a "lixeira" do R10D) — a rotina **r9** do player, recompilada.
##
## Este arquivo existe porque `port/actors/player.gd` não é meu: aqui fica a máquina de estados
## e o gatilho, prontos para o `player.gd` chamar. A lista do que engatar lá está no fim.
##
## ══════════════════ 1. O EVENTO DO R10D **NÃO** É O "SUBIR" ══════════════════
## O R10D tem exatamente um AOT: `0x63` na **função 5** do `R10D.scd`, offset `0x0122`:
##
##     63 01 05 41 00 00 | 77 de 68 c5 e4 0c 74 0e | ff 00 19 0b 00 00
##     op aot sce sat fl -  x=-8585 z=-15000 w=3300 d=3700   payload
##
## `sce = 5` → handler **`0x800512bc`** (tabela `0x8009e0bc`). Esse handler faz exatamente isto:
##
##     if (*(u32*)0x800ccba0 & 0x02000000) return;          // 0x800512c8..d4
##     a0 = *(u16*)(payload + 0);   // 0x00ff = 255         // 0x800512dc  lhu $a0,($a1)
##     a1 = *(u8*) (payload + 3);   // 0x0b   = 11          // 0x800512e0  lbu $a1,3($a1)
##     0x80052478(a0, a1);
##
## e `0x80052478` → `0x8005242c` monta o PC da thread: `a2 = *(0x800e0144)` (base do script),
## `PC = a2 + *(u16*)(a2 + func*2)` (`0x8005242c..0x80052474`). Ou seja o payload é o MESMO
## descritor do opcode `0x04` (`evt_exec`): **slot de thread `0xff` (qualquer livre, 2..9) e
## função `11`**. Nada de animação, nada de player.
##
## A **função 11** (offset 1570 do bytecode, 250 B) é uma CENA: `65 aot_reset`, `4d` flag set,
## `19 0d/0e/0f/16..19/1a/20..25` (gosubs), `0a` yields, `55/56` som, `46` câmera, `40` var,
## `04 ff 19 xx` (novas threads), `10/11` while/break e `01` no fim. É cutscene, não o subir.
## Somado ao que o chamador já apurou (a caixa `x[-8585..-5285] z[-15000..-11300]` fica a OESTE
## da captura em `x=-3678, z=-12960`), fica **PROVADO que o AOT do R10D não é o gatilho**.
##
## ══════════════════ 2. QUAL É O GATILHO DE VERDADE (provado) ══════════════════
## O "subir/descer" é a **rotina 9** da ação on-foot (`exe_combat.md §3.2`), e quem a liga é uma
## FLAG GLOBAL, não um AOT. A cadeia inteira, sítio por sítio:
##
## a) **Detecção de contato** — `0x80036c60`, uma das entradas da tabela de handler por tipo de
##    objeto de cenário `0x8009cc64` (índice = `om+4`); é a **entrada 0**
##    (`0x8009cc64[0] = 0x80036c60`). O laço que a chama percorre o pool de 32 objetos `om`
##    (`gs+0x4328`, passo `0x194`, fim em `gs+0x75a8`) em `0x8003650c..0x8003654c`:
##
##      if (!(obj->flags & 1)) return;                                   // 0x80036c7c
##      if (player+5 != 1 && player+5 != 9) obj+0xc0 = 0;   // rotina andar(1)/subir(9)
##      if ((obj+0xae & 0x10) && (obj+0xba & 0x8000)) {                   // 0x80036cac/c0
##          *(0x800dd4ac) += 1;                                          // 0x80036cd8
##          if (player+9 == obj+9) *(0x800dd4b0) = obj;   // MESMO piso  // 0x80036cf0
##      }
##
## b) **6 quadros de contato → acende a flag** — `0x80036570`, chamada uma vez por quadro logo
##    depois do laço (`0x80036550`):
##
##      if (*(0x800dd4ac) != 1) return;                                  // 0x8003657c
##      obj = *(0x800dd4b0); if (!obj) return;                           // 0x8005658c
##      if (obj->flags & 0x4000) return; if (!(obj->flags & 0x100)) return;
##      if (++obj+0xc0 < 6) { restaura X/Z; return; }   // 6 quadros!    // 0x800365c8
##      if (obj+0xae & 0x20) { obj+0xc0 = 0; restaura X/Z; return; }
##      *(0x800d1f2c) |= 0x10;                                           // 0x800365fc ★
##      *(0x800dd4ac) = 0;  if (obj+0xc0 != 6) obj+0xc0 = 7;
##
##    `0x800365fc` é o **ÚNICO** sítio do EXE que acende o bit `0x10` de `0x800d1f2c`
##    (varredura de todo `sw ..., 0x77f4(reg)` precedido de `ori ..., 0x10`). E ele é APAGADO
##    no começo de cada quadro em `0x800364f8..0x80036508`
##    (`addiu $v1,$zero,-0x11; and; sw`), junto com `0x800dd4ac`/`0x800dd4b0` — ou seja a flag é
##    RECALCULADA a cada quadro, não é estado persistente.
##
## c) **A flag entra na rotina 9** — no FIM de r1 (andar para frente) e de r2 (ré):
##
##      0x800397b0  lw $v0, 0x1f2c($v0)   ; r1  (0x8003957c)
##      0x800397b8  andi $v0, $v0, 0x10
##      0x800397c0  addiu $v0, $zero, 0x901
##      0x800397c4  sw $v0, 4($s0)        ; player+4 = action 1 | routine 9  ★
##      0x80039b58..0x80039b6c            ; idêntico em r2 (0x80039924)
##
##    E o único leitor de `0x800d1f2c & 0x10` em toda a máquina de estados é `0x800350f8`
##    (passe de colisão) mais estes dois — não há outro consumidor.
##
## ══════════════════ 3. A ANIMAÇÃO (provada) ══════════════════
## r9 é o par `move 0x8003b1c4` + `anim 0x8003b244`. O `anim` despacha por `player+6` numa
## tabela de **8** subestados em `0x800107d0`, e os `player+0xc8` que ele escreve são:
##
##   sub 2 (`0x8003b38c`): `sw 0x00070006, 0xc8($s0)`  →  **SEQ 6**  (0x8003b39c)
##   sub 4 (`0x8003b3b4`): `sw 0x00070007, 0xc8($s0)`  →  **SEQ 7**  (0x8003b3c4)
##   r9 move (`0x8003b20c`): `sb 6, 0xc8` + `sb 0, 0xc9` + `sb 7, 0xca` = o mesmo 0x00070006
##
## (o byte `+0xca = 7` é a constante `0x0007<<16` que TODA a SM escreve junto do índice —
## `exe_combat.md §3.2` — não é um terceiro índice de animação).
##
## Logo: **subir em objeto = sequências 6 e 7** do banco EDD ativo. No `PL00.glb` isso é
## `anim06`/`anim07` (banco do `PL00.PLD`) ou `arm06`/`arm07` (banco 0 do `PL00W00.PLW`).
## 🟡 **NÃO PROVADO qual banco**: o dispatcher `0x80038c7c` passa `a1 = player+0xe8`,
## `a2 = player+0xec` (o banco default) e r9 repassa os dois a `0x80027940` sem trocar de
## ponteiro; como a base é escolhida em runtime pela arma equipada (`animacoes_player.md`), com
## arma na mão o índice 6/7 cai no PLW. O port usa `anim06`/`anim07` por padrão (ver `CLIPES`),
## trocável numa linha.
##
## ⚠ **CORREÇÃO a `docs/formatos/animacoes_player.md`**: a tabela das 22 seqs rotula a 06 como
## "Passo curto virando" (confiança média) e a 07 como "Postura dinâmica (+X)" (baixa), ambos
## por render. O papel real das duas está PROVADO aqui: são o par de **subir/descer em objeto**
## da rotina 9. A pendência "validar 'subir em item'" listada no STATUS daquele doc fecha.
##
## ══════════════════ 4. O QUE FALTA (honesto) ══════════════════
## O R10D tem 3 objetos `om` (opcode `0x7f`, função 4, slots 0/1/2) em
## `(11844,-180,-9306)`, `(15408,-180,-9306)` e `(-14550,0,-12625)` — **nenhum** na captura do
## dono. Os campos que marcam o objeto como escalável (`om+0xae & 0x10`, `om+0xba & 0x8000`)
## são de RUNTIME: o descritor de 40 B do `0x7f` não os carrega, quem os escreve é o script
## (member-set) ou o carregador de modelo. Então **qual om é a lixeira não sai do dado estático**
## — do mesmo jeito que a espécie do inimigo não sai (ver `sce_em_set.md §2.1`).
## O que EXISTE no dado, e é o melhor limite: na colisão do R10D o retângulo #9
## `(-4128,-15823)..(-3328,-10197)` (800 de largura, `forma 8`, `topo -3600`, `nivel 1`) contém
## EXATAMENTE a posição da captura e é 1800 unidades mais ALTO que os vizinhos #7/#10
## (`forma 1/7`, `topo -1800`) — a geometria de um degrau para subir. Por isso o gatilho aqui é
## **data-driven**: `pontos` é uma lista de caixas escaláveis, e a candidata do R10D entra como
## **declarada / NÃO PROVADA** em `PONTOS_DECLARADOS`.

## Quadros de contato antes de acender a flag: `sltiu $v0, $v0, 6` em `0x800365c8`.
const FRAMES_CONTATO := 6
## Bit da flag global `0x800d1f2c` (= `gs+0x77f4`) que liga a rotina 9. Aceso só em
## `0x800365fc`, apagado todo quadro em `0x800364f8`.
const FLAG_SUBIR := 0x10
## Rotinas do player que mantêm a contagem viva (`0x80036c88..0x80036c9c`): 1 = andar frente,
## 9 = a própria rotina de subir.
const ROTINAS_VALIDAS: Array[int] = [1, 9]
## Rotina 9 e ação 1: o valor exato que r1/r2 escrevem em `player+4` (`0x800397c0`).
const ACTION_ROUTINE_R9 := 0x901
const ROTINA_SUBIR := 9

## Sequências do banco EDD (provadas em `0x8003b39c` / `0x8003b3c4`).
const SEQ_SUBIR := 6
const SEQ_TOPO := 7
## Nomes de clipe no `port/assets/PLD/PL00.glb`. Trocar para `arm06`/`arm07` liga o banco
## ARMADO (banco 0 do PLW) — qual dos dois o motor usa é 🟡 (ver o cabeçalho §3).
const CLIPES := {SEQ_SUBIR: "anim06", SEQ_TOPO: "anim07"}

## Subestados de `player+6` na rotina 9 — tabela `0x800107d0`, 8 entradas, uma a uma:
##   0 `0x8003b294` entra: `sub = 1`, anim = linha do ANDAR da tabela 3×3 (`0x8009cde0 + 3`),
##                  e liga `gs+0x77f4 |= 0x100` (trava o gate de evento durante a ação)
##   1 `0x8003b2d8` roda o andar/alinhamento: passo (`0x800776b0`), integra (`0x80027940`,
##                  `a3 = 0x200`), gira `player+0x6e`; quando `0x6e & 0x3e0 == 0` → `sub = 2`
##   2 `0x8003b38c` `sub = 3` e **anim SEQ 6**
##   3 `0x8003b3a0` avança a SEQ 6 (`0x80027940`, `a3 = 0x200`)
##   4 `0x8003b3b4` `sub = 5` e **anim SEQ 7**
##   5 `0x8003b3c8` roda a SEQ 7; se `player+0xc9 == 1` dispara SFX `0x1022c` (`0x800746c0`) e
##                  a vibração (`0x80038678(2,0)`, `0x80038704(3,0x96,0)`,
##                  `0x8003879c(0x14,0x96,0,3)`) = o IMPACTO de pousar em cima
##   6 `0x8003b494` avança com `a3 = 0x10200` e soma o retorno em `player+6` (fim da anim)
##   7 `0x8003b4c4` `gs+0x77f4 &= ~0x100` e **`player+4 = 1`** → volta para a ação on-foot
## O `move` (`0x8003b1c4`) só age no `sub == 5`: se o pad de direção está SEGURADO **e** a flag
## `0x10` continua acesa ele NÃO avança (é o "segurar para continuar"); caso contrário põe
## `sub = 6` e reescreve a anim, com SFX `0x10200` (`0x8003b224`).
enum Sub { ENTRA = 0, ALINHA = 1, INICIA_SUBIDA = 2, SUBINDO = 3, INICIA_TOPO = 4,
	NO_TOPO = 5, TERMINANDO = 6, SAI = 7 }

## SFX disparados por r9 (ids de `0x800746c0`, o mesmo caminho do resto dos efeitos).
const SFX_INICIO := 0x10200            ## `0x8003b224` (r9 move, entra em `sub 6`)
const SFX_IMPACTO := 0x1022C           ## `0x8003b3e8` (`sub 5` com `player+0xc9 == 1`)

## ── Pontos escaláveis DECLARADOS por sala (NÃO PROVADO) ──
## Formato: `{ "R10D": [ {"caixa": Rect2i(x, z, w, d), "y_topo": int, "nota": String} ] }`
## A caixa é testada contra o PONTO DE SONDA de 620 unidades à frente (a mesma sonda dos AOT de
## ação, `0x800505c8`), porque subir exige estar de frente para o objeto. `y_topo` é a altura em
## que o personagem termina (o `topo` do retângulo de colisão).
const PONTOS_DECLARADOS := {
	## Candidata do R10D: o retângulo #9 da colisão da sala — 800 de largura, `topo -3600`
	## (1800 acima dos vizinhos), e contém a posição da captura do dono (-3678,-12960).
	## **DECLARADO, NÃO PROVADO**: o marcador real (`om+0xae & 0x10`) é runtime e não está no
	## descritor de 40 B do `0x7f`. Se um dia o `om` da lixeira for identificado, isto sai.
	"R10D": [{"caixa": Rect2i(-4128, -15823, 800, 5626), "y_topo": -3600,
		"nota": "rect #9 da colisao (forma 8, topo -3600, nivel 1) — degrau de 1800"}],
}

var pontos: Array[Dictionary] = []      ## pontos escaláveis da sala corrente
var flag := false                       ## espelho de `0x800d1f2c & 0x10` (recalculada por quadro)
var contato := 0                        ## `om+0xc0` — quadros de contato acumulados
var sub: Sub = Sub.ENTRA
var ativo := false                      ## a rotina 9 está rodando?
var ponto_atual: Dictionary = {}
var sfx_pendente := 0                   ## id de SFX a tocar neste quadro (0 = nenhum)
var quadros_no_sub := 0


func carregar_sala(room_id: String) -> int:
	## Instala os pontos escaláveis DECLARADOS da sala. Devolve quantos.
	pontos = []
	flag = false
	contato = 0
	ativo = false
	sub = Sub.ENTRA
	ponto_atual = {}
	var lista: Variant = PONTOS_DECLARADOS.get(room_id, [])
	for p: Dictionary in lista:
		pontos.append(p.duplicate(true))
	return pontos.size()


func adicionar_ponto(caixa: Rect2i, y_topo: int, nota := "") -> void:
	## Para testes e para quando o `om` escalável for identificado por sala.
	pontos.append({"caixa": caixa, "y_topo": y_topo, "nota": nota})


func ponto_em_frente(pos: Vector3i, facing: int) -> Dictionary:
	## Ponto escalável sob a SONDA de 620 unidades à frente (a mesma do laço de AOT).
	var s := ScriptVM.sonda_de(pos, facing)
	for p: Dictionary in pontos:
		var c: Rect2i = p["caixa"]
		if s.x >= c.position.x and s.x <= c.position.x + c.size.x \
				and s.y >= c.position.y and s.y <= c.position.y + c.size.y:
			return p
	return {}


func detectar(pos: Vector3i, facing: int, rotina: int, andando: bool) -> bool:
	## Um quadro do detector (`0x80036c60` + `0x80036570`). Devolve o novo valor da FLAG.
	##
	## `andando` = o pad está pedindo movimento (é o que mantém o personagem encostando; no
	## motor o contato existe porque a colisão devolve o X/Z ao valor anterior todo quadro,
	## `0x80036624..0x80036630`).
	##
	## Regras copiadas: a contagem zera se a rotina não é 1 nem 9 (`0x80036ca0`), e a flag só
	## acende quando a contagem CHEGA a 6 (`0x800365c8  sltiu $v0,$v0,6`).
	flag = false                                    ## apagada todo quadro (`0x800364f8`)
	if not ROTINAS_VALIDAS.has(rotina):
		contato = 0
		ponto_atual = {}
		return false
	var p := ponto_em_frente(pos, facing)
	if p.is_empty() or not andando:
		contato = 0
		ponto_atual = {}
		return false
	ponto_atual = p
	contato += 1
	if contato < FRAMES_CONTATO:
		return false
	flag = true
	return true


func deve_entrar(rotina: int) -> bool:
	## O que r1/r2 fazem no fim (`0x800397b0..0x800397c4`): se a flag está acesa, `player+4`
	## passa a `0x901`. Só de r1 (andar frente) e r2 (ré) — não de idle, corrida ou mira.
	return flag and (rotina == 1 or rotina == 2)


func iniciar() -> void:
	ativo = true
	sub = Sub.ENTRA
	quadros_no_sub = 0
	sfx_pendente = 0


## Duração de cada subestado em quadros. 🟡 **DECLARADO**: no motor a saída de cada subestado é
## o RETORNO de `0x80027940` (a animação acabou), não um contador. Aqui, sem o EDD ligado, uso
## a contagem de quadros dos clipes medidos em `docs/formatos/animacoes_player.md`
## (seq 06 = 10 quadros, seq 07 = 25) para o estado avançar sozinho; quando o `player.gd`
## estiver dirigindo o `AnimationPlayer`, troque por `anim_terminou()`.
const QUADROS_SUB := {Sub.ALINHA: 6, Sub.SUBINDO: 10, Sub.NO_TOPO: 25, Sub.TERMINANDO: 2}


func avancar(segurando_direcao: bool) -> Sub:
	## Um quadro da rotina 9. Devolve o subestado corrente. `sfx_pendente` sai != 0 no quadro em
	## que o motor dispararia o efeito.
	sfx_pendente = 0
	if not ativo:
		return sub
	quadros_no_sub += 1
	match sub:
		Sub.ENTRA:
			sub = Sub.ALINHA
			quadros_no_sub = 0
		Sub.ALINHA:
			if quadros_no_sub >= int(QUADROS_SUB[Sub.ALINHA]):
				sub = Sub.INICIA_SUBIDA
				quadros_no_sub = 0
		Sub.INICIA_SUBIDA:
			sub = Sub.SUBINDO
			quadros_no_sub = 0
		Sub.SUBINDO:
			if quadros_no_sub >= int(QUADROS_SUB[Sub.SUBINDO]):
				sub = Sub.INICIA_TOPO
				quadros_no_sub = 0
		Sub.INICIA_TOPO:
			sub = Sub.NO_TOPO
			quadros_no_sub = 0
			sfx_pendente = SFX_IMPACTO          ## `sub 5` com `+0xc9 == 1` (`0x8003b3e8`)
		Sub.NO_TOPO:
			# o `move` só avança quando a direção NÃO está segurada com a flag acesa
			if segurando_direcao and flag:
				return sub
			if quadros_no_sub >= int(QUADROS_SUB[Sub.NO_TOPO]):
				sub = Sub.TERMINANDO
				quadros_no_sub = 0
				sfx_pendente = SFX_INICIO       ## `0x8003b224` na virada para `sub 6`
		Sub.TERMINANDO:
			if quadros_no_sub >= int(QUADROS_SUB[Sub.TERMINANDO]):
				sub = Sub.SAI
				quadros_no_sub = 0
		Sub.SAI:
			ativo = false
	return sub


func seq() -> int:
	## Índice de sequência do EDD que o motor teria em `player+0xc8` neste subestado.
	## -1 = o subestado usa a animação de ANDAR (linha da tabela 3×3), não uma seq própria.
	match sub:
		Sub.INICIA_SUBIDA, Sub.SUBINDO:
			return SEQ_SUBIR
		Sub.INICIA_TOPO, Sub.NO_TOPO, Sub.TERMINANDO:
			return SEQ_TOPO
		_:
			return -1


func clipe() -> String:
	var s := seq()
	return String(CLIPES.get(s, "")) if s >= 0 else ""


func y_destino() -> int:
	## Altura em que o personagem termina (o `topo` do ponto). 0 = sem ponto.
	return int(ponto_atual.get("y_topo", 0)) if not ponto_atual.is_empty() else 0


func resumo() -> String:
	return "subir: pontos=%d flag=%s contato=%d/%d ativo=%s sub=%s clipe=%s" % [
		pontos.size(), flag, contato, FRAMES_CONTATO, ativo, Sub.keys()[sub], clipe()]


# ═════════════════════════════════════════════════════════════════════════════════
# O QUE ENGATAR NO `port/actors/player.gd` (não editei — é seu)
# ═════════════════════════════════════════════════════════════════════════════════
# 1. Um campo:            `var subir := SubirObjeto.new()`
#    e no load da sala:   `subir.carregar_sala(room_id)`   (ou o `world.gd` chama e repassa)
#
# 2. No fim do tick, ANTES de decidir a rotina do próximo quadro (é onde r1/r2 fazem isso):
#        subir.detectar(pos, facing, rotina, pad.pressed(Pad.FWD) or pad.pressed(Pad.BACK))
#        if subir.deve_entrar(rotina) and not subir.ativo:
#            acao = 1 ; rotina = SubirObjeto.ROTINA_SUBIR ; subir.iniciar()
#    (equivale ao `sw 0x901, 4($player)` de `0x800397c4`)
#
# 3. Enquanto `rotina == 9`:
#        subir.avancar(pad.pressed(Pad.FWD) or pad.pressed(Pad.BACK))
#        var c := subir.clipe()      # "anim06" -> "anim07"
#        if c != "": tocar(c)        # senão mantém o clipe de ANDAR (arm00)
#        if subir.sfx_pendente != 0: Sfx.tocar(subir.sfx_pendente)
#        if not subir.ativo: acao = 1 ; rotina = 0     # `player+4 = 1` de `0x8003b4e0`
#
# 4. A altura: no subestado `NO_TOPO` em diante o personagem já está em cima, então o passe de
#    piso tem de aceitar `subir.y_destino()` como Y (senão o `floor_height` puxa de volta).
#    Sugestão mínima: `if subir.ativo and subir.sub >= SubirObjeto.Sub.NO_TOPO:
#        pos.y = subir.y_destino()`.
#
# 5. NOME DO ESTADO: chame de `SUBINDO` no seu enum `Acao`/`Rotina` — mas o valor da ROTINA tem
#    de ser **9**, porque é o índice real de `player+5` e é o que a detecção testa
#    (`ROTINAS_VALIDAS = [1, 9]`, de `0x80036c88..0x80036c9c`).
