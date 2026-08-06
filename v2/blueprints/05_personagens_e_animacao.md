# 05 · Personagens + animação (PLD base + PLW armado)

> Fonte: [`../../docs/formatos/PLD.md`](../../docs/formatos/PLD.md) e
> [`../../docs/formatos/animacoes_player.md`](../../docs/formatos/animacoes_player.md);
> máquina de estados em [`../../docs/formatos/exe.md §4-B`](../../docs/formatos/exe.md).
> Ferramentas: `tools/pld2gltf.py` (`build_armed_clips`), `find_anim_banks.py`.

## O que reusar direto na v2

Os `.glb` já exportados (**109/110** modelos: 25 `.PLD` + 84 `.PLW`) servem **sem mudança** —
malha + esqueleto (**15 ossos**) + skin suave + 22 clipes base + textura (com **rosto HD**).
São os mesmos modelos+anim que a v2 usa (a v2 muda o cenário, não os personagens).

- **PLD 100%** (unidade `pld`): rig **limpo** — baseline `rig_check PL00≈0,002` (vão-até-pai),
  a referência de qualidade usada para validar todos os outros rigs (inclusive os inimigos).
- **Locomoção armada 100%** (unidade `plw`): **84/84 PLW validados**; a **malha da arma** foi
  decodificada como malha própria → **63 `_WPN.glb`** (arma separável) + 21 sem slot (handguns
  W00 + PL09/PL0A pintadas na pele) = esperado.

## A descoberta-chave: locomoção é MULTI-BANCO por arma

- `player+0xc8` = índice de sequência EDD; mas o **ponteiro-base do EDD é selecionado em
  runtime pela ARMA equipada** (multi-banco). Com arma na mão (o caso normal da Jill), a
  base é o **PLW**, não o `PL00.PLD`.
- O **banco0 do PLW** é **corpo inteiro** (15 ossos, frameSize 76, 18 seqs, 399 poses):
  - seq0 = **andar** (~76/f) · seq1 = **correr** (~222/f) · seq9 = **ré** (~68/f) · seq2/5/8 = parado/mira.
- O `pld2gltf.build_armed_clips` retargeta o banco0 do PLW ao esqueleto do PLD (mesmos 15
  ossos) → o `PL00.glb` tem 40 clipes: `anim00..21` (base) + `arm00..17` (armado).

## Como montar o controller 3D

1. **Locomoção** = clipes `armNN` do **PLW da arma equipada** (troca de banco ao trocar de arma).
   Cada uma das 21 armas (`PL00W00..W14`) tem seu PLW → o andar muda por arma. Cada PLW tem
   **3 bancos** (bank0=15 ossos/locomoção; bank1/2=overlays parciais de mira/gesto) →
   correspondem aos 3 slots armados do EXE (`player+0xf4/0xf8/0x100`).
2. **Ações sempre-válidas** (independem da arma) vêm do PLD base: dano `anim19/anim20`,
   apanhar `anim08`, idle-wait `anim21`.
3. **Movimento por root-motion real** (vetores por pose em `physics.json`), não velocidade
   escalar — ver [01](01_coordenadas_e_escala.md).
4. Skinning **suave por vértice** (envelope local por membro) já resolvido no export — mantém
   botas/antebraços atados nas juntas.

## Osso de anexo (arma)

- **`bone4`** (punho direito) é o osso de anexo da arma, world-rest `(-32, 297, -435)`. É dado de
  decomp fechado; prender a `_WPN.glb` nele no controller 3D é **vínculo**, não pesquisa.

## Pendências

- **Mesh da arma decodificada** (63 `_WPN.glb` separáveis) — resta só **anexá-la no `bone4`** no
  controller (vínculo). Deixou de ser "estática/refino futuro".
- Validar **mira** + "subir em item"; fixar o índice de tier por captura de save-state
  (ver [exe.md §4-B.5](../../docs/formatos/exe.md)).
- **Inimigos** têm doc própria: [06_inimigos](06_inimigos.md).
