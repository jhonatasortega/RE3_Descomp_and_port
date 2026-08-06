# Referência da comunidade — Evil Resource (RE3)

> **Papel:** roster de **nomes** (itens/armas/inimigos) para dar nome aos IDs extraídos do
> binário. Usado por [../formatos/scd_gameplay.md](../formatos/scd_gameplay.md) (itens/inimigos),
> [../formatos/exe.md](../formatos/exe.md) (tabelas SCE) e [../godot_ui.md](../godot_ui.md).
> Índice em [../README.md](../README.md). **O mapeamento hex↔nome ainda é "a confirmar".**

Fonte: https://www.evilresource.com/resident-evil-3-nemesis (indicada pelo usuário).

> ⚠️ O site **não expõe os IDs internos** (hex) do jogo — traz **nomes** (roster), **mapas**
> por área e **localizações**. Serve para: (1) dar NOME aos IDs que extraímos do binário,
> (2) validar placements de item/inimigo, (3) validar o grafo do mapa (portas→destinos).

## Como isto ajuda o projeto
- **Itens (opcode 0x68):** temos IDs reais (`0x21, 0x41, 0x04, 0x15, 0x42, 0xa0, 0x9b, 0x99`).
  Falta a **ordem interna de ID** (do binário ou de fonte de mod) para casar com estes nomes.
  Ex. provável: `0x15×30` = *hand gun bullets*; `0x04×7` = munição/consumível pequeno.
- **Modelos de arma** `PL00W00..W14` (0x00–0x14, 21 modelos) → mapear para a lista de *weaponry*
  (armas + peças que a Jill segura). A confirmar pelo agente de modelos.
- **Inimigos:** roster de 15 tipos abaixo — base para a caça ao `sce_em_set` e para os
  modelos embutidos nos `R###.BIN`.
- **Mapas** (5 áreas) → validação visual do grafo de salas derivado do binário.

## Áreas / mapas
Uptown and Downtown · Police Station · Raccoon City Clock Tower · Raccoon City Hospital ·
Raccoon City Outskirts.

## Itens (65)
game instructions A/B, reloading tool, ink ribbon, backdoor key, lighter oil, empty lighter,
lighter, card case, STARS card (Brad/Jill), STARS key, lockpick, sapphire, power cable,
fire hook, emerald, rust hex crank, wrench, future compass, book of wisdom, battery, fuse,
fire hose, square crank, machine oil, oil additive, mixed oil, bezel key, winder key,
chronos chain, chronos key, obsidian ball, amber ball, crystal ball, gold/silver/chronos gear,
tape recorder, sickroom key, medium base, vaccine (medium/base/vaccine), main gate key,
graveyard key, iron pipe, rear gate key, facility key, system disk, water sample,
facility key (coded), card key, boutique key, green/red/blue herb, first aid spray/box,
mixed herb (GG/GR/GB/GGB/GGG/GRB).

## Armaria (41)
knife, M92F custom, SIGpro SP2009, STI Eagle 6.0, Benelli M3S, Western Custom M37,
HK P grenade launcher, M4A1 assault rifle, S&W M629C, mine thrower, M66 rocket launcher,
gatling gun · eagle parts A/B, M37 parts A/B · hand gun bullets (+enhanced),
shotgun shells (+enhanced), grenade/acid/flame/freeze rounds, assault rifle bullets,
magnum bullets, mine thrower rounds, infinite bullets · gun powder A/B/C (+ combinações).

## Inimigos (15)
zombie, zombie dog, crow, drain deimos, brain sucker, grave digger, sliding worm,
giant spider, small spider, hunter beta, hunter gamma, Nicholai (helicopter),
**Nemesis** (1ª/2ª/3ª forma).
