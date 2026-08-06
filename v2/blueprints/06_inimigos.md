# 06 · Inimigos (`STAGE#/R###.BIN` + EMD do GOG)

> Fonte: [`../../docs/formatos/enemy_bin.md`](../../docs/formatos/enemy_bin.md),
> [`../../docs/decomp/notes/enemy_mesh.md`](../../docs/decomp/notes/enemy_mesh.md) (malha/rig/render),
> [`../../docs/decomp/notes/exe_ai.md`](../../docs/decomp/notes/exe_ai.md) (IA) e
> [`../../docs/decomp/notes/sce_em_set.md`](../../docs/decomp/notes/sce_em_set.md) (spawn/espécie).
> Ferramentas: `tools/emd2gltf.py` → `godot/assets/ENEMY/*.glb` · `tools/overlay_ai.py` (IA).

## Onde estão

Os `.PLD` são **só humanos** (players/NPCs). **Zumbis, cães, aranhas, Nemesis etc. são
carregados por sala**, embutidos no contêiner `R###.BIN` de cada sala (validado em 122 salas).
O modelo empacotado in-RAM do PS1 **deixou de ser bloqueante**: a fonte limpa é o **port de PC
(GOG)**, onde os inimigos estão como `.EMD` standalone (`emd3.h` do reevengi) em `Rofs9.dat`
(`ROOM/EMD`, 69 EMD+TIM). O esqueleto/anim do EMD são **idênticos** aos do PS1.

## Estado da RE (unidade `enemy` — decompilado 85%)

| Parte | Estado |
|---|---|
| Contêiner `R###.BIN` + manifesto de blocos | ✅ (122 salas) |
| Sub-contêiner do modelo (8 seções) / malha in-RAM PS1 | 🟡 histórico (não decodificada, **não mais bloqueante**) |
| **EMD standalone do GOG → `.glb`** (malha+UV+textura+esqueleto+anim) | ✅ **69/69 exportados** |
| **EMR** (esqueleto) | ✅ 10–22 ossos por espécie (o humano/zumbi = 15, igual ao PLD) |
| **EDD** (animação) | ✅ clips por espécie (anims em 61/69) |
| **TIM** (textura) | ✅ 8bpp+CLUT — `tx=(page>>6)&3`, `pal=clutid&0x3F` |

**Extração:** `python tools/emd2gltf.py batch <GOG_EMD_dir> godot/assets/ENEMY` → 69/69 exportados,
0 anomalias, 0 zero-face. Cada `.glb` traz malha, UV, textura, esqueleto e animação do próprio EMD
(autossuficiente — dispensa `--ps1`).

## Rig — FIX grande, com resíduo honesto

O rig teve uma correção de fundo: **`inverseBind = G_bind⁻¹` (matriz completa, com rotação)** em
vez de `T(−world)` translação-only — isso **matou o "splay" grosseiro** dos membros. Prova: o
**zumbi macho (EM10, 15 ossos)** fica com vão ≈ o baseline do rig limpo (rig_check `PL00≈0,002`);
não é diferença sistemática. Fixes acessórios: `move_offset`/`frame_size` lidos do cabeçalho do
skel (não mais `176/76` fixos → matou o "fly-away" 10–29× nos modelos de N≠15 ossos); rotação de
**repouso = pose0** (hunters/deimos deixam de espalhar parados); variante de formato com **flags
no u16 alto** (EM16/EM1E/EM25/EM2D) recuperada.

**Resíduo honesto (não fecha 100%):** algumas **partes autoradas em MODEL-SPACE** (pés/mãos/braços
de alguns modelos) ainda são tratadas por **heurística** (`_is_model_space`) e não por
extração exata — sobra descolamento residual em **hunters** (EM22 braço≈0,18, EM24≈0,19) e no
**pé-chain do EM2E≈0,16**. Dois oddballs incerto/BAIXA (**EM2C**, **EM3A**) têm 1 espeto/peça
solta. A amarração exata dessas partes está no formato/rotina de skinning do EXE — precisa
**extrair, não chutar**. Detector: `rig_check.gd` (baseline `PL00≈0,002`).

## IA — 100% do estaticamente decodável

- IA de inimigo = **MIPS puro embutido no `R###.BIN`** (overlay, tag low16=0x0001, base 0x80100000).
  **12/12 overlays × 548/548 handlers** com papel determinado e verificado
  (`godot/data/ai_overlays.json`: role/semantics/regions/counters + state_machines).
- Roteamento: loop único de objetos `0x8001bb24` → tabela **T64 `0x80097bd4`** por tipo; inimigos
  = tipos ~16..44; char-struct `0x1fc`; Nemesis (t41) `0x80020eb8`.
- **Não-decodável por design:** o *branch por-frame* é dinâmico (leques/tabelas já decodificados);
  **nome-de-espécie** é cross-unit (não está no EXE).

## Espécie — anotação por confiança (sem mapa canônico estático)

Não existe mapa canônico estático `EM##↔espécie` (nem no EXE nem publicado 1:1); a ligação
`class ↔ mesh ↔ EM##/skin` é **m:n** (provado: TIM byte-idêntico casa 1 mesh com vários skins).
A espécie é resolvida em **runtime**. Por isso a anotação é **por confiança explícita**
(`godot/data/sce_enemies.json → emd_annotations`: nome + `render_conf` + evidência):

- **Confirmados por render** (✅): EM10 zumbi, EM20 cão (Cerberus), EM21 corvo, EM25 aranha,
  EM3E/EM3F **helicópteros** (corrigido — não eram vermes), EM38 Nemesis-provável.
- Cobertura: **ALTA+MÉDIA = 43,5%**; **categoria-ou-melhor = 81,2%**; BAIXA = 19%.
- Palpites levam sufixo `_incerto`. Roster do jogo (15 tipos: zombie, dog, crow, drain deimos,
  brain sucker, grave digger, sliding worm, spiders, hunter β/γ, Nicholai, Nemesis 1ª/2ª/3ª)
  casa com as categorias vistas, mas o 1:1 não está fechado.

## Como usar na v2

1. **Já dá para colocar os 69 inimigos no mundo 3D:** os `.glb` trazem malha + textura +
   esqueleto + animação → prototipagem completa, reusando o pipeline do PLD.
2. **Espécie por sala** = cruzar o spawn do SCD (`sce_em_set`, op `0x7d`, 24B: classe+pos+dir+arma;
   1136 spawns + 80 NPCs em 137 salas) com a **anotação de confiança** — ver
   [scd_gameplay.md §4.1](../../docs/formatos/scd_gameplay.md). O `type_id` é **slot**, não espécie.
3. **IA:** `ai_overlays.json` dá o comportamento por classe (estados/timers/decisões) para portar
   a lógica; o branch fino é runtime (tabelas decodificadas).
4. **Resíduo a fechar:** extrair (não chutar) a amarração das partes model-space dos hunters/deimos
   e o mapa parte→osso dos 2 oddballs (EM2C/EM3A).
