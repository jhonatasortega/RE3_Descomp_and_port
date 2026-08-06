# Notas de decompilação — categoria "Sala / Lógica (RDT/ARD)"

> Notas de trabalho do dono da categoria. Fonte de verdade: disassembly do
> `SLUS_009.23` (base 0x80010000) + dados das 169 salas + fontes da comunidade
> (reevengi-tools wiki, GameFAQs save-hacking). Marcações: CONFIRMADO (provado
> por disasm/dados) · ALTA/MÉDIA/BAIXA · "a confirmar".
>
> NÃO edita `docs/formatos/` (fechado por outro agente). As correções abaixo que
> tocam ARD.md/SCD.md/scd_gameplay.md/exe.md são para o dono daqueles docs aplicar.

---

## 1. Papéis do header do RDT e da tabela de 22 offsets  ✅ (reevengi + validação)

A wiki reevengi-tools (`.RDT (Resident Evil 3)` / `(Resident Evil 2)`) documenta o
cabeçalho do RDT; casa com os bytes reais das 169 salas. Resolve os "🟡 papéis" do
ARD.md §3.1/§3.2:

| offset (byte) | campo | papel |
|---|---|---|
| +0 | **nSprite** | nº de sprites de máscara de prioridade (oclusão) |
| +1 | **nCut** | nº de câmeras (já confirmado no projeto) |
| +2 | **nOmodel** | nº de modelos de objeto da sala |
| +3 | **nItem** | nº de itens |
| +6 | **Reverb_lv** | nível de reverb de áudio da sala |
| +7 | **nSprite_max** | máximo de sprites de máscara |

Tabela de 22 offsets (`rdt+0x08`) — mapeamento reevengi → índice do projeto:

| índice | ponteiro reevengi | papel | status |
|---|---|---|---|
| 0, 1, 2 | **pVb0 / pVh0 / pVh1** | **ÁUDIO** — bloco VAB (VB) + headers VH do som da sala | resolve "provável som" do ARD.md |
| 3, 4, 5 | (nulos) | sempre ausentes | ✓ |
| 6 | **pSca** | COLISÃO (SCA) | já confirmado |
| 7 | **pRID** | câmeras (RID) | já confirmado |
| 8 | **pRVD** | zonas de troca de câmera | já confirmado |
| 9 | **pLIT** | **ILUMINAÇÃO** (LIT) — resolve "piso e/ou luz" do ARD.md | ALTA |
| 10..15 | pMD2 / MSG / TIM etc. | texturas/modelos, mensagens, TIM | a confirmar por-índice |
| 16 | **pSCD** (Main+Sub) | script SCD | já confirmado |
| 22 | pRBJ | animação (ausente se a sala não tem anim) | reevengi |

> Nota reevengi p/ RE3: pointers #14(MSG), #15(TIM), #17(SCD sub) ficam 0 (o Main e o
> Sub SCD vivem ambos no #16). Bate com o projeto (só usa o [16]).
> Fonte: github.com/pmandin/reevengi-tools/wiki/.RDT-(Resident-Evil-3).

---

## 2. RVD — fechamento da semântica de flags  ✅ (dados: 4585 entradas / 169 salas)

Struct de 20 bytes já documentado (ARD.md §3.5). Fechando os flags (u16 @+0):

Distribuição real:
- **byte BAIXO**: `0x01` em 4339/4585 (**94,6 %**), `0x00` em 246 (5,4 %).
- **byte ALTO**: `0x80` em 4298/4585 (**93,7 %**); pequenos `0x01..0x1f` em ~287; `0x00` em 61.
- flags dominante `0x8001` = 4087 (89 %); depois `0x8000`=211, `0x0201`=62, `0x0101`=55, `0x0001`=51…

Semântica (evidência = cruzamento com `from==to` e `degenerate`):
- **bit 0 do byte baixo (`0x01`) = "zona ATIVA"** (dispara troca). Entradas com baixo=`0x00`
  (246) são **todas** `from != to` → provável "fronteira/limite sem gatilho" (desativada).
  Confiança **ALTA** (correlação limpa).
