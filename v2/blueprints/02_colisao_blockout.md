# 02 · Colisão → blockout 3D (RESOLVIDO — revisado 2026-08-04)

> Fonte: [`../../docs/formatos/ARD.md §3.6–3.8`](../../docs/formatos/ARD.md) (formato FECHADO
> contra o EXE em 2026-08) e o port 1:1 (`port/room/collision.gd`, implementação de referência).
> Ferramenta: `tools/rdt_collision.py` → `{NOSTALGIA_OUT}/data/STAGE{n}/{sala}_col.json`.
>
> ⚠️ **Esta página substitui a leitura antiga.** O que aqui se chamava de "y = altura do chão"
> e "h = topo" era um erro: `+0x08` é um **bitfield de forma/estado** e `+0x0A` é máscara.
> Tudo abaixo foi provado por desassembly (endereços no ARD.md) e validado em jogo no port.

## O que é

O bloco de **colisão (SCA)** do RDT (`offset_table[6]`) dá, por sala, uma lista de
**registros de forma** no plano XZ — as posições **reais** de paredes, móveis, rampas e
escadas. É o **blockout 3D exato** de cada sala, incluindo os **desníveis**: o esqueleto
navegável (com andares e rampas!) já vem pronto, sem precisar medir na foto.

## Formato (unidades PS1; 1 m ≈ 808 un; Y cresce PARA BAIXO)

```
Cabeçalho 16 B:
  +0x00 u32 count          (inclui o cabeçalho como registro 0)
  +0x04 s16 cx1, cz1       centro 1 (broadphase de quadrante)
  +0x08 s16 cx2, cz2       centro 2 (pode ser DIFERENTE do 1)
  +0x0E s16 piso_padrao    Y de piso fallback da sala (0 em 154/169)

Por registro (16 B):
  +0x00 s16 f0, f1         par de coordenadas 1 (x, z) — ordem crua
  +0x04 s16 f2, f3         par de coordenadas 2
  +0x08 u16 bits           0..3 FORMA · 4..5 canto/sentido · 6..15 estado (script, opcode 0x6e)
  +0x0A u16 mask           0..7 quadrantes · 8..11 arestas (formas 9/10) · bit 12 = GIRADO 45°
  +0x0C s8  base           base em Y = -1800 × valor (0 = térreo)
  +0x0D s8  nivel_max      teto da FAIXA DE NÍVEIS em que o registro é colisor ativo
  +0x0E s16 topo           topo em Y (para pisos/plataformas, é a SUPERFÍCIE onde se pisa)

Depois dos registros: GRID de broadphase 16×16 (u16[256] + listas u8 terminadas em 0xFF;
célula = ((x+32768)>>12) + ((z+32768)>>12)*16) — irrelevante para modelagem.
```

### As formas (o que modelar em 3D)

| forma | geometria 3D | n no jogo |
|---|---|---|
| 0 | **cilindro** inscrito na caixa (raio = largura/2) — pilares, barris, mesas redondas | 632 |
| 1, 7 | **caixa cheia** `[f0..f2]×[f1..f3]`, do `topo` até `-1800×base` | 3163 |
| 2 | **mureta** na linha média em Z (+ 2 diagonais de acabamento) | 484 |
| 3 | **mureta** na linha média em X (+ 2 diagonais) | 373 |
| 4 | cruz "+" das duas linhas médias | 17 |
| 5 | um segmento diagonal `(f0,f1)-(f2,f3)` | 3 |
| 6 | **parede em "L"**: 2 arestas perpendiculares; o canto vem de `bits & 0x30` | 463 |
| 9, 10 | **RAMPA/ESCADA** (ver seção abaixo) — o desnível navegável | 121 |
| 12 | **cone radial** (montículo: centro alto, borda baixa) | 5 |
| 8, 11 | marcadores sem colisão | 28 |

**Importante para o blockout:** formas 2/3/4/6 **não são caixas cheias** — o personagem
circula por "dentro" da envolvente; só as arestas bloqueiam. Modelar como mureta/L, não
como bloco sólido (no port, tratá-las como bloco selava salas inteiras).

## Escadas, rampas e andares (NOVO — o desnível 3D exato)

