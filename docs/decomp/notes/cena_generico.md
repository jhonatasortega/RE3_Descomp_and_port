# Cenas POR DADO — o censo dos opcodes e o critério que substituiu a lista branca

> **O pedido do dono, literal:** *"não dá para a gente ficar extraindo as cenas uma por uma,
> precisa de um padrão. Além disso algumas têm mudança no cenário de forma permanente,
> movimentação de NPCs, efeitos, trilhas, explosões..."*
>
> Este doc é a resposta. Duas cenas foram portadas à mão (`cena_r10d.md`, `cena_r101.md`) e
> ficavam numa lista branca `World.CENAS_LIGADAS`. **A lista caiu.** Agora o port audita o
> bytecode da cena e decide sozinho; a cobertura sobe conforme os opcodes entram.
>
> **Ferramenta:** [`tools/scd_cena_censo.py`](../../../tools/scd_cena_censo.py) →
> [`port/data/cena_opcodes.json`](../../../port/data/cena_opcodes.json) (versionável).
> **Critério:** `Cena.auditar()` em [`port/script_vm/cena.gd`](../../../port/script_vm/cena.gd).
> **Métrica:** `port/dev/diag_cena_cobertura.gd`.
> **Testes:** `-- cena` (229 asserts) · `-- world` (110, as 453 portas verdes).

---

## 1. O número que importa

```
══════════ COBERTURA DAS CENAS (critério `Cena.auditar()`) ══════════
cenas de ENTRADA :  174   rodam  114  (66%)
cenas de GATILHO :  178   rodam  151  (85%)
TOTAL            :  352   rodam  265  (75%)
salas com cena   :  120   com pelo menos uma rodando: 103
```

Antes deste round: **2 cenas** (as duas do `R10D`) + a do `R101`. Agora **265**, e nenhuma delas
precisou de uma linha de código por sala.

As "cenas" aqui são as que o jogo REALMENTE abriria numa partida nova: `executar(0)` em cada sala,
mais as ENTRADAS (`vm.threads_pedidas`, os `0x04` que o init de fato executou) e os GATILHOS (o
payload dos AOT `sce 5` que o init registrou). Não é contagem estática de funções.

### 1.1 O que falta, e é uma lista de CINCO opcodes

| opcode | cenas travadas | o que é |
|---|---|---|
| `0x18` | **81** | salto relativo `0x80053770` — §4, é problema de ARQUITETURA, não de opcode |
| `0x6c` | 4 | condição de `while` (`aot`, não decodificado) |
| `0x7a` | 3 | FMV |
| `0x6d` | 1 | condição de `while` |
| `0x1d` | 1 | condição de `while` |

Tirando o `0x18`, **9 cenas** separam o port de ~100%.

---

## 2. O censo — 169 salas, 125 opcodes

`tools/scd_cena_censo.py` acha as funções de cena pelas RAÍZES que o dado declara (nada escolhido
a dedo): alvo de `0x04`/`0x03` (`evt_exec`, `0x80052ea4`) e payload de AOT `sce 5`
(`0x800512bc`), com fechamento por `0x19` (gosub) e `0x03`/`0x04` (thread). Cada opcode sai com
nome, handler, classe, tamanho, nº de ocorrências, nº de salas e nº de cenas.

Os 20 primeiros por alcance (salas):

```
op     salas cenas  vezes  classe       nome
0x01   138   1437   5151   fluxo        evt_end/return
0x00   136   1242   32254  fluxo        nop
0x09   127   1002   10754  fluxo        sleep_init
0x0a   127   1002   10754  fluxo        sleeping (espera NN quadros)
0x4d   125    ...          flag         SET/CLEAR flag
0x47   119                 variavel     work_set
0x4c   118                 flag         CHECK flag
0x06   115                 fluxo        if_begin
0x20   115                 variavel     var op= imediato
0x02   112                 fluxo        evt_next
0x77   111                 ator         entity update
0x42   107                 variavel     member_get
0x41   106                 variavel     member_set por var
0x08   104                 fluxo        end-block
0x04   102                 fluxo        evt_exec (thread)
0x19   101                 fluxo        gosub
0x65   101                 cenario      aot_reset
0x40    98                 variavel     member_set imediato
0x55    95                 som          som posicional (0x80034124)
0x1e    94                 ?            (sem handler medido)
```

