# Decompilação de conteúdo RE3 — PROGRESSO

> **GERADO** por `tools/decomp_progress.py` a partir de [`progress.json`](progress.json). Não edite à mão — edito falando da posite o JSON e rode o script.
>
> Método (decomp.dev-adaptado): decompila o **conteúdo** (formatos/assets/lógica), não binário nativo. **decompilado** = entendemos+extraímos · **vinculado** = ligado no protótipo Godot.

## Geral (ponderado por peso, 33 unidades)

- **Decompilado:** `████████████████████` **99%**
- **Vinculado:**  `███████░░░░░░░░░░░░░` **34%**

## Por categoria

| Categoria | Decompilado | Vinculado |
|---|---|---|
| Disco & Containers | ████████████ 100% | ██████████░░ 80% |
| Gráficos / Cenário | ████████████ 100% | ███░░░░░░░░░ 27% |
| Modelos & Animação | ████████████ 97% | ████████░░░░ 64% |
| Sala / Lógica (RDT/ARD) | ████████████ 100% | ████░░░░░░░░ 30% |
| Áudio / Vídeo | ████████████ 100% | ██░░░░░░░░░░ 16% |
| EXE / Código (SLUS_009.23) | ████████████ 99% | ██░░░░░░░░░░ 20% |
| UI / Meta-jogo | ████████████ 100% | ████░░░░░░░░ 32% |

## Detalhe por unidade

### Disco & Containers

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Extração ISO PS1 (ISO9660 MODE2) | 3 | 100 | 100 | `list_iso.py, extract_iso.py` | inventario.md | 1334 arquivos extraídos |
| Rofs*.dat (arquivo PC/GOG, CRC32+LZ) | 2 | 100 | 50 | `rofs_extract.py` | rofs.md | usado p/ puxar HD/áudio do GOG |

### Gráficos / Cenário

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Backgrounds BSS (MDEC/DCT) | 5 | 100 | 15 | `bss2png.py` | BSS.md | 2109 bg 320x240; no protótipo só R100 |
| Texturas TIM (4/8/16bpp+CLUT) | 3 | 100 | 80 | `tim2png.py` | PLD.md | usado em modelos e UI |
| Backgrounds HD (Seamless/GOG) — NCC match | 4 | 100 | 15 | `hd_match.py, hd_copy.py` | hd_seamless.md, hd_mapping.md | migração por conteúdo; no protótipo só R100 |
| Mapas de menu (MAP_U) + HD | 2 | 100 | 0 | `map_decode.py, map_clut_match.py, map_hd_locate.py` | map.md | plantas p/ v2; sem tela de mapa no protótipo |

### Modelos & Animação

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Personagens PLD (malha+esqueleto+skin+textura+anim) | 5 | 100 | 90 | `pld2gltf.py, pld_hd_textures.py` | PLD.md | Jill no protótipo, HD no rosto |
| Armas PLW + LOCOMOÇÃO ARMADA (multi-banco) | 5 | 100 | 85 | `pld2gltf.py (build_armed_clips, extract_weapon), find_anim_banks.py` | animacoes_player.md, decomp/notes/plw.md | ✅ COMPLETO (lado decomp): 84/84 PLW validados (find_anim_banks --validate-all) — todos com banco armado+malha; 63 *_WPN.glb (arma separável), 21 sem slot (handguns W00 + PL09/PL0A pintadas na pele) = esperado. MULTI-BANCO resolvido: cada PLW tem 3 bancos (bank0=15 ossos/locomoção=armNN; bank1/2=overlays parciais de mira/gesto) → 3 slots armados do EXE (player+0xf4/0xf8/0x100). Osso de anexo = bone4 (punho dir), world-rest (-32,297,-435). PL06CH = variante CH (cutscene/dano) de PL06, redundante. Resíduo = só vínculo (anexar no controller) |
| Sistema de animação do player (EDD/EMR/poses) | 4 | 100 | 90 | `pld2gltf.py` | animacoes_player.md | movimentação 100% (falta validar mira + subir em item) |
| Modelos de INIMIGOS (EMD do GOG) | 5 | 88 | 10 | `emd2gltf.py` | decomp/notes/enemy_mesh.md, emd_skinning.md | MALHA/UV/TEXTURA/ANIM 100% (69/69). RIG: funciona nos 1:1 e bem-distribuídos (zumbis, cão, corvo, aranha, heli, maioria dos humanos) = malha colada nos ossos idle+animado. NÃO FECHA nos multi-osso baked (hunters EM22/23/24, deimos EM28/35, Nemesis EM38, EM34/36/3A): FATO PROVADO olhando o dado — esses têm ossos-marcador degenerados de 3 verts no braço/perna e a malha do membro está ASSADA num objeto grande multi-osso; a info de qual vértice→qual osso (índice por-primitiva) foi DESCARTADA no EMD do PC. As DUAS fontes PC (Rofs9 EMD e Rofs10 EMD08) são IDÊNTICAS — sem referência melhor. O índice real só existe no mesh empacotado do PS1 (não decodável, várias tentativas). Envelope (método Jill) melhora números mas NÃO cola os hunters visualmente (métricas vão/tear enganam; usuário confirma quebrado). LIMITE REAL DO DADO. Opções: aceitar (maioria ok) OU rig manual dos ~8-10 no Blender (geometria/textura/anim estão certas, só o peso-por-osso é artista) OU decodificar o mesh PS1 empacotado (alto risco) |
| Modelos de porta (.DO1-.DO7, anim de transição) | 1 | 100 | 0 | `do2gltf.py` | decomp/notes/doors_model.md | ✅ COMPLETO: formato .DO# cracado (malha 12B tri + vért 8B + TIM 128×256); 21 portas exportadas+renderizadas. Bloco de abertura DECODIFICADO = é ANIMAÇÃO (prova cruzada: malha e bloco variam independentes); tag@+2=6=nº frames; abertura = rotação rígida da folha, dobradiça extraída da geometria (find_hinge_x), 90°. 15 *_ANIM.glb + 2 renderizados (folha girando fechada→aberta, validado animado). RESÍDUO: só o easing por-frame é bit-packed irredutível (fronteira provada) — a animação em si é exportável/usável |