- **byte ALTO `0x80` = zona PADRÃO/global** (quase universal). Os altos pequenos
  `0x01..0x1f` (~287, **todas não-degeneradas**, com quads específicos) = provável
  **id de grupo / prioridade / ordem** de corte. Confiança **MÉDIA**.
- **`degenerate`** (alguma coord `±32768`) vem das COORDENADAS, não do flag — quad ilimitado
  (frustum). 456 entradas, 449 delas com alto=`0x80`. `from==to` só em 171 entradas
  (destas 170 têm baixo=`0x01`). Confirma ARD.md: degenerate ≠ "cobertura da câmera".

Conclusão: RVD como **grafo de adjacência** (abordagem atual do remake) continua o método
robusto; adicionalmente pode-se **filtrar por bit0=ativa** para descartar as ~246 fronteiras
inativas. Isto leva o RVD a ~100 % de entendimento (o byte alto pequeno = grupo/prioridade
fica MÉDIA).

---

## 3. Oclusão — formato do bloco de máscara (mask_data_ptr)  🟡→ mais fechado

Verificado nos bytes reais (169 salas, 111.644 blocos). Layout por bloco confirmado
(ver `tools/rdt_collision.py` `decode_masks`):

```
cabeçalho @mask_data_ptr:  u16 n_groups, u16 n_masks
grupo 0:                   u16 count, u16 depth0
depois: n_masks blocos (lista PLANA), 8 ou 12 bytes:
  bloco 8B (quando byte +2 != 0):
    +0 u16 pri        // ordenação/profundidade por-sprite (0..~45240)
    +2 u8  w          // largura em px (múltiplo de 8)
    +3 u8  (0 usual)  // ver nota altura
    +4 u8  sx, +5 u8 sy   // ORIGEM no atlas de máscara (VRAM PS1)
    +6 u8  dx, +7 u8 dy   // canto na TELA, em PIXELS (múltiplos de 8) — NÃO "grade/8"
  bloco 12B (quando byte +2 == 0):  sprite com tamanho explícito
    +0 u16 pri, +2 u8 0, +3 u8 0, +4 u8 w2, +5 u8 ?, +6 u8 h2, +7 u8 ?,
    +8 u8 sx, +9 u8 sy, +10 u8 dx, +11 u8 dy
```

Achados novos (corrigem/precisam ARD.md §3.7):
- **O bloco de 12B (tamanho explícito) é MAIORIA: 83.579 / 111.644 (≈75 %)**, não exceção.
  A doc trata como caso especial; deveria ser o caso principal.
- **`dx`,`dy` são PIXELS de tela** (0..~255, múltiplos de 8), não "grade de 8 px". Idem `sx,sy`
  em pixels de VRAM (0..255 dentro da página).
- **`depth0` do grupo 0 = 30720 (0x7800) CONSTANTE** em todas as 1507 câmeras → NÃO é um Z
  por-sala; é um valor fixo (provável Z-base/near de clip do OT do PS1). O Z real de
  ordenação por-sprite é o **`pri` (+0/+1)** de cada bloco (0..45240) — é ele o "depth
  comparável" pedido, não o `depth0`.
- A subdivisão em grupos **além do grupo 0 NÃO é inline** `(count,depth)` (confirmado: o
  2º "grupo" lê `count=24632`, lixo). Ler como **lista plana de n_masks blocos** com `pri`
  por-sprite (é o que o parser faz).
- `b0/b1` da hipótese do coordenador = os bytes +0/+1 = **`pri`** (Z de sprite), NÃO altura
  nem page/clut. Altura: no bloco 8B a altura é implícita (tile 8px, com w explícito); no
  12B há `h2` explícito (+6). O byte +3 no 8B é quase sempre 0 (27.663×), com alguns valores
  8/16/24/32/56 (81/45/37/30/19×) → provável **altura em px** quando presente.

