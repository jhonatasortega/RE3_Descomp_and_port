# Plano de trabalho — RE3 RE + Remake 3D

> **Papel:** estratégia macro original (visão de longo prazo, fases 0–4 → v2 3D). O plano
> **operacional** pós-reset é o [`decomp/PLANO_ACAO.md`](decomp/PLANO_ACAO.md); o progresso
> real está no [`decomp/progress.json`](decomp/progress.json). Índice em [`README.md`](README.md).
> Os marcadores de fase abaixo são do início do projeto (não refletem o estado atual).

## Estratégia geral

O objetivo final (remake 3D no Godot) **não exige** um *matching decomp* completo. A engine
clássica da RE separa bem **dados** de **código**:

- **Dados** (a maior parte de "eventos, itens, IA de sala, câmeras, colisão") ficam nos
  arquivos **`.RDT`** (Room Data) — são *dados*, não código. Dá pra parsear com Python.
- **Código** (física de movimento, sistema de mira/tiro, dano, lógica central da IA do
  Nemesis) fica no **executável**. Isso sim entra em `decomp/` com Ghidra + PCSX-Redux.

Portanto: **RE dirigida > decomp completa** para o nosso objetivo.

---

## Fase 0 — Setup e extração  ← ESTAMOS AQUI

- [ ] Instalar ferramentas em `tools/` (jPSXdec, dumpsxiso, PCSX-Redux, Ghidra)
- [ ] Gerar `.cue` para a imagem (facilita alguns fluxos)
- [ ] **Extrair o sistema de arquivos** do disco (`dumpsxiso`) → `extracted/`
- [ ] **Inventariar os arquivos**: identificar `.RDT`, `.EMD`/`.PLD`, `.TIM`, `.XA`, executável
- [ ] Documentar o índice do disco em `docs/inventario.md`

## Fase 1 — Extração de assets

- [ ] **Áudio** — música/ambiente em `.XA` e SFX em bancos `VAB` → `.wav`/`.ogg` (jPSXdec)
- [ ] **Backgrounds** pré-renderizados → `.png` (podem estar comprimidos)
- [ ] **Texturas** `.TIM` → `.png`
- [ ] **Modelos** de personagens/inimigos (`.EMD`/`.PLD`) → `.glb`/`.obj`
- [ ] **Vídeos** `.STR` (cutscenes) → `.avi`/`.mp4` (jPSXdec)
- [ ] Referências 4K da internet para os cenários (só referência visual p/ remodelar em 3D)

## Fase 2 — RE de dados e lógica

### 2a. Dados de sala (RDT) — Python
- [ ] Mapear o cabeçalho/estrutura do `.RDT` do RE3 (variação do formato do RE2)
- [ ] Extrair por sala: posições de câmera + máscaras de profundidade, colisão, portas
- [ ] Extrair **posicionamento de itens** e **spawns de inimigos**
- [ ] Extrair os **scripts de evento** (SCD) — o que dispara o quê
- [ ] Documentar itens (IDs, tipos, munição) em `docs/mecanicas/itens.md`

### 2b. Lógica do executável — Ghidra + PCSX-Redux
- [ ] Achar constantes de **física/movimento** (velocidade, rotação, "tank controls")
- [ ] Sistema de **mira/tiro/dano**
- [ ] **IA**: máquina de estados dos zumbis e do **Nemesis** (perseguição, ataques)
- [ ] Sistema de **eventos** e flags de progresso

## Fase 3 — Protótipo Godot (fatia vertical)

- [ ] Instalar Godot 4 + estrutura do projeto em `godot/`
- [ ] Importar 1 sala: background + máscara de profundidade + câmera fixa (fiel ao original)
- [ ] Personagem com movimentação e colisão da sala
- [ ] Provar o pipeline de asset ponta-a-ponta antes de escalar

## Fase 4 — v2 3D

- [ ] Remodelar ambientes em **3D real** (usando backgrounds + refs 4K como referência)
- [ ] **Câmera livre 3D** (em vez de câmeras fixas)
- [ ] Port completo da lógica (física, itens, eventos, IA)
- [ ] Export para **PC** e **Android TV** (leanback + navegação por controle)

---

## Notas técnicas

- **PAL vs NTSC:** a base do projeto é **NTSC-U (60 Hz)**, exe `SLUS_009.23` (a imagem PAL
  `SLES_025.29` é só referência). Física/timing são por-frame; gameplay ≈ 30 fps (60/2).
- **Fixed-point:** o PS1 não tem FPU; posições/ângulos usam ponto-fixo. Atenção ao converter.
- **Não distribuir assets:** todo o pipeline assume que o usuário final traz a própria ISO.
