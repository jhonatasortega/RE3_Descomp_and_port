# Localização PT-BR (pacote "Edição Definitiva Dublado") — fonte de texto, voz e vídeo

> **STATUS:** fonte **MEDIDA e identificada** (2026-07-31), ainda **não consumida** pelo port.
> Itens no tracker: **P6-04** (files/memos), **P6-05** (FMV), **P6-06** (vozes/legendas),
> **P6-11** (tabelas de texto do mod) e **P6-12** (`.SLD`, formato a decodificar).
> Índice: [`README.md`](README.md) · Plano: [`../port/PLANO_MIGRACAO.md`](../port/PLANO_MIGRACAO.md)

O pacote PT-BR (`Resident Evil Edição Definitiva Dublado`) **já está aplicado** na instalação
GOG usada pelo projeto — comparação arquivo a arquivo do `hires/`: **0 arquivo exclusivo do
pacote** e apenas **1 divergência** (`hires/skin0/others`, 0 B no GOG vs 16 KB no pacote).
Ou seja: a instalação de referência **é** a versão PT-BR. O que o pacote traz **além** do
`hires/` é o que este doc cataloga.

> ⚠️ Trabalho de fãs sobre arte/áudio da **Capcom**. Uso pessoal/local; **não redistribuir**
> (mesma política de [`hd_seamless.md`](hd_seamless.md) §6).

## 1. Tabelas de texto do mod — `mod_BH3_Portuguese/xml/`

Formato trivial e diretamente consumível: XML `<Strings><Text>…</Text>…</Strings>`, **indexado
por posição** (o índice é o id do texto no engine). BOM UTF-8.

| Arquivo | Conteúdo |
|---|---|
| `items_simple.xml` | **Nomes de item por `item_id`** (`Faca`, `Pistola de mercenário`, `Escopeta`, `Lança minas`, …) |
| `status_mapping.xml`, `system.xml` | Strings de status/sistema (as duas maiores, 16 KB cada) |
| `epilogue.xml`, `prologue.xml` | Epílogos e prólogo |
| `mercs.xml`, `mercs_sel.xml` | Mercenários (Operation Mad Jackal) e sua tela de seleção |
| `map.xml`, `card.xml`, `power.xml`, `gas.xml` | Rótulos de mapa, cartão, painel de energia, válvula |
| `prompt.xml`, `pc_int.xml`, `title_mapping.xml`, `music.xml`, `ascii.xml` | Prompts, interação de PC, título, música, fonte |
| **`rdt/R###.xml`** | **129 arquivos** — texto in-game **por sala**, na ordem da tabela de mensagens do RDT |

Exemplo (`rdt/R100.xml`): `{scroll 2}Um mapa da área pro serviço\nde entrega.` — marcação
`{scroll N}` e `\n` explícito. **É a tabela real de exames/memos em PT-BR**, o que resolve o
TODO de [`../godot_ui.md`](../godot_ui.md) ("textos de exame são aproximações").

**A conferir (P6-11):** se o índice do XML casa 1:1 com o índice de mensagem extraído do RDT/EXE
(`re3_messages.json`). Cruzar com a tabela EN do EXE (`0x8a124`) dá o par EN↔PT por id.

## 2. Voz e som — `DATA_A/` e `DATA/`

Arquivos soltos que o Classic REbirth carrega por cima do `Rofs*.dat`:

| Pasta | Conteúdo | Medido |
|---|---|---|
| `DATA_A/VOICE` | **Vozes dubladas PT-BR** (`m101a010.wav`…) | **441 WAV**, 310 MB |
| `DATA_A/SOUND` | Áudio de menu/ambiente (`MAIN00.WAV`…) | 125 WAV, 258 MB |
| `DATA/SOUND` | Bancos de SFX e música do **PC** | 838 arq (531 `.VB`, 199 `.VH`, **107 `.BGM`**) |
| `DATA_A/BSS` | **`R###.SLD`** — 1 por sala + 5 `.JPG` | **169 SLD**, 31 MB (8 B … 464 KB) |

- Os **441 WAV** casam em contagem com os 441 `.ogg` PT-BR já no projeto
  (`assets/VOICE/ptbr/`) — mesma origem, mas aqui em **WAV sem recompressão**: melhor fonte
  para reencodar (P6-06).
- Os **107 `.BGM`** são a trilha sequenciada na versão PC (o projeto decodificou a do PS1 —
  ver [`audio_video.md`](audio_video.md) §7). Serve como fonte alternativa/de conferência.
- **`.SLD` = formato NÃO decodificado** (P6-12). Cabeçalho de `R100.SLD`:
  `01 00 00 00 | 14 2A 00 00` (`0x2a14` = 10772). Um por sala, tamanho muito variável →
  hipótese a testar: **legenda/slide por sala** (texto renderizado por cima da cena). Não
  confundir com `hires/slide` (34 telas de ending).

## 3. Vídeo — `zmovie/`

| Origem | Arquivos | Observação |
|---|---|---|
| Pacote PT-BR | **14 `.mp4`**, 482 MB | **1280×960, h264, 29,97 fps** — upscalados **e dublados em PT-BR** |
| GOG (original PC) | 16 `.dat` | FMV original do PC, não upscalado |

Ou seja: os `.mp4` da instalação vêm **deste pacote** — é a fonte HD **e** PT-BR do P6-05.
Não há trilha de áudio EN nos `.mp4`; se o port quiser FMV em inglês, a fonte é o `.dat`
(PC) ou o `.STR` do PS1 (320×160, já convertido para 14 `.ogv`).

## 4. Consequência para o port

1. **Idioma de texto:** PT-BR sai do mod (`xml/`), EN sai da tabela do EXE → par completo.
2. **Idioma de voz:** PT-BR de `DATA_A/VOICE` (WAV), EN do `Rofs*.dat` (ver [`rofs.md`](rofs.md)).
3. **FMV:** PT-BR dublado em HD já disponível; EN exigiria outra fonte (registrar como limitação).
4. **Nada disso é redistribuível** — entra pelo pipeline a partir da instalação do usuário
   (política P7-06).
