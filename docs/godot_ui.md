# UI in-game do RE3 (HUD + Inventário + Seletor de idioma)

> **Guia do protótipo** (implementação v1). Fontes: ícones/textos HD ([formatos/hd_ui.md](formatos/hd_ui.md)),
> `item_id` do SCD ([formatos/scd_gameplay.md](formatos/scd_gameplay.md)), nomes em
> [referencias/evilresource.md](referencias/evilresource.md). Índice em [`README.md`](README.md).
> Nota: o RE3 **não tem HUD em gameplay** (unidade `hud` do tracker → remover do protótipo).

Camada de interface do remake, montada **inteiramente via autoloads** para não
tocar em `room_game.gd`, `jill_controller.gd` nem `game_room.tscn`. Como cada
autoload de UI é uma cena com raiz `CanvasLayer`, ele é filho de `/root` e
renderiza **sobre qualquer cena** automaticamente.

![Inventário autêntico do RE3 sobre o jogo](godot_ui.png)

## Inventário AUTÊNTICO do RE3 (nova versão em `ui/`)

A tela de status/inventário foi refeita para reproduzir **fielmente** o RE3
original (a versão em grade genérica antiga virou placeholder). Arquivos novos:

| Arquivo | Papel |
|---|---|
| `godot/scenes/ui/inventory.tscn` + `godot/scripts/ui/inventory.gd` | **Inventário fiel RE3** (status + grade 2×4 + submenu USE/COMBINE/CHECK + descrição) |
| `godot/scenes/ui/hud.tscn` + `godot/scripts/ui/hud.gd` | **HUD in-game** RE3 (condition/ECG + estado + arma equipada/munição) |
| `godot/data/re3_items.json` | Banco de itens: nomes/descrições PT-BR/EN + `default_loadout` |
| `godot/assets/UI/item/*.png` | **45 ícones HD reais** (Seamless HD `hires/item`), identificados por render |
| `godot/assets/UI/frame/*.png` | Peças do frame metálico do RE3 recortadas de `ETC/STMAIN0U.png` (EQUIP, condition/ECG, retrato da Jill, fundo navy do slot) |
| `godot/assets/UI/text/*.png` | Palavras do atlas `ETC/STMOJIU.webp` (Fine/Caution/Danger/Poison + verbos EQUIP/USE/COMBINE/CHECK) |
| `godot/dev/tools_inv_shot.gd` | Harness de screenshot (troca os autoloads em runtime; `--rendering-driver opengl3`) |

### ⚠️ Registro do autoload (a fazer no `project.godot`)

O autoload `Inventory`/`HUD` **ainda aponta para os placeholders** em
`res://scenes/inventory.tscn` / `res://scenes/hud.tscn`. Para ativar a versão
autêntica, trocar por:

```ini
[autoload]

LangManager="*res://scripts/lang_manager.gd"
HUD="*res://scenes/ui/hud.tscn"
Inventory="*res://scenes/ui/inventory.tscn"
```

E (opcional) registrar as ações de input `inventory_toggle` (TAB/I). Enquanto o
autoload não for trocado, o harness `tools_inv_shot.gd` instancia as cenas `ui/`
em runtime para validação.

### Layout (fiel ao RE3, base 320×240 escalada 4× → 1280×960)

- **Esquerda (status):** prévia do item selecionado (`item_box`), arma **EQUIP**
  com ícone HD + munição, display **condition** com ECG animado e estado
  **FINE/CAUTION/DANGER/POISON** (palavra autêntica do STMOJI, tintada
  verde/amarelo/vermelho/roxo), e o **retrato da Jill**.
- **Direita:** **grade 2×2×4 (8 slots)** com ícones HD reais sobre o fundo
  azul-marinho autêntico das caixas de item; slot selecionado com cursor
  pulsante.
- **Rodapé:** barra de **descrição** (nome + texto de exame, PT-BR/EN).
- **Submenu:** ao apertar Enter num item abre **EQUIP / USE / COMBINE / CHECK**
  (verbos reais do atlas STMOJI) com cursor-triângulo. `combine` de ervas
  implementado (verde+vermelha etc.).

### Ícones e fonte dos nomes