### 2.1 ⭐ O achado do censo: as CONDIÇÕES DE `while` são só SEIS

É o dado que decide tudo. O `0x10` (`0x80053364`) avalia a condição **despachando o opcode em
`PC+4`** (`0x80053550`) e usa o retorno como verdade. Se o port não sabe avaliar aquele opcode ele
responde "falso" — e o laço sai na hora, isto é **a cena corre adiantada**. Censo:

```
0x4c 204 cenas · 0x43 50 · 0x4e 17 · 0x6c 4 · 0x1d 2 · 0x6d 1
```

`0x4c` já estava. `0x43` e `0x4e` foram **decodificados neste round** (§3). Sobram 7 cenas.

---

## 3. Os opcodes novos, com o handler de cada um

| op | o que é | handler | prova |
|---|---|---|---|
| `0x12`/`0x13` | **do-while** | `0x80053464` / `0x800534c8` | `0x12` guarda `PC+4` em `obj+0x20` (início) e `PC+4+s16@+2` em `obj+0x60` (saída); `0x13` anda 2, avalia a condição e, se VERDADEIRA, `PC = obj+0x20` (`0x80053530/38`), senão desempilha |
| `0x14`/`0x15`/`0x16`/`0x17`/`0x1b` | **switch/case/esac/default/break** | `0x80053638` … | `0x14`: `a3 = PC+4`; saída em `obj+0x60`; `v1 = lh(0x800d1f46 + byte@+1 *2)`; percorre a lista — `0x16` sai, `0x17` entra no default, `0x15` compara `u16@(a3+4)` e pula `6+u16@(a3+2)` quando não bate; `0x1b` = `PC = obj+0x60` |
| `0x4e` | **compara VAR com imediato** | `0x800547f0` | `u16@+2` = (índice de var no byte baixo, comparador no alto), `s16@+4` = imediato, var lida com `lh` |
| `0x43` | **compara MEMBRO do work com imediato** | `0x80053c74` | idêntico, mas o lado esquerdo vem de `member_get` (`0x80053fac`) sobre `obj+0x154` |

### 3.1 Os 7 comparadores (tabelas `0x80010b78` e `0x80010930`)

Delay slots já resolvidos — está em `ScriptVM.comparar()`:

```
0 0x8005484c  xor + sltiu v0,1     -> a == b
1 0x80054858  delay slt v0,b,a     -> a >  b
2 0x80054860  slt a,b + xori 1     -> a >= b
3 0x8005486c  delay slt v0,a,b     -> a <  b
4 0x80054874  slt b,a + xori 1     -> a <= b
5 0x80054880  xor + sltu zero,v0   -> a != b
6 0x8005488c  and + sltu zero,v0   -> (a & b) != 0
op >= 7 -> 0x80054894 jr $ra com $v0 = 0 = FALSO
```

⚠ Implementar `0x4e`/`0x43` **também mudou os `if` de init**: eles caíam no `_:` e o port entrava
no bloco por omissão (89 salas usam `0x4e`, 44 usam `0x43`). Efeito medido: o total de cenas
alcançáveis numa partida nova caiu de 464 para **352** — porque agora os ramos certos são
recusados. Menos cenas, mas as certas.

---

## 4. ⭐ O `0x18` é ARQUITETURA, não opcode — e é o achado deste round

`0x80053770` faz **`PC += s16@+4`** (delay slot `0x800537b8  sw $a1, 0x1c($a0)`): um salto
relativo. Varredura dos **344** `0x18` do jogo: **217 têm deslocamento NEGATIVO** = aresta de
volta, ou seja **laço infinito por desenho**. O exemplo canônico é a função 41 do `R10D`, que o
init abre com `04 05 19 29`:

```
+0x0002  30 00 01 09 68 42        ; x = 17000
+0x0008  30 00 01 0b b4 e2        ; z = -7500
+0x000e  32 01 00 64 46 37
+0x0014  02                       ; cede o quadro
   … (o mesmo de novo) …
+0x002a  18 ff ff 00 d7 ff        ; PC += -41  ->  volta ao começo, PARA SEMPRE
```