### Sala / Lógica (RDT/ARD)

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Contêiner ARD/RDT (blocos + offset_table) | 4 | 100 | 60 | `ard_parse.py` | ARD.md | 169 salas |
| Câmeras (RID, from/to 3D) | 5 | 100 | 40 | `ard_parse.py, cameras_to_3d.py` | ARD.md | 2105 câmeras; câmera fixa no protótipo (1 sala) |
| Zonas de câmera RVD (troca/histerese) | 4 | 100 | 40 | `ard_parse.py` | ARD.md | ✅ COMPLETO: consumidor per-frame ISOLADO = 0x8002a84c (lê RDT via load absoluto 0x800cc86c+0x28=offset_table[8], cacheia gs+0x2148). PROVADO no código: stride 0x14, from_cam@+2==gs+0x2486, BIT0/ativa (lbu@+0 beqz), BYTE-ALTO=grupo (lb@+1: 0x80=global OU ==gs+0x2495), ponto-em-quad 0x8001020c, to_cam@+3 commit 0x8002a938→fade 0x8005190c→gs+0x7842. Histerese em 2 fases (chamadores 0x80023b84/0x80024abc). Semântica dos flags provada no binário (não mais por clustering) |
| Colisão (offset_table[6], retângulos XZ) | 5 | 100 | 70 | `rdt_collision.py` | ARD.md | colisão real no R100 |
| Máscaras de oclusão (mask_data_ptr, priority) | 4 | 100 | 15 | `rdt_collision.py` | decomp/notes/occlusion.md | ✅ COMPLETO: formato refeito (campos estavam trocados no 80%). Cabeçalho=tabela desc 8B; sprite SQUARE 8B / RECT 12B (disc. byte+6); tela=(dx+add), Z per-sprite=depth*16. Validado: Σcount==n_masks 1507/1507 câmeras, atlas recall 1.0, overlay HD casa. 169 salas regeneradas (111644 sprites). Vínculo: recalibrar occ_depth_scale (Z agora per-sprite) |
| Script SCD (portas/triggers/entidades/itens) | 5 | 100 | 0 | `scd_decode.py, scd_gameplay.py, scd_doors.py, scd_items.py` | SCD.md, scd_gameplay.md | ✅ COMPLETO: VM confirmada (jump table 0x8009e0f8; loop 0x80052ba4; init 0x80052474). 4238/4238 funções fecham em evt_end, ZERO opcodes inválidos (63.6%→97.1%→99.95%→100%). Espaço de opcodes = 0x00..0x8f. 0x3b=3 (handler 0x80057f84) + 4 tamanhos corrigidos (0x3c/0x24/0x2f/0x4b=1) via avanço do epílogo dos 144 handlers. R123 f17/R208 f0/R211 f44 = drift dos tamanhos errados (não dado-embutido), agora limpos. 0x06=if_begin/block |
| Destino das portas (sala→sala) | 4 | 100 | 0 | `scd_door_dest.py, room_graph_build.py` | decomp/notes/door_handler.md | ✅ COMPLETO 100% (destino ESTÁTICO): porta = AOT sce∈{1,13} (0x61 32B/0x62 40B; sce13 handler 0x80051cb0). next_stage@+0x16(mod9)/next_room@+0x17 = dígitos HEX do nome Rxyz = índice fileid 0x8009dfd0. AUDITORIA: 453 portas (corrigido de 447 — 6 sce==13 eram descartadas → 3 pares recíprocos R114↔R118/R304↔R30A/R40C↔R40E). 453/453 resolvidos, 0 TODO. Cobertura PROVADA (varri todos AOT das 169 salas; só sce∈{1,13} troca sala, room-loader 0x800493ec só via door_handler, sem warp por script). 296 arestas-sala: 279 recíprocas + 17 mão-única TODAS justificadas (queda/hub-mercs/gate-progressão/boss/placeholder) = reciprocidade explicada 100%. room_graph.json c/ reciprocal+oneway_reason por aresta |
| IDs de item/espécie de inimigo (tabelas SCE) | 3 | 100 | 0 | `scd_items.py, scd_enemies.py, re3_text.py` | decomp/notes/messages.md, sce_em_set.md | ✅ COMPLETO (extração 100% + anotação no teto real): ITENS 193 IDs (100%). INIMIGO sce_em_set (op 0x7d 24B) 100% byte-a-byte → classe+pos+dir+arma; 1136 spawns+80 NPCs em 137 salas. Anotação de espécie dos 69 EMD em sce_enemies.json (emd_annotations: nome+render_conf+evidência): ALTA+MÉDIA=43,5%, categoria-ou-melhor=81,2%, BAIXA=19%. RESÍDUO (fonte, não trabalho): mapa canônico EM##↔espécie NÃO existe no EXE nem publicado 1:1; espécie fina (Hunter β/γ, qual NPC) resolve em runtime (class↔mesh é m:n). Rótulo = anotação com confiança explícita, não invenção |