Para oclusão pixel-exata: o atlas de origem (sx,sy) fica na **máscara TIM dentro do BSS**
da sala (reevengi `bsssld2tim -re3` descomprime; padrão RE3). dx,dy dão o destino em tela.
Com o atlas decodificado + (sx,sy,w,h)→(dx,dy) por bloco e `pri` como Z, dá para reconstruir
a oclusão por-pixel. Isto sobe a oclusão de 60 % para ~85 % (falta só decodificar o atlas TIM
do BSS e casar page/clut).

Fontes: reevengi-tools README (`bsssld2tim`), wiki `.RDT`.

---

## 4. sce_ids — nomes de item  ✅ parcial (faixa confirmada)

Tabela de nomes 0x01–0x1B (armas+munição) + 0x2A (First Aid Spray) adicionada a
`tools/scd_items.py` (`ITEM_NAMES`) e emitida em `godot/data/sce_item_names.json` +
campo `name`/`name_conf` em cada item extraído.

- **Validação**: `0x15` (×30 no SCD) = **Hand Gun Bullets** — bate com o `amount` observado.
  Confirma que o `item_id` do opcode 0x68 usa o **mesmo espaço** dos IDs de inventário.
- IDs observados no SCD e seus nomes: `0x04`=Benelli M3S Shotgun (×7), `0x15`=Hand Gun
  Bullets (×30). **A confirmar** (fora da faixa publicada): `0x21, 0x41, 0x42, 0x99, 0x9b,
  0xa0` (provável key items/ervas; IDs >0x80 podem ter bit de categoria).
