# Plano de migração — Port 1:1 do RE3 Nemesis para Godot 4

> **Papel:** plano operacional do **port 1:1** (fiel ao PS1 NTSC-U `SLUS_009.23`), com assets
> visuais do **Seamless HD Project**. Checklist, progresso e critérios de validação por item
> ficam no tracker gerado [`PROGRESSO.md`](PROGRESSO.md) (fonte: [`port_progress.json`](port_progress.json)).
>
> Companheiro de: [`../decomp/PROGRESS.md`](../decomp/PROGRESS.md) (o que já foi decompilado —
> **99% decompilado / 34% vinculado**) e [`../formatos/README.md`](../formatos/README.md) (formatos).

## 0. Decisões desta reinicialização

| Decisão | Valor |
|---|---|
| **Pasta** | **`port/`** — projeto Godot 4 novo e limpo |
| **`godot/`** | Protótipo antigo: **arquivo morto consultável**, não evolui mais |
| **`v2/`** | **NÃO É TOCADO** (linha 3D de câmera livre, vida própria) |
| **Assets** | **Copiados/regerados** para `port/assets` e `port/data` (projeto autocontido; `tools/*.py` reapontados) |
| **Escopo** | Campanha completa + 2 finais + dificuldades + **Mercenários** (Operation Mad Jackal) |
| **Tela** | **Mundo sempre em 4:3 1280×960** (= 4× PS1). Apresentação é **parâmetro**: modo **4:3** (padrão, pillarbox) ou **16:9 experimental** (crop para 1280×720). Nunca stretch — ver §2.1 |
| **Fonte visual** | SHDP `hires/` (bgd 1280×960, mask0/mask1 2048²) + `zmovie/*.mp4` upscalados 1280×960 — instalação GOG **somente leitura** |

## 1. O princípio que faz este port ser viável

O RE3 é **data-driven**. A decomp já provou onde está cada coisa:

- **Conteúdo** (169 salas, 2105 câmeras, 4238 funções de script, 453 portas, 193 itens, 69 modelos
  de inimigo, 62 BGM, 267 SFX, 13 telas de menu) → **já extraído** em JSON/glb/webp/ogg.
- **Comportamento** vive em **três intérpretes**: a **VM do SCD** (jump-table `0x8009e0f8`,
  144 opcodes), a **máquina de estados do player** (8 ações macro / 16 rotinas) e o
  **dispatcher de IA por classe** (`0x80023e00`, 12 overlays MIPS).

> **Regra do port:** reimplementar os **intérpretes**, nunca transcrever o conteúdo.
> Um `if` escrito à mão para abrir uma porta específica é dívida; a VM do SCD executando o
> script daquela sala é o port. Se a VM está certa, **169 salas de puzzles saem de graça**.

Corolário prático: **a fase F2 (VM do SCD) é o coração do projeto**. O protótipo antigo tinha
0% dela vinculado — é exatamente por isso que ele não escalava além de uma sala.

## 2. Fidelidade: o que "1:1" significa aqui (e o que não significa)

**É 1:1:**
- **Timing:** gameplay em **30 Hz fixo** (PS1 NTSC = 60 Hz de vídeo, lógica a 30). Toda constante
  do decomp é por-frame de 30 — o relógio precisa ser fixo e desacoplado do render.
- **Matemática:** ângulo de **4096 unidades** = 360°, `sin/cos` pela **tabela do jogo**,
  posições em unidades PS1 (fixed-point). Converter só na hora de desenhar.
- **Algoritmos, não aproximações:** troca de câmera pelo **RVD** como o EXE faz (stride `0x14`,
  ponto-em-quad, histerese em 2 fases), **não** por "melhor enquadramento"; **root-motion por
  pose**, não velocidade escalar; oclusão pelo **atlas de priority sprites**, não por caixa 3D.
- **Números:** dano pela tabela `0x8009d834`, frame do tiro por arma (`0x8009cf28`), HP em `+0xcc`.

