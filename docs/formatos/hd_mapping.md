# Mapeamento HD ↔ sala (Método B — autoritativo via cache)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `hd_bg`)
> - **Formato:** cache de runtime `ROOMxxxx.dat` do Classic REbirth = array plano de hashes u32 (tabela sala→assets HD)
> - **Extensão/origem:** `hires/cache/ROOMxxxx.dat` (GOG, **somente leitura**); 170 salas
> - **Ferramenta:** [`tools/hd_match.py`](../../tools/hd_match.py), [`hd_copy.py`](../../tools/hd_copy.py) → `godot/data/hd_map.json`
> - **Decompilado:** **100%** (mapa autoritativo sala→hash resolvido)
> - **Feito:** cache decodificado (99,7% dos hashes casam um `.webp`); agrupamento por câmera (bgd+mask0+mask1); **`stage_offset=1` confirmado** (PC `ROOM0000` = PS1 `STAGE1/R100`, ver [../descobertas.md](../descobertas.md)).
> - **Falta:** alinhar índice de câmera PC↔PS1 (§6). Estrutura da pasta HD em [hd_seamless.md](hd_seamless.md).

> Como casar cada background/máscara HD (Seamless HD Project) com a sala/câmera do jogo.
> **Resultado: o ATALHO funcionou** — o cache do Classic REbirth (`hires/cache/ROOMxxxx.dat`)
> É a tabela autoritativa `sala → hashes`. Não foi preciso quebrar a função de hash nem
> desempacotar os `Rofs*.dat`. Ver também [`hd_seamless.md`](hd_seamless.md) (estrutura da pasta HD).

## 1. Como resolveu: o cache `ROOMxxxx.dat`

Cada arquivo `hires/cache/ROOM<SRRP>.dat` é um **array plano de inteiros de 32 bits
little-endian, sem cabeçalho**. Cada valor de 32 bits é, literalmente, o **nome-hash** (8 dígitos
hex) de um arquivo `.webp` em `hires/` — o mesmo nome que aparece em `bgd/`, `mask0/`, `mask1/`.

```
ROOM<SRRP>.dat  =  uint32_le[ N ]      # N = qtd. de assets HD da sala
cada uint32  ->  "%08X".webp           # ex.: 0xF6E45F06 -> bgd/F6E45F06.webp
```

- Tamanho do arquivo é **sempre múltiplo de 4** (confirmado nos 170 arquivos) → sem padding/cabeçalho.
- **Endianness:** little-endian. Teste: big-endian casou **0%** dos valores; little-endian **99,7%**.
- Os `ROOMxxxx.dat` referenciam **apenas backgrounds e máscaras** (nenhum door/effect/skin/item
  aparece) — ou seja, é o cache específico de "background + máscara de profundidade por sala".

### Validação
- **Estatística:** 3.769 valores de 32 bits em 170 salas; **3.756 (99,7%)** correspondem a um
  arquivo `.webp` existente em `bgd/mask0/mask1`. Os 13 restantes (0,3%) são assets não
  substituídos em HD (ver §5). Validação muito além dos "5 arquivos" pedidos.
- **Visual:** renderizadas 4 câmeras da `ROOM0010` → é claramente **a mesma sala** (armazém,
  piso verde, empilhadeira, mezanino) vista de 4 ângulos → o agrupamento por sala está correto.
  Renderizado background + suas máscaras → as máscaras são os **sprites de oclusão** (vigas/
  estruturas do 1º plano) daquele mesmo cenário → pareamento background↔máscara confirmado.

## 2. Agrupamento por CÂMERA (bgd + mask0 + mask1)

A ordem dos valores no `.dat` é **agrupada por câmera**. O padrão dominante é o tripleto:

```
[ background, mask0, mask1 ]  [ background, mask0, mask1 ]  ...
     └── câmera 0 ──┘              └── câmera 1 ──┘
```

- **Heurística de parsing:** cada `hash de bgd` inicia uma nova câmera; os `hash de mask0/mask1`
  seguintes (até o próximo bgd) pertencem a ela.
- **Robustez:** em **0** casos um asset não-bgd/não-máscara aparece no meio de um grupo, então a
  separação é limpa.
- Nem toda câmera tem máscara: de **1.521 câmeras**, 1.075 têm o tripleto completo (b+m0+m1),
  361 não têm máscara (só background) e 85 são parciais.
- **Máscaras (`mask0`/`mask1`):** WEBP 2048×2048 lossless; são **atlas de sprites de oclusão**
  (blocos do 1º plano que devem cobrir o personagem), não máscaras full-screen. `mask0` e `mask1`
  são duas camadas/planos de prioridade da mesma câmera.

## 3. Nomenclatura do PC e mapeamento PC → PS1

ID de sala do PC (nome do arquivo de cache): `ROOM` + `S`·`RR`·`P` (4 hex):

```
S  = stage/estágio        (1 hex)  — observados 0..6  (+ F = global/compartilhado)
RR = número da sala       (2 hex)
P  = player/variante      (1 hex)  — sempre 0 no RE3 (só Jill)
```