É a **thread de AMBIENTE da rua** (chuva/som), e no motor ela roda **em paralelo ao gameplay** —
não suspende nada. O port só sabe rodar cena como coisa que **suspende** o jogo (`World.cena`
bloqueia pad, RVD, porta e item), então abrir uma dessas como "cena" congelaria o jogador até a
rede de segurança.

➜ **O que falta não é o `0x18`: é um modelo de THREAD CONCORRENTE** (thread de ambiente ×
cinemática). Enquanto não existe, o `0x18` fica em `Cena.OPS_BLOQUEANTES` e as 81 cenas ficam de
fora — o port imprime o motivo em cada uma. Isso também explica por que a lista branca era a
decisão certa antes de haver critério.

---

## 5. O critério, em três níveis

`Cena.auditar(vm, func_id)` percorre o fechamento de chamadas da cena e classifica cada opcode:

1. **IMPLEMENTADO** (`OPS_IMPLEMENTADOS`) — semântica medida e executada.
2. **INÓCUO** — tamanho conhecido (lido dos avanços de PC dos handlers) e sem efeito em fluxo ou
   sincronismo: o intérprete anda o PC e **conta**. No pior caso a cena perde um efeito visual.
   É a maioria do censo (`0x82`, `0x5b`, `0x77`, `0x70`, `0x79`…).
3. **BLOQUEANTE** (`OPS_BLOQUEANTES`) — os dois jeitos de dar errado de verdade: controle de fluxo
   não decodificado (`0x18`/`0x1a`/`0x1c`) e **FMV** (`0x7a`, que o port pularia calado).

Mais o quarto caso, que não é lista: **condição de `while`** que o port não avalia (§2.1).

`World.cena_autorizada()` chama isso e imprime o motivo quando recusa. `World.cenas_recusadas`
guarda a lista — é o backlog do que implementar.

### 5.1 O FREIO DE `while` — 🟡 declarado, e é do port

Implementar o `0x4e` transformou um comportamento à prova de falha (condição desconhecida =
falsa = sai do laço) num **travamento**: a função 13 do `R101` — a que devolve o controle — faz

```
10 06 0a 00 / 4e 00 1a 05 09 00 / 02 / 11 00     =  while (var[26] != 9) { yield }
```

e **`var[26]` é escrita pelo MOTOR**, não pelo script (varri: nenhum store direto em
`0x800d1f7a`). Sem freio a cena morria nos 4000 quadros da rede de segurança. O freio tem dois
valores, e a diferença é medida:

- `WHILE_MAX_SINCRONISMO = 900` para `while (4c 04 …)` = espera pelo **banco 4**, que o `0x81`
  acende na chegada do ator (`0x800169f0` → `0x800788dc(0x800d1fc0)`) e que o port SABE satisfazer
  (`Cena.chegou()`). As esperas reais medidas ficam em 300..640 quadros.
- `WHILE_MAX_OUTRO = 60` para qualquer outra condição — tipicamente estado que o port não modela.

Quando o freio age, a dívida entra em `Cena.debitos` → `World.cena_debitos`. O `R101` termina em
**1422** quadros (era 1362 antes do `0x4e`, e 3999 com o freio único de 900).

---

## 6. ⚠ Bug de regressão consertado no caminho: "o personagem não responde ao input"

Reportado no `-- world` e pelo dono ("não acontece nada"). Causa medida: **a cena pode terminar
com o corpo ENCRAVADO**. Ela move o corpo por caminhos que não passam pelo resolver — o `0x81`
(destino do script), a translação manual (`player+0x34 += k`) e o `+0x12d`, que a própria cena usa
para atravessar o cenário (`cena_r10d.md` §6-4). Terminando dentro de uma caixa inflada pelo raio
450, o resolver rejeita **todo** movimento e o pad fica morto.

Medido: a função 12 do `R101` (gatilho `sce 5`, AOT 11) deixa a Jill em `(-7692, -3600, -11152)`,
de onde ela não anda. Cura: `World._fechar_cena()` passa a rodar `_desencravar()` — o mesmo da
chegada de porta — e registra a dívida quando precisou mexer. O assert está em
`test_cena_world.gd` §4 ("e o personagem RESPONDE ao input depois dela").