**Não é 1:1 (e está tudo bem):**
- **Resolução:** 1280×960 em vez de 320×240 — é o objetivo explícito (assets HD do mod).
- **Renderização:** Godot desenha; não replicamos GTE/MDEC. O que replicamos é o **resultado**
  (transform bone-local, ordem `T·Rx·Ry·Rz`, mesma silhueta de oclusão).
- **Formato de save:** save próprio do port. O **conteúdo** salvo é que precisa ser completo.
- **Loader de CD/SPU:** fora de escopo — a engine do Godot cobre.

### 2.1 Proporção de tela: 4:3 é o dado, 16:9 é um recorte

**Medido na instalação GOG (não suposto):**

| Fonte | Resolução | Proporção |
|---|---|---|
| `hires/bgd` — **1316/1316** backgrounds | 1280×960 (sem exceção) | **4:3** |
| `hires/mask0` + `mask1` — 1761 máscaras | 2048×2048 | atlas de sprites |
| `zmovie/*.mp4` — 14 FMV upscalados (2025) | **1280×960**, h264, 29,97 fps | **4:3** |
| `hires/map` | 1024×1024 e 1024×864 | 4:3 |
| `config.ini` (Classic REbirth) | `Display_mode=3`, `RenderUnwarp=1`, `LowResBg=1` | **nenhuma chave de widescreen** |

**Conclusão:** a versão de PC/GOG com o SHDP é **4:3**. Não existe asset widescreen no mod
(`RenderUnwarp` é correção de distorção de aspecto, não widescreen). Logo, 16:9 só sai de:

- **cortar 25% da altura** (1280×960 → 1280×720: 120 px em cima + 120 embaixo) — e nas câmeras do
  RE3 o piso/teto costuma estar na borda; ou
- **inventar 33% da largura** (960 de altura exigiria 1706 de largura) por outpainting — cenário
  inventado sem máscara de oclusão nem colisão correspondente, contra um frustum de câmera que
  assume o quadro original. **Descartado.**

**Decisão:** o **quadro é parâmetro de apresentação**, não premissa de arquitetura. O mundo é
sempre renderizado em 4:3 1280×960; o modo de tela decide se **emoldura** (pillarbox, padrão) ou
**recorta** (1280×720, experimental). Isso custa 4 itens no plano (**P1-15**, **P1-16**, **P6-10**,
**P7-09**) se feito desde a F1, e custaria uma reescrita se feito depois.

Três consequências registradas para não virarem bug silencioso:
1. **O gate da F1 (P1-14) é medido no modo 4:3** — o 16:9, por definição, não é 1:1 no enquadramento.
2. **As máscaras de oclusão têm coordenada de TELA** — se o crop não for propagado à origem dos
   sprites, a oclusão desalinha 120 px no modo 16:9 (**P1-16**).
3. **A UI é composta numa base 320×240** (×4 = 1280×960) — no 16:9 ela ancora numa safe-area em
   vez de seguir o crop (**P6-10**).

E a decisão final sobre suportar ou não o 16:9 sai de um **número**, não de impressão: **P7-09**
varre as 2105 câmeras e lista em quantas o corte come o piso ou um elemento essencial.

> Widescreen "de verdade" (sem perder quadro) exige cenário 3D real — que é exatamente o que a
> linha [`../../v2/`](../../v2/README.md) existe para fazer, e que **não é tocada** por este port.

## 3. Arquitetura de `port/`