- Os 120 `.webp` HD de `hires/item` foram identificados **por render** (contact
  sheet + zoom) e 45 migrados para `assets/UI/item/` já renomeados por item
  (`handgun_sigpro`, `shotgun`, `grenade_launcher`, `green_herb`,
  `first_aid_spray`, `ink_ribbon`, `magnum`, `mine_thrower`, etc.). Confiança da
  identificação por item em `re3_items.json` (`icon_conf`).
- **Nomes canônicos** do RE3 em PT-BR e EN. Os textos de **exame** são
  aproximações — **TODO:** extrair a tabela real de nomes/exame dos arquivos de
  mensagem por idioma (RDT/MSG) e casar por `item_id` (o `item_id` em
  `re3_items.json` é hipótese de `sce_items.json`, confiança média/baixa).

## 1. HUD de vida (estilo RE clássico)

- **Eletrocardiograma**: linha de batimento animada (forma P-QRS-T simplificada)
  desenhada em `_draw` via o sinal `draw` do nó `EcgView`, com varredura
  horizontal e ponto brilhante na "cabeça". Fica no **canto inferior esquerdo**.
- **Estado de saúde**: `FINE` / `CAUTION` / `DANGER` com cor
  **verde / amarelo / vermelho**. O estado atual é um **placeholder (`FINE`)**.
  O batimento acelera conforme o estado piora.
- API para o resto do jogo mudar o estado sem acoplamento:
  `HUD.set_state(HUD.Health.CAUTION)`.

## 2. Inventário (grade estilo RE)

- Abre/fecha com **I** ou **TAB** (também fecha com **ESC**).
- **Fonte de dados**: `godot/data/sce_items.json`.
  - `itens_observados.por_sala` → `item_id` + `amount` reais extraídos do SCD
    (opcode `0x68`), agregados somando todas as salas.
  - `item_id_ref` → nome/categoria do `item_id` (quando conhecido).
  - Observação: os arquivos `data/STAGE*/R*.json` **ainda não têm** o campo
    `rdt.script.items` anotado, então a fonte confiável hoje é o próprio
    `sce_items.json`. Quando o extrator `tools/scd_items.py` for rodado e
    anotar as salas, basta estender `inventory.gd` para ler de lá.
- **Ícones**: placeholders (retângulo colorido por categoria) + **nome** +
  **ID + quantidade**. Ex.: `Grenade Launcher (Explosive rounds)` `0X04 x14`.
- Itens exibidos (agregados das 7 salas observadas): `0x04, 0x15, 0x21, 0x41,
  0x42, 0x99, 0x9b, 0xa0`. IDs sem nome no roster aparecem como `Item 0xNN`
  (honesto — nomes só para os que têm confiança na tabela).

## 3. Seletor de idioma (voz)

- Autoload **`LangManager`** com `lang` = `"en"` | `"ptbr"` e um
  `AudioStreamPlayer` próprio (toca sobre qualquer cena).
- Vozes em `res://assets/VOICE/en/` e `res://assets/VOICE/ptbr/`
  (441 `.ogg` em cada, mesmos nomes de cena — paridade verificada).
- Métodos: `set_lang(l)`, `toggle_lang()`, `has_voice(nome)`,
  `play_voice(nome_cena)`, `stop_voice()`. Sinais: `lang_changed`,
  `voice_played`.
- **Tecla L** (tratada no HUD) cicla o idioma, atualiza o indicador
  `VOICE: EN/PTBR [L]` no topo direito, mostra um toast e toca uma fala de
  demonstração (`m101a010`) no novo idioma.

Exemplo de uso a partir de qualquer script de gameplay:

```gdscript
LangManager.set_lang("ptbr")
LangManager.play_voice("m101a010")   # res://assets/VOICE/ptbr/m101a010.ogg
```

## Validação

Godot 4.7.1 (Steam), driver OpenGL3.

1. **Import**: `godot --headless --path . --import` → `IMPORT_EXIT=0`, sem
   erros de script nem de autoload.
2. **Execução**: `godot --path . --rendering-driver opengl3 --quit-after 150`
   → `RUN_EXIT=0`, sem erros/warnings. Os três autoloads instanciam e o
   inventário carrega `sce_items.json` sem avisos.
3. **Print**: cena temporária instanciou `game_room.tscn` com os autoloads por
   cima e capturou `docs/godot_ui.png` (HUD + inventário sobre o jogo). Os
   arquivos temporários da captura foram removidos.
