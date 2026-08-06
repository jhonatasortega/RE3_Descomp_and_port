# Plano de ação — decomp-first

> Companheiro do [`PROGRESS.md`](PROGRESS.md) (onde estamos) e da fonte [`progress.json`](progress.json).
> Regra nova (pós-reset): **profundidade + fidelidade > largura**. Uma coisa por vez, você valida cada passo.
> Ordem macro pedida: **1) documentar o decomp · 2) limpar o conteúdo · 3) só então voltar ao protótipo Godot.**

## Princípios
- **Fonte única de verdade:** `docs/decomp/` (este hub). Trackers antigos consolidados aqui.
- **Dois eixos sempre:** só marco "vinculado" o que você confirmou no protótipo.
- **Sem sprawl:** nada de N features paralelas meio-prontas. Fecha e valida antes de somar.
- **Fidelidade:** preferir poucas coisas 100% fiéis ao RE3 a muitas aproximadas.

---

## Fase A — Limpeza & consolidação (documentação/conteúdo)  ← FOCO AGORA
- [x] Hub de decomp com `progress.json` + `PROGRESS.md` gerado + este plano.
- [ ] **Consolidar docs sobrepostos:** `STATUS_GAME.md` (apagado, era redundante); `progresso.md` vira histórico; `plano.md` = estratégia macro (mantido); `descobertas.md` revisar/fundir.
- [ ] **Auditar `godot/assets` e `godot/data`:** listar o que está extraído vs lixo/duplicado; marcar o que é "vinculado" de verdade.
- [ ] **Auditar `tools/`:** 30 scripts — marcar quais são o pipeline canônico vs experimentos.
- [ ] Fechar cada `docs/formatos/*.md` com o status real (o que falta em cada formato).

## Fase B — Decomp prioritário (alto peso, baixo % — destrava o resto)
Ordenado por alavancagem:
1. [ ] **Handler de transição de sala (exe)** → resolve `door_dest` (sala→sala). Destrava TODAS as transições. (dec 0%, peso 4)
2. [ ] **Mesh empacotado dos inimigos (R###.BIN sec2/4)** — abordagem NOVA: pesquisar o formato de mesh de inimigo do RE2/RE3 PS1 (difere do MD1 do player; há doc da comunidade). Fecha o 1º zumbi. (dec 55%, peso 5)
3. [ ] **Mira / tiro / dano (exe)** — o próximo do core de gameplay (você quer validar a mira). (dec 0%, peso 5)
4. [ ] **Oclusão (mask_data_ptr)** — completar o formato do bloco de máscara p/ oclusão pixel-exata. (dec 60%, peso 4)
5. [ ] **IA (zumbi/Nemesis) no exe** — depois do combate. (dec 0%, peso 5)

## Fase C — Restaurar o NÚCLEO do protótipo (o que regrediu)  [depois de A]
Fatia vertical fiel de 1 sala, cada item validado por você:
- [ ] **Remover o HUD** in-game (RE3 não tem — tela limpa).
- [ ] **Desligar a oclusão** quebrada/invertida até refazê-la certa (Fase B4).
- [ ] **Corrigir loadout inicial** do inventário (Jill começa com Handgun + munição, não o arsenal).
- [ ] **Ligar o som** (AudioManager.play_bgm ao entrar na sala) — hoje sem som.
- [ ] **Câmera:** revisitar a entrada por lado (não centralizar no corte). Validar "isso é RE3".
- [ ] Validar **mira** + **subir em item** (resto da movimentação já está 100%).

## Fase D — Vinculação em largura (só com A–C sólidos)
- [ ] Generalizar o carregamento de sala (qualquer R###, não só R100).
- [ ] Transições entre salas (usa `room_graph.json` + `door_dest` da Fase B1).
- [ ] Integrar spawns/itens/triggers do SCD no protótipo.
- [ ] Menus/save, cinemáticas (FMV), puzzles.

## Fase E — v2 3D (visão de longo prazo)
- [ ] Reconstrução 3D por sala (colisão+frustums+plantas HD como blueprint). Ver `v2/README.md`.

---

## Como manter o tracker
Editar `docs/decomp/progress.json` (ajustar `decompilado`/`vinculado`/`nota`) e rodar:
```
python tools/decomp_progress.py
```
Isso regenera `PROGRESS.md`. **Nunca** editar o `.md` à mão.