```
port/
├─ project.godot                # 1280x960, 4:3 travado (pillarbox), 30 Hz de gameplay
├─ core/                        # camada determinística — NÃO conhece Godot visual
│  ├─ clock.gd                  # tick fixo de 30 Hz, ordem de update canônica
│  ├─ ps1_math.gd               # ângulo 4096, sin/cos table, fixed-point
│  ├─ coords.gd                 # PS1 (Y-down) <-> Godot (Y-up), world_scale=808
│  ├─ game_state.gd             # bancos de flags 0xc0..0xf1, variáveis, inventário, progresso
│  └─ entity.gd                 # char-struct (pos +0x34, dir +0x6e, HP +0xcc, estado, timers)
├─ script_vm/                   # F2 — a VM do SCD
│  ├─ vm.gd                     # dispatch dos 144 opcodes (0x00..0x8f), threads, PC
│  ├─ opcodes/                  # handlers agrupados por família (fluxo, AOT, som, cena, enemy)
│  └─ aot.gd                    # gatilhos: AABB / QUAD sobre a posição do personagem
├─ room/                        # F1/F3 — runtime de sala
│  ├─ room_loader.gd            # RDT + _col + _scd (qualquer R###)
│  ├─ camera_rid.gd             # câmera fixa (from/to, FOV por câmera)
│  ├─ camera_rvd.gd             # troca de câmera com a semântica provada
│  ├─ collision.gd              # retângulos XZ, parede vs móvel, deslize por eixo
│  ├─ occlusion.gd              # atlas HD mask0/mask1 + mask_data_ptr (Z per-sprite)
│  └─ door.gd                   # transição + animação .DO#
├─ actors/                      # player + inimigos
│  ├─ player_sm.gd              # 8 ações macro / 16 rotinas / tier de anim por HP
│  ├─ combat.gd                 # mira (aim tier), hitscan, projéteis, dano
│  └─ ai/                       # F5 — uma classe por arquivo (zumbi, cão, hunter, nemesis…)
├─ present/                     # apresentação: modo de tela 4:3 | 16:9 (crop), pillarbox, tonemap
├─ meta/                        # F6 — menus, inventário, mapa, files, FMV, save
├─ assets/                      # GERADOS pelo pipeline (GITIGNORED)
├─ data/                        # GERADOS pelo pipeline (GITIGNORED)
└─ dev/                         # harness: screenshot, test runner, replay de input
```

**Regra de camada:** `core/` e `script_vm/` não referenciam nó visual nenhum. Isso é o que
permite rodar a VM e a física em teste headless — e é o erro do protótipo antigo, onde lógica
de sala e apresentação moravam juntas em `room_game.gd`.

## 4. Fases e ordem de trabalho

Detalhe item a item (78 itens, com critério de validação em cada) no
[`PROGRESSO.md`](PROGRESSO.md). Resumo e por que nesta ordem:

| Fase | Título | Por que aqui | Gate de saída |
|---|---|---|---|
| **F0** | Fundação do `port/` | Relógio, ângulo, coordenadas e flags contaminam tudo se errados | Importa com 0 erro, 4:3 pillarbox, suíte de testes rodando, 0 asset faltante |
| **F1** | Sala fiel (R100 + R10E) | Prova o pipeline visual/físico ponta a ponta numa sala só | **P1-14:** 6 pontos de referência lado-a-lado, aprovados por você |
| **F2** | **VM do SCD** | O coração: destrava 169 salas de eventos/puzzles de uma vez | **P2-10:** dry-run das 4238 funções, 0 opcode faltante, diff limpo vs `scd_decode.py` |
| **F3** | Mundo inteiro | Com VM pronta, portas/salas/save são consequência | **P3-06** 453/453 portas + **P3-07** rota crítica completa por replay |
| **F4** | Combate e entidades | Precisa de entidade + animação de inimigo já no mundo | **P4-09:** nº de tiros para matar == original em 6 pares arma×inimigo |
| **F5** | IA por classe | Última camada de comportamento; a mais custosa de validar | **P5-09:** cada classe em vídeo lado-a-lado |
| **F6** | Meta-jogo | Fecha o jogo completo (menus, mapa, FMV HD, finais, Mercenários) | Completável do título ao epílogo, 2 finais, Mercenários jogável |
| **F7** | Fidelidade e release | Tempos, mixagem, regressão, export "traga sua cópia" | Build limpo sem asset da Capcom/SHDP + suíte verde |