---

## 7. A chegada do `R101` — o dono está certo, e a linha do RVD MORREU

O dono relatou: *"a câmera e a posição da Jill estão erradas ao chegar"* e *"no fim da cutscene
inicial a câmera tem de ser a 10 (`R101_10.webp`)"*.

**A câmera 10 no fim CONFERE.** Medido pelo caminho real do jogo antes do relato: a linha de
`cut_chg` da função 3 é `24 → 10 → 25 → 26 → 25 → 26 → 27 → 21 → 19 → 17 → **10**`. A leitura da
cena está certa.

**A câmera de CHEGADA estava errada, e agora sai do dado.** O port emprestava a câmera **7** (da
porta `R102 → R101`). O primeiro `cut_chg` da função 3 é `50 18` = **24**, e o `cut_chg` PRENDE a
câmera (`gs+0x77f4 |= 0x80`, `0x800548f0`) — então mostrar a 7 por 55 quadros era só erro do port.
`World.aplicar_chegada()` passa a usar `Cena.primeira_camera()`.

**A POSIÇÃO continua em dívida, e agora com uma hipótese ENTERRADA.** Duas medições novas:

1. **A cena não posiciona o player.** Varredura exaustiva do fechamento da função 3
   (funções 3, 4, 5, 6, 7, 8, 9, 10, 11, 13) por todo `0x40`/`0x41`/`0x30`/`0x31`/`0x32`/`0x77`:
   os **únicos** escritos no work `1:0` são `40 0f 02 00` (membro `0x0f` = `player+0x09` = NÍVEL 2
   ⇒ y = −3600) e `41 0d 10` (membro `0x0d` = ÂNGULO, de `var[16]`). **Nenhum X, nenhum Z.**