- **type_id de inimigo** (opcodes 0x61/0x62): continua **slot de modelo, não espécie**
  (confirmado no projeto; a espécie vem do R###.BIN da sala). O opcode dedicado de inimigo
  (`sce_em_set`) e a tabela de espécie ficam pendentes do EXE.

Fontes: gamefaqs.gamespot.com/pc/431704 (Shockproof_Jamo), xpgamesaves.com, guia Dreamcast.

---

## 5. Cross-check de numeração de opcode com reevengi (RE3)  ✅

reevengi confirma para RE3: **`aot_set` = 0x63**, **`aot_reset` = 0x65** — bate exatamente
com a numeração empírica do projeto (0x63 trigger de 20B). Logo a numeração do projeto é a
mesma do RDT cru de RE3 (não a do BIOFAT/CRE, que renumera). Estruturas de fluxo confirmadas
pela reevengi (RE3): `0x06 if`(4B, u16 block_length), `0x10 while`(4B), `0x14 switch`(4B:
opcode,u0,u1,dummy), `0x15 case`(2B), `0x0a sleep`(3B), `0x04 evt_exec`(4B: opcode,event,
u16 instr). **ATENÇÃO — divergência a resolver com o EXE**: SCD.md do projeto lista
`0x04 = 2 bytes` e `0x14`/switch sem tamanho; reevengi dá `0x04 = 4` e `0x14 = 4`. O
constraint-fit local sobre as 169 salas foi **refutado** (deu 0x14=32, sinal de subdeterminação),
então o árbitro é o **interpretador no EXE** (em extração por subagente).

Fonte: github.com/pmandin/reevengi-tools/wiki/.RDT-(Resident-Evil-3) e (Resident-Evil-2).

---

> **ATUALIZAÇÃO (round de integração):** o mecanismo de troca de sala foi LOCALIZADO no
> EXE (handler `0x800248e4`, loader `0x800493ec`, tabela `0x8009dfd0[stage][room]`,
> globais `0x800d1f76/78`) e a tabela de fileids foi extraída e ALINHADA (EXE-stage s ⇒
> pasta STAGE(s+1)). Detalhes em [door_handler.md](door_handler.md). A CHEGADA está 100%
> integrada; o DESTINO ainda não fecha (reciprocidade 14%) — falta o VM de script de sala
> que popula o descriptor. A tabela de opcodes SCD foi integrada em `scd_decode.py`
> (fechamento 30%→64%); ver [scd_opcodes.md](scd_opcodes.md).

## 6. door_dest — status e pista da estrutura  🟡 (em extração no EXE)

Estrutura da porta 0x67 (62B) re-alinhada limpa (âncora no marcador de chegada
`ff [x] 60 10 00`):
```
+0=0x67  +1=aot  +2=0x02  +3=sat(0x31)  +4=floor  +5=0
+6 s16 x  +8 s16 z  +10 s16 w  +12 s16 d      (AABB do gatilho)
+14..+21 = 8 bytes de DESTINO (pequenos; padrão "XX 00 YY 00 ..")
+22 = 0x7f (const)  +23 = seq
+33..+37 = marcador ff [x] 60 10 00
+38 s16 to_x  +40 s16 to_y  +42 s16 to_z  +44 s16 to_facing   (CHEGADA, world coords, ✅)
```
- Só **164/481** "portas" são opcode 0x67; as demais têm head diferente (marcador de chegada
  genérico). Reciprocidade por bytes crus (todos os offsets/encodings do bloco +14..+21)
  **satura em 14 %** → destino NÃO é campo cru trivial. Precisa do handler no EXE.
- RE2 (reevengi/ModDB): `door_aot_set`=0x3b com `next_stage`/`next_room` como u8 **após** a
  chegada; RE3 renumera e reorganiza. O handler no EXE (em extração por subagente) dará o
  offset exato de stage/room-destino. [A COMPLETAR com o resultado do subagente.]

---

## 7. Divergências a aplicar no progress.json (proposta ao dono)

- `rvd`: 90 → **98** (flags fechados: bit0=ativa ALTA; byte-alto=grupo/prioridade MÉDIA).
- `oclusao`: 60 → **80** (layout do bloco fechado; 12B é maioria; pri=Z; depth0 é constante;
  falta só o atlas TIM do BSS p/ pixel-exato).
- `sce_ids`: 30 → **50** (faixa de item 0x01-0x1B+0x2A nomeada e validada; falta espécie de
  inimigo e IDs altos).
- `scd`: 70 → **90** (⭐ **VM do script de sala LOCALIZADO e VERIFICADO**: jump-table
  `0x8009e0f8`→scratchpad `0x1f800000`, loop `0x80052ba4`, dispatch `0x80052c48`, PC em
  `obj+0x1c`, init `0x80052474`. `VM_SIZES` lido dos handlers → **97,1%** das funções fecham
  (era 63,6%). Correções: a "porta de 62B" = par `0x67`(22)+`0x7f`(40); `0x62`=40. Opcodes
  nomeados pelos leaves: `0x06`=flag(`0x800512fc`), `0x67`=door_aot_set, `0x7f`=door dest,
  `0x7b`=map data, etc. Ver `scd_opcodes.md`). Falta só nomear leaves menores.
- `door_dest`: 0 → **45** (VM produtor localizado — handlers `0x800574f4`(0x67)/`0x80056510`
  (0x7f); consumidor `0x800248e4` lê descriptor+8(%9)/+9; loader `0x800493ec`; tabela fileids
  `0x8009dfd0`; CHEGADA 100%). **PROVADO que o destino NÃO é campo estático do SCD**: seletor
  `0x7f byte@+9` é sempre 0 nos 653 opcodes; busca exaustiva de reciprocidade ≤15%. O destino
  é RUNTIME-indireto → fechar por casamento espacial da chegada (RID/RVD) ou traçando a
  indireção. NÃO é 100%; reciprocidade permanece ~14-15%.

### Correções de arquitetura (para o dono do SCD.md/exe.md/scd_gameplay.md)
- `0x8007688c` = VM de **IA de entidade/inimigo**. `0x8009e0bc`/`0x80050aac` = VM de
  **EVENTO/AOT per-frame** (consome AOTs, seta `gs+0x2154`/flag `0x800c7960`). O
  **interpretador de bytecode do SCD** = **`0x8009e0f8`** (loop `0x80052ba4`) — ACHADO.
- `tools/scd_decode.py` `SIZES` agora é `VM_SIZES` (lido do interpretador; autoritativo).