O RE3 **não integra o Y do personagem**: todo frame o motor rederiva o Y do piso
(`floor_height`, `0x8004d720`) a partir destes mesmos registros. Para o 3D isso significa
que **a geometria vertical inteira está aqui**:

1. **Andares**: a unidade de nível é **1800 un (≈ 2,23 m)**; `nível = -Y/1800`. Plataforma
   plana = registro **forma 1** com bit de piso (`bits & 0x8000`) e sem arestas
   (`mask & 0x0F00 == 0`): a superfície é `topo` (ex.: passarela da R101 em `topo=-3600`).
2. **Rampa/escada (formas 9/10)** — a receita 3D exata (`0x8004e10c`):
   - ponta BAIXA em `Y = -1800×base`; ponta ALTA em `Y = topo + 1800`;
   - **sentido de subida** em `bits & 0x30`: `0` = sobe em +X · `1` = sobe em −X ·
     `2` = sobe em +Z · `3` = sobe em −Z;
   - o Y interpola LINEARMENTE ao longo do eixo do sentido, clampado nas pontas.
     Ex. (escada da R101): `raw=[-29579,-26045,-26634,-22265]`, `base=2 (Y=-3600)`,
     `topo=-9000`, sentido 2 → plano inclinado de `Y=-3600` (em `z=-26045`) a `Y=-7200`
     (em `z=-22265`). **É literalmente a malha da rampa.**
   - forma 10 = mesma matemática com visual de escada → modelar degraus sobre o plano
     inclinado.
3. **Cone (forma 12)**: centro em `topo`, borda em `-1800×base`, raio = largura/2 —
   montículos/entulho.
4. **Faixa de atividade** (`+0x0C..+0x0D`): em quais andares o registro é colisor. Padrão
   dos dados: plataforma com superfície no nível L tem `nivel_max = L−1` (colide com quem
   está ABAIXO dela; quem está em cima anda por ela). As paredes da moldura usam 0..15.
5. **Piso padrão** (`piso_padrao`): o Y do chão fora de qualquer registro — o térreo da
   sala (0 em 154/169; ex. de exceção: garagem R201 = −16200).
6. **Grupo de câmera = andar**: o seletor de zonas RVD (`gs+0x2495`) é o **nível do piso**
   do personagem, reescrito todo frame — as zonas de troca de câmera de cada andar usam o
   número do andar como grupo (R101: grupos 1..4 = pisos −1800..−7200). Ao posicionar
   câmeras da v2 por andar, esse é o vínculo.

### Bônus para a v2: zonas de prioridade (seção 14 do RDT)

`offset_table[14]` (78/169 salas) traz **zonas no chão** (RECT/QUAD + nº de banco) que o
motor usa para decidir a camada de oclusão por região — na prática um **zoneamento por
área/planta da sala** (exportado em `priority_zones` no `_col.json`). Útil como divisão
semântica dos ambientes ao modelar.

## Como usar na v2

1. **Piso:** `piso_padrao` + plataformas (forma 1 com bit de piso) + rampas 9/10 = o
   TERRENO 3D completo, com desníveis e escadas nas posições e inclinações exatas.
2. **Paredes:** os 4 primeiros registros são a moldura da sala (faixa 0..15, `topo=-28800`).
3. **Móveis:** forma 1/7 = caixas; forma 0 = cilindros; formas 2/3/4/6 = muretas/L
   (NÃO são blocos cheios); usar `topo`/`-1800×base` como extensão vertical real.
4. **Navegação (se a v2 quiser andar como o jogo):** raio do personagem = **450 un**
   (constante do ator do player, `0x80033538`); movimento clampa na face da caixa inflada
   pelo raio; o Y vem sempre de `floor_height` — ver `port/room/collision.gd`.
5. O script Blender [`../reconstruction/build_stages_from_json.py`](../reconstruction/build_stages_from_json.py)
   gera chão + paredes + portas do `{sala}_col.json` — **atualizar para**: (a) ler `raw` +
   `forma` (não só a envolvente), (b) gerar planos inclinados para 9/10, cilindros para 0
   e muretas para 2/3/6, (c) usar `topo`/`base_y` como altura em vez de constantes.

> Diferença v1→v2: na v1 (port) esses registros movem a Jill em 30 Hz; na v2 são a
> **geometria base 3D** sobre a qual se modela o cenário fiel (encaixando nas fotos HD).