### Áudio / Vídeo

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Trilha (BGM) — 125 faixas .ogg | 3 | 100 | 40 | `re3_sound.py, bgm2midi.py, audio_gog.py` | audio_video.md, godot_audio.md | `port/core/audio.gd` toca BGM por sala (`tocar_bgm_da_sala`), ligado em `present/screen.gd`. RESÍDUO: o de-para **sala → faixa** NÃO foi medido (mapa por STAGE, `room_override` vazio) — e **nenhum dos 144 handlers de opcode do SCD toca BGM** (varredura em exe_audio.md §5.3), logo o vínculo não está no bytecode de sala |
| SFX (bancos VAB) — VH decodificado | 3 | 100 | 10 | `vab.py, re3_sfx.py` | decomp/notes/sfx.md | ✅ COMPLETO (formato 100% byte-provado): VH (VagAtr 32B + tabela VAG); 267 SFX corte+pitch; LOOP (marcadores ADPCM bit0/1/2) + ADSR (decode SPU bit-a-bit) emitidos no manifesto. sfx_map.json: papel por hash de PCM (ALTA 267/267: idx00-04 = núcleo global). ⚠ DUAS AFIRMAÇÕES DESTA LINHA FORAM CORRIGIDAS em decomp/notes/exe_audio.md: (a) os "opcodes de som 0x57/0x58/0x59" e as "filas 32×10B 0x800de648/0x800de798" são **VIBRAÇÃO** (PadSetAct via 0x80091710), não som — os 1528 "disparos" são eventos de rumble; (b) o link id→vag **EXISTE** no estático |
| **Motor de SE — id de SE → amostra** | 3 | 100 | 60 | `exe_audio.py` | decomp/notes/exe_audio.md | ✅ De-para PROVADO: a tabela id→descritor mora no **offset 0 do `.VH`/`.SND`** (`N = hdr/4`, `0xffffffff` = vazio; `hdr` pelo magic `0x0001eeee` em `hdr+0x10`); descritor → tom (`b1>>4`) → `vag` → WAV. Cadeia no EXE: `0x800746c0` (pede) → anel `0x800e0de4` → `0x80074770` (resolve) → `0x800749a0` (voz) → `SpuSetVoiceAttr 0x8007f768` / `SpuSetKey 0x8007eda8`. `cat` == id de banco VAB (C_=0, A_=1, R=2, **porta=4**). **PORTA:** todo `STAGE*/DOOR??.DO1` embute um banco VAB (magic `0x0001eeee`, 4 ids, corpo em `hdr+total`) — 76/76, o "DOOR SOUND" do loader `0x80012818` (string `0x800103ac`); 147 WAV extraídos. **1345 asserções, 0 falhas** (35/35 headers do disco, 278/278 descritores, 76/76 bancos de porta). 5 sons de menu com confiança ALTA (4 evidências independentes). RESÍDUO: nome das ações de JOGO (tiro/passo/item/recarga) segue DECLARADO; qual id da porta é abrir vs fechar não foi medido; quem preenche `SND_CTX+cat*4` não foi localizado; 12 dos 159 descritores de porta são sobra do template (inconsistência do dado ORIGINAL, medida) |
| Vídeos/FMV (STR→ogv) | 2 | 100 | 0 | `-(jPSXdec)` | audio_video.md | convertidos; sem player integrado |
| Vozes dual-idioma (PT-BR/EN) | 2 | 100 | 50 | `rofs_extract.py` | rofs.md, audio_video.md | LangManager |