2. **O descriptor da porta é 32 bytes de ZERO.** Bytes crus (`R10D` func 3 +0x0000):
   ```
   61 00 01 21 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00 02 00 00 00 00
   to_pos=(0,0,0) facing=0 stage=0 room=1 cut=0 grupo=0
   ```
   ➜ **`descriptor+0xb` (grupo do RVD) é 0.** A hipótese registrada em `cena_r10d.md` §4.2 ("a
   posição deve vir do grupo do RVD") está **descartada**: não há nada no descriptor de onde vir.

O empréstimo segue, com o critério de ANDAR (§3 de `cena_r101.md`): sai a chegada do `R102`,
`(-4434, −3600, −27933)`, que é o nível 2 que a cena exige e a vizinhança do primeiro `0x81` do
player (`(-8630, −27690)`). 🟡 Continua **DECLARADO** e em `world.cena_debitos`.

### 7.1 O que ainda pode explicar a posição (não medido)

Com o descriptor todo zero, sobra o `door_handler 0x800248e4` fazer algo diferente quando
`to_pos == (0,0,0)` — por exemplo **manter a posição corrente** (é o que o port já faz para
elevador/escada). Se for isso, a chegada no `R101` é a última posição da Jill no `R10D`, que a cena
de saída deixa perto de `x = -32000` (`func 21` manda ela sair de quadro). **Não medi**, e não
invento.

---

## 8. As categorias que o dono listou — onde cada uma está

| categoria | estado | onde |
|---|---|---|
| câmera | ✅ `0x50`/`0x51` | `Cena.cut_chg`/`cut_old`; `world.camera` |
| espera / tempo | ✅ `0x09`/`0x0a`/`0x02`, laços `0x0d`/`0x0f`/`0x10`/`0x11`/`0x12`/`0x13`, `switch` | `vm.gd` `_passo_cena` |
| ator / NPC | ✅ `0x80` (anim por índice), `0x81` (ir até + bit do banco 4), `0x8f` (liga entidade) | `Cena.ator_anim`/`ator_ir`/`ator_ativa` |
| **cenário PERMANENTE** | 🟡 **parcial — ver §8.1** | `0x6e` (colisão), `0x65` (aot_reset), `0x4d` (flag) |
| efeitos / explosão | 🟡 registrado, não desenhado: `0x70`/`0x71`/`0x72`/`0x73`/`0x75`/`0x78` andam o PC e contam | `Cena.auditar().inocuos` |
| trilha e som | 🟡 `0x57`/`0x58`/`0x59` entram em `vm.sons` com os operandos crus; `0x55`/`0x56`/`0x5b` só registrados | §8.2 |
| fade | 🟡 `cena.fade_ativo` traz `abr`, `c0`, `c1`, `T` e o `t` corrente — **ninguém desenha** | §8.2 |

### 8.1 Mudança PERMANENTE de cenário — o que está provado e o que falta

O dono citou isto como o ponto crítico. O que o port já faz sobreviver:

- **colisão**: `0x6e` (`0x800556e0`) escreve em `rects[idx].bits`, e o `world.gd` **relê o RDT na
  carga** (`room.colisao.reset_estado()`) porque o PS1 também relê do CD. Isto é: a mudança de
  collider **NÃO** persiste entre cargas por si — quem a torna permanente é o `if (flag)` do init
  que reexecuta o `0x6e`. Esse caminho funciona, e é o do jogo.
- **flags**: `0x4d` grava no `GameState`, que é serializado no save. É o mecanismo REAL de
  permanência do RE3 — a cena acende a flag e o init da sala reconstrói o cenário a partir dela
  (`cena_r101.md` §2: a própria cena de entrada faz `4d 03 0b 01` para não reprisar).
- **AOT**: `0x65 aot_reset` desativa o gatilho na execução corrente; a permanência é pela flag.

🟡 **O que NÃO está medido**: `0x7b` (`map data write`, 72 salas / 126 cenas, handler
`0x80055568`) e o membro `0x00` do `om` (o `be_flg`, que decidiria objeto quebrado/aberto). Os dois
são candidatos a "objeto que muda e fica assim" e nenhum dos dois foi decodificado. Enquanto isso,
eles são **inócuos** no critério (andam o PC), então a cena roda e o cenário não muda — o que é
visivelmente incompleto, mas não é mentira: `Cena.auditar().inocuos` diz exatamente quais.

### 8.2 O que é da APRESENTAÇÃO (`port/present/*` não é deste round)

1. **Fade do `0x46`**: `cena.fade_ativo` já traz `abr`/`c0`/`c1`/`T`/`t` por quadro. O gancho é
   `World.cena_iniciada`/`cena_terminada` + ler `mundo.cena.fade_ativo` no `_on_tick`.
2. **Som e trilha**: a API a usar é `Audio.tocar_faixa` e `Sfx.tocar_id`. O que o port tem hoje é o
   disparo cru em `vm.sons` (`0x57`/`0x58`/`0x59`) e o registro de `0x55`/`0x56` na linha do tempo.
   Qual campo do `0x55`/`0x56` é id de SE e qual é posição **não está medido** (`cena_r10d.md` §7-5).
3. **HUD**: esconder durante `cena_iniciada`..`cena_terminada`.
4. **SEQ fora do banco**: a cena do `R101` pede **SEQ 22, 24 e 25** no player e o banco `animNN` do
   `PL00.PLD` para em 21 — a apresentação não toca clipe nesses trechos (`has_animation` falha).
   Ou o índice é de outro banco (PLW), ou o de-para `anim%02d` não vale para cena. **NÃO PROVADO**,
   e o `test_cena_r101.gd` cobra isso como dívida conhecida.

---

## 9. Como reproduzir

```bash
# o censo (169 salas) -> port/data/cena_opcodes.json
python tools/scd_cena_censo.py
python tools/scd_cena_censo.py --sala R101

# a cobertura pelo critério do port
godot --headless --audio-driver Dummy --path port \
    --script res://dev/diag_cena_cobertura.gd
COBERTURA_DETALHE=1 godot ... (cena por cena)

# as duas cenas como CASO DE TESTE do sistema
godot --headless --audio-driver Dummy --path port \
    --script res://dev/run_tests.gd -- cena       # 229 asserts
godot --headless --audio-driver Dummy --path port \
    --script res://dev/run_tests.gd -- world      # 110, as 453 portas

# pelo caminho REAL do jogo: R10D -> R101, lendo o AnimationPlayer por quadro
godot --headless --audio-driver Dummy --path port \
    --script res://dev/diag_cena_r101_jogo.gd
```