**Uma fase por vez, um item por vez.** Nada da fase seguinte começa antes do gate da anterior —
essa é a regra que o [`PLANO_ACAO.md`](../decomp/PLANO_ACAO.md) já estabeleceu depois do sprawl
do protótipo antigo (14 unidades meio-vinculadas, nenhuma fechada).

## 5. Metodologia de validação (como se prova "1:1")

Três instrumentos, escolhidos por item no tracker:

1. **Harness automático (o mais forte).** Roda no Godot headless e compara contra o dado já
   decompilado. Exemplos: as 4238 funções de script executam e fecham em `evt_end`; as 453
   portas atravessam nos 2 sentidos; as 169 salas carregam sem exceção; os 4096 ângulos batem
   com a `sin_cos_table`. **Prova por construção — não depende de olho.**
2. **Medição numérica contra o emulador.** Rodar o original (PCSX-Redux/DuckStation) e medir a
   mesma grandeza: distância percorrida em 10 passos, frames de recuo, tiros para matar, posição
   exata do corte de câmera. **Número igual = igual.**
3. **Render lado-a-lado aprovado por você.** Screenshot/vídeo do original vs port no mesmo ponto.
   Usado onde não há número: enquadramento, silhueta de oclusão, comportamento de IA, timing de
   cena. **Só você marca `valid=100`.**

**Regra de honestidade (herdada do tracker de decomp):** aproximação declarada é aceitável;
aproximação disfarçada de fidelidade não é. Todo item que ficar aproximado nasce com nota
explícita no `port_progress.json` dizendo o quê e por quê.

## 6. Riscos e limites conhecidos (declarados de saída)

| Risco | Situação | Encaminhamento |
|---|---|---|
| **Rig de ~8-10 modelos de inimigo** (hunters EM22/23/24, deimos EM28/35, **Nemesis EM38**, EM34/36/3A) | **Limite do dado, provado:** o índice vértice→osso foi descartado no EMD do PC e as duas fontes (Rofs9/Rofs10) são idênticas. Geometria, UV, textura e animação estão certas — falta o peso por osso | **P4-03:** rig manual no Blender. Nemesis é obrigatório. É o "bug de modelo 3D" que você já notou |
| **100 câmeras sem background HD** (medido) | 2005 das 2105 câmeras têm HD (**95,2%**), 100 ficam em SD, **0 sem imagem**. A estimativa inicial de ~600 estava errada: os 1232 arquivos HD são **reusados** entre câmeras/salas | **P1-02:** decidir entre upscalar o SD, casar pelo Método A (pHash) ou jogar as salas faltantes no PC para regerar o cache — o impacto real é 4,8% das câmeras |
| **Índice de câmera HD ↔ PS1** | Única pendência aberta do HD (`hd_mapping.md §6`) | **P1-03:** auditar `n_cameras(hd_map)` vs `n_cameras(RDT)` nas 170 salas |
| **IA = MIPS puro nos overlays** | 548/548 handlers têm **papel determinado**, mas o branch por-frame é dinâmico por design | **F5:** reimplementar por comportamento observável, classe a classe, validando em vídeo |
| **Easing por-frame das portas** | Bit-packed irredutível (fronteira provada) | **P3-02:** aproximar a curva, validar contagem de frames em vídeo |
| **Nome de espécie `EM##`** | Mapa canônico não existe no EXE nem publicado | Usar `emd_annotations` com a **confiança registrada** (ALTA+MÉDIA 43,5%; categoria-ou-melhor 81,2%) |
| **Modo 16:9** | Não existe asset widescreen (medido: 1316/1316 bgd em 4:3); crop perde 25% da altura | **P7-09:** auditar as 2105 câmeras e decidir por número se sai como opção suportada, "a seu risco" ou descartada |
| **Memória dos assets HD** | bgd 1280×960 + máscaras 2048² por câmera | **P3-04:** carregar por câmera, não por sala; medir pico |
| **FMV** | Godot 4 só toca **Ogg Theora**; a fonte HD é `.mp4` (`opn.mp4` = 135 MB) | **P6-05:** reencode com o `ffmpeg` de `tools/`, testar bitrate vs qualidade |
| **Licença** | SHDP e Classic REbirth são trabalho de fãs sobre arte da **Capcom** | **P7-06:** nada de asset no repo/pacote; usuário gera do próprio disco/instalação. Projeto **privado** |