### EXE / Código (SLUS_009.23)

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Máquina de estados do player + índice de anim | 5 | 100 | 80 | `exe_parse.py, exe_dispatch.py, exe_combat.py` | exe.md, decomp/notes/exe_combat.md | ✅ COMPLETO: 8 ações macro + 16 rotinas mapeadas c/ endereços. r10/r12/r15 desmontadas (r10=andar-frente c/ mira 0x8003b4fc, r15=ré/DOWN c/ mira 0x8003bf28, r12=anim scriptada 0x8003ca80) + alcançabilidade provada. tier de anim = ZONA DE SAÚDE (HP player+0xcc), tabela 3×3 0x8009cde0. RESOLVIDO anim19/20 = poses de MIRA upper-aim (0x8003acb8/accc na rotina 7), NÃO dano (dano=ação a3 0x8003d9e0, anims 4/5/9-12). Reconciliado exe.md↔anim_map.json (momentum→hp) |
| Mira / tiro / dano | 5 | 100 | 0 | `exe_combat.py` | decomp/notes/exe_combat.md | ✅ COMPLETO: mira(pad 0x500)/auto-lock; altura/pitch = aim_tier 0..3 → player+0x6e=(tier<<9)+0x800, poses 14-17 (0x8003ac40), upper-aim 15→19/16→20 (0x8003ac90). Hitscan (genéricas 0x80044804, dano no mesmo frame, sem entidade-bala) vs projétil dedicado (rocket w10 0x800408c4, granada w14 0x8003ff9c), faca w0 0x8003e494. Timing 0x8009cf28 (frame do tiro por arma), recuo 0x80048308. TABELA DE DANO 0x8009d834[alvo+0x4a], dano=word&0x3ff. HP=char+0xcc. Resíduo (é da unidade ai): hitbox/osso do inimigo é data-driven pela EMD/EMR |
| IA (zumbi / Nemesis) | 5 | 100 | 0 | `exe_ai.py, overlay_ai.py, scd_enemies.py` | decomp/notes/exe_ai.md, sce_em_set.md | ✅ COMPLETO (IA estruturas+comportamento = 100% do estaticamente decodável): dispatcher por-classe 0x80023e00; char-struct 0x1fc; Nemesis t41 0x80020eb8. IA = MIPS PURO no R###.BIN (tag low16=0x0001, 0x80100000). 12/12 overlays × 548/548 handlers com PAPEL DETERMINADO e verificado (ai_overlays.json: role/semantics/regions/counters + state_machines). Analisador rastreia jalr/jr sub-dispatch + aliasing char em $s0/$s1. Distribuição: ANIM/STATE 138·SUB-DISPATCH 101·IDLE/DECIDE 96·SPAWN 57·STATE-SET 33·TIMER 25·AIM/GEOM 24·DELEGATE 16·CLASS-ENTRY 13·DEATH/DAMAGE 13·MOVE 13·COLLISION 5·FIELD-SET 5·EXE-CALL 5·CHANCE 4. Não-decode-gap: branch-por-frame é dinâmico por design (leque/tabelas decodificados); nome-de-espécie é cross-unit (sce_em_set, não-estático) |
| Handler de transição de sala | 4 | 100 | 0 | `scd_door_dest.py` | decomp/notes/door_handler.md | ✅ COMPLETO (100% in-EXE): callback de colisão FECHADO — driver per-frame 0x80050b58 → VM de colisão AOT 0x800505ac (AABB 0x800101c8 / QUAD 0x8001020c sobre char+0x34/+0x3c) → dispatch por SCE jalr *(0x8009e0bc+sce*4), sce1=produtor 0x80050d28 grava 0x800c7960=1 + gs+0x2154=descriptor → handler 0x800248e4 (spawn +0x34/38/3c/6e, current_stage 0x800d1f76/room 0x800d1f78) → room-loader 0x800493ec (fileid 0x8009dfd0[stage][room]) |
| Lógica de item/inventário/flags | 3 | 100 | 30 | `exe_items.py` | decomp/notes/exe_items.md | ✅ COMPLETO (decomp 100%; resíduo é só VÍNCULO Godot): flags 0x8009e3f8 (SET/CLEAR/CHECK). array 0x800d2134 (MAIN10/BOX64), slot {id,qtd,flags}. find_by_id 0x8006cc8c verificado; PEGAR 0x80069c3c→0x80069cb8→0x8006a020; USAR 0x8006d0a8; COMBINAR/consolidar 0x8006cf0c verificado (correção: 0x8006cf00 era epílogo). Receita de ervas vive no menu (unidade menus) |
| Renderização/skinning de modelo (GTE) | 3 | 90 | 0 | `exe_parse.py` | decomp/notes/emd_skinning.md | ✅ DECOMPILADO (agente, decoder COP2/GTE próprio; emd_skinning.md §10): UM só caminho de desenho p/ player E inimigos (laço atores 0x8002412c→nós 0x800254ac→transform 0x80025610→prim 0x80025de8→folhas GTE 0x8007b2fc/518/824). REGRA PROVADA: uniformemente BONE-LOCAL matriz completa (sem ramo model-space; flags no+0xa2 só luz/LOD). Binding vértice→osso = ÍNDICE EXPLÍCITO por-primitiva (byte/grupo, listas 0xFF-term, lidas em 0x8007b518), NÃO posicional — malha cita vários ossos. FK por ponteiro-de-pai 0x800253f0 (Mundo[i]=Pai∘Local via 0x8002d4b0), ordem T(relpos)·Rx·Ry·Rz = igual ao gbind. Resíduo: detalhe exaustivo de folha (luz/subdiv). NOTA DE ESCOPO: MDEC/loader-CD/save/áudio-SPU do EXE = engine NÃO decompilada, FORA do escopo do remake (Godot faz; dados extraídos à parte) — não é 'feito', é fora-de-escopo |