Salas por stage no cache: st0=38, st1=28, st2=24, st3=23, st4=17, st5=15, st6=24, F=1 (total 170).

**PC → PS1 (~1:1), com `stage_offset` parametrizado:**
```
ps1.stage = pc.stage + stage_offset
ps1.room  = pc.room        (mesmo valor)
```
- `stage_offset` está **no `meta` do JSON** (default = **1**, hipótese do coordenador: PC nibble
  0–6 → PS1 STAGE 1–7). **NÃO confirmado** — o naming do PS1 está sendo levantado por outro agente.
  Se o disco PS1 usar o mesmo número de stage do ID de sala, o offset correto é **0**.
- **Pista importante:** o PC **stage 0 compartilha backgrounds com o stage 5** (ex.:
  `ROOM0010`↔`ROOM5010`, `ROOM0070`↔`ROOM5070`, `ROOM00B0`↔`ROOM50B0`) → são as **mesmas áreas
  físicas** revisitadas. Isso ajuda o agente do PS1 a fixar o offset e a entender salas repetidas.

## 4. Arquivo gerado: `godot/data/hd_map.json`

Schema:
```jsonc
{
  "meta": { "stage_offset": 1, "endianness": "...", "coverage_note": "...", "caveats": [...] },
  "rooms": {
    "1000": {
      "pc":  { "stage":1, "room":0, "player":0, "id":"ROOM1000" },
      "ps1": { "stage":2, "room":0, "note":"stage via stage_offset (unconfirmed)" },
      "global": false,
      "n_cameras": 12,
      "cameras": [
        { "index":0, "background":"F6E45F06", "mask0":"D0792CA3", "mask1":"2F7CA3E9", "masks_extra":[] },
        ...
      ],
      "other_assets": [], "unresolved": []
    }
  },
  "backgrounds": {                       // índice reverso: hash -> onde aparece
    "F6E45F06": { "webp":"hires/bgd/F6E45F06.webp", "rooms":["1000", ...] }
  }
}
```
- `background`/`mask0`/`mask1` são os **stems** dos `.webp` (arquivo = `hires/<pasta>/<HASH>.webp`).
- Para achar o HD de uma câmera PS1: `rooms[SRRP].cameras[i].background` → `hires/bgd/<hash>.webp`.
- **Câmera i** aqui é o índice na ordem do cache; ainda **falta alinhar** com o índice de câmera
  do PS1 (ver §6).

## 5. Cobertura e limitações

- **Cobertura:** 1.232 de 1.316 backgrounds (**94%**) referenciados; **170 salas**.
- **Só salas VISITADAS:** o cache é gerado em runtime conforme se joga. Os ~6% de backgrounds
  não referenciados são salas que o jogador ainda não visitou (ou backgrounds alternativos/não usados).
- **277 backgrounds aparecem em >1 sala** (áreas revisitadas). O índice `backgrounds[hash].rooms`
  lista todas. Para backgrounds, isso é normal (mesma área, stages diferentes).
- **13 hashes referenciados sem arquivo** (`rooms[].unresolved`): assets **não** substituídos em HD
  (o jogo usa o original SD). Concentrados em `ROOMFFFF` (global) e algumas salas.
- **20 colisões de hash entre pastas** (mesmo conteúdo em 2 categorias, ex.: bgd+slide) — resolvidas
  por prioridade (bgd > máscara > outros).

## 6. Pendências

1. ~~**`stage_offset`** — confirmar 0 vs 1~~ ✅ **RESOLVIDO: `stage_offset = 1`** (PC `ROOM0000`
   = PS1 `STAGE1/R100`, confirmado por render; ver [../descobertas.md](../descobertas.md)).
2. **Índice de câmera PS1 ↔ ordem do cache** — a ordem das câmeras no `.dat` provavelmente segue a
   ordem de câmera do engine, mas **validar** contra a contagem/ordem de câmeras extraída do
   `.RDT`/`.ARD` do PS1 (nº de câmeras por sala deve bater com `n_cameras`).
3. **Completar os 6% restantes** — jogar as salas faltantes (regenera o cache) **ou** cair para o
   fallback do Método A (casamento por imagem) só nesses casos.

## 7. Sobre a função de hash (não foi necessária)

O nome dos `.webp` é um **hash de conteúdo de 32 bits** cujo algoritmo **não foi identificado** —
e **não precisou ser**, porque o cache já fornece o índice reverso `sala → hash`. A engenharia
reversa do algoritmo de hash e o desempacotamento dos `Rofs*.dat` (passos 2a/2b do plano) só
seriam necessários para mapear salas que **nunca** entram no cache; nesse cenário, o fallback
recomendado é o **Método A (pHash/SSIM)** de [`hd_seamless.md`](hd_seamless.md), que independe do hash.

## 8. Licença

Assets do **Seamless HD Project** (fãs) sobre arte da **Capcom**. Uso pessoal/local ok;
**distribuição exige aval dos autores + Capcom**. Ver nota completa em [`hd_seamless.md`](hd_seamless.md §6).