## 7. Como montar os assets (pipeline)

Uma CLI só, que declara etapa, dependência, fonte necessária e saída:

```bash
python tools/build_assets.py --list --out port      # 31 etapas, deps, fontes e contagem atual
python tools/build_assets.py --out port             # monta tudo o que é automático
python tools/build_assets.py --out port --only rooms,scd
python tools/build_assets.py --out port --manifest  # inventário (P0-03)
python tools/build_assets.py --out port --verify    # confere contra o inventário
```

O destino chega nos scripts pela variável **`NOSTALGIA_OUT`** ([`tools/paths.py`](../../tools/paths.py)),
então nenhum caminho de saída fica fixo no código das ferramentas. O default é `godot`, o que
preserva o comportamento histórico dos 26 scripts repontados.

Fontes (todas **somente leitura**, nada é redistribuído): `iso` (disco PS1 extraído), `hires`
(instalação de PC com o SHDP), `rofs` (`Rofs*.dat`, modelos de inimigo e vozes EN) e `ptbr`
(pacote dublado — ver [`../formatos/localizacao_ptbr.md`](../formatos/localizacao_ptbr.md)).

**Quatro etapas são MANUAIS** por dependerem de ferramenta externa ou decisão ainda não tomada
(`voices_en`, `voices_ptbr`, `fmv`, `ptbr_text`). Elas aparecem no relatório como
`PENDENTE-MANUAL` — **nunca** são silenciosamente puladas.

### Dívida descoberta ao montar o pipeline (P0-11)

Seis JSON de `data/` **não são gerados por script nenhum** (foram produzidos ad-hoc):
`physics.json`, `anim_map.json`, `ai_overlays.json`, `sce_items.json`, `hd_ui_map.json` e
`re3_items.json` — e `re3_text.py --build-items` **enriquece** o último em vez de criá-lo.
Enquanto **P0-11** não fecha, a etapa `seed` copia esses arquivos do `godot/data` e **declara**
a dívida no log. O precedente de como fechar é o
[`hd_map_build.py`](../../tools/hd_map_build.py): era o 7º caso, foi escrito agora e **provado
equivalente** ao arquivo antigo (170 salas, 1521 câmeras, 0 divergência).

## 8. Como manter o tracker

O checklist **não** é editado à mão. Editar `impl`/`valid`/`nota` em
[`port_progress.json`](port_progress.json) e rodar:

```bash
python tools/port_progress.py     # regenera docs/port/PROGRESSO.md
```

Convenção dos eixos:
- `impl` sobe conforme o código existe e roda (0 → 100).
- `valid` só vai a **100** quando o **critério do item** foi cumprido — e, nos itens de render/
  vídeo, quando **você aprovou**. Nada de "valid" por autoavaliação do agente.
- Checkbox no `.md`: `[ ]` a fazer · `[~]` implementado, não validado · `[x]` validado.

## 9. Primeiro passo concreto

**F0 / P0-01 + P0-02:** criar `port/` (Godot 4, 1280×960, 4:3 pillarbox) e transformar os ~40
scripts de `tools/` numa CLI única de build de assets apontando para `port/assets` e `port/data`
— com manifesto e verificador (P0-03). Sem isso o projeto novo não tem como se montar sozinho a
partir da sua cópia do jogo.