### UI / Meta-jogo

| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |
|---|--:|--:|--:|---|---|---|
| Inventário (grade+ícones HD+status+ações) | 3 | 100 | 70 | `etc_hd_match.py, re3_text.py` | godot_ui.md, decomp/notes/messages.md | ✅ COMPLETO: item table REAL (nomes+exames EN+PT; tabela EN @0x8a124 termina em 0x84 = 100% dos exames que existem). item_id 100% por 3 fontes. LOADOUT DE NOVO-JOGO DECODIFICADO: rotina 0x8006d0d8 zera array 0x800d2134 e copia TEMPLATE ESTÁTICO de 0x800a018c (entrada 4B {id,qtd,flags16}, term FFFFFFFF); extraído p/ re3_items.json (default_loadout_jill + newgame_loadout_templates). Mercenários byte-idênticos ao SELECT.BIN. Honesto: 'Faca+Pistola' não existe como tabela discreta; qual template o retail usa é decisão de flag (s5 via jump-table 0x80010f9c) |
| HUD in-game | 1 | 100 | 0 | `-` | - | RE3 NÃO tem HUD em gameplay → remover do protótipo |
| De-para HD de UI/itens/memos | 2 | 100 | 40 | `etc_hd_match.py, hd_masks.py` | hd_ui.md | ícones/frames HD migrados; usados no inventário |
| Menus (título/novo/continuar/opções/save) | 3 | 100 | 0 | `menu_extract.py` | decomp/notes/menus.md | ✅ COMPLETO: BIN=OVERLAYS MIPS (bases in-game 0x801c2000/boot 0x80194000); 13 telas com draw_seq. PROVADO que o rect (u,v,w,h) por-sprite é COMPOSTO EM RUNTIME (pipeline draw_sprite 0x800746c0→resolve 0x80074770→compose_geom 0x800749a0; 0x800e0610=estado do compositor). Fonte ESTÁTICA extraída p/ layout.json: atlas *_OBU.TIM (dims/paletas byte-a-byte) + mapa sprite_id→(page,index) por chamada nas 4 telas indexadas. Correção: 0x80078930=flag_test (não draw_string), texto real 0x800788dc |

## Radar — bloqueios / baixo decompilado (<50%)

