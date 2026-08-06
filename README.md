# Nostalgia — Resident Evil 3: Nemesis (RE + Remake 3D)

Projeto pessoal de **engenharia reversa** e **reimplementação** de *Resident Evil 3: Nemesis*
(PlayStation 1, base **NTSC-U**, exe `SLUS_009.23`) na engine **Godot**, com objetivo final
de uma **versão 3D com câmera livre** ("v2 3D"), substituindo os cenários pré-renderizados
por ambientes 3D reais. Documentação em [`docs/`](docs/) (índice: [`docs/README.md`](docs/README.md)).

## ⚠️ Aviso legal (leia antes de tudo)

- *Resident Evil 3* é propriedade da **Capcom**. Este é um projeto de **estudo/preservação pessoal**.
- A imagem do disco (`rom/`) e os assets extraídos (`extracted/`, `assets/`) **NÃO são
  distribuídos** e estão no `.gitignore`.
- Qualquer versão pública deve **exigir que o usuário forneça a própria cópia original**
  (modelo DevilutionX / OpenRCT2) — nunca embutir os assets da Capcom.
- Reimplementação de jogo ainda comercializado tem risco de DMCA. Manter o projeto privado
  até decidir a estratégia de release.

## Objetivo

1. **Engenharia reversa** dos dados e da lógica: física, eventos in-game, IA (Nemesis/zumbis),
   itens, trilha sonora e imagens.
2. **Documentar** formatos de arquivo e mecânicas em `docs/`.
3. **Reconstruir no Godot** como *v2 3D*.

> **Escopo realista:** não é preciso um *matching decomp* (recompilar byte-a-byte) do jogo
> inteiro para o remake. O caminho eficiente é **RE dirigida**: extrair assets + parsear os
> dados de sala (RDT) + entender as mecânicas do executável. O `decomp/` fica para as partes
> de *código* que precisarmos entender a fundo (física, IA). Ver `docs/plano.md`.

## Estrutura

```
Nostalgia/
├─ rom/            # imagem original do disco (GITIGNORED — copyright)
├─ extracted/      # arquivos crus extraídos da imagem (GITIGNORED)
├─ assets/         # assets convertidos p/ formatos abertos: png, glb, ogg (GITIGNORED)
├─ tools/          # ferramentas de RE/extração (jpsxdec, dumpsxiso, scripts)
├─ docs/           # documentação da RE — formatos, salas, mecânicas, itens
├─ decomp/         # trabalho de decompilação do executável (Ghidra, m2c, asm)
├─ port/           # **PORT 1:1 no Godot 4** (foco atual) — ver docs/port/PLANO_MIGRACAO.md
├─ godot/          # protótipo antigo (referência/arquivo morto)
└─ v2/             # linha 3D de câmera livre (independente)
```

## Ambiente

| Ferramenta | Status | Uso |
|---|---|---|
| Python 3.12 | ✓ instalado | scripts de parsing/extração |
| Java 17 | ✓ instalado | jPSXdec |
| Git 2.51 | ✓ instalado | versionamento |
| Godot 4 | ⚠️ instalar | engine da v2 |

## Imagens do disco (em `rom/`, todas gitignored)

| Arquivo | Versão | Papel |
|---|---|---|
| `Resident Evil 3 - Nemesis.bin` (+`.cue`) | **NTSC-U (América)** | **BASE PRINCIPAL** — 60 Hz, exe SLUS |
| `Resident Evil 3 - Nemesis (Europe).bin` | PAL/Europe | Referência — 50 Hz, exe `SLES_025.29` |
| `Resident Evil 3 - Nemesis.cdi` | **Dreamcast** | Fonte 2ª de backgrounds (melhor qualidade) |

- **Formato PS1:** raw CD MODE2/2352.
- **Base principal = NTSC-U** (timing canônico 60 Hz; a RE tooling documenta o SLUS).
- **Dreamcast (`.cdi`):** outra plataforma (SH-4) — não serve p/ decomp do executável, mas os
  backgrounds pré-renderizados tendem a ter resolução melhor. Formato GD-ROM/DiscJuggler,
  precisa de ferramenta específica (não o `list_iso.py`).

## Roadmap (resumo)

- **Fase 0** — Setup e extração do disco
- **Fase 1** — Extração de assets (backgrounds, modelos, texturas, áudio)
- **Fase 2** — RE de dados e lógica (RDT: salas/itens/eventos/IA; executável)
- **Fase 3** — Protótipo Godot (fatia vertical de uma sala)
- **Fase 4** — v2 3D (ambientes 3D, câmera livre, port completo)

Detalhes em [docs/plano.md](docs/plano.md).
