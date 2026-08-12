extends RefCounted
## Regras de item (descritor, cura, receitas) e a fonte de texto — tudo contra o valor do EXE.
## Se alguém "arredondar" um número aqui, o teste acusa: cada assert traz o endereço de origem.


func run(t: Object) -> bool:
	# ── DESCRITOR (`0x800a0514`, 4 B por item; byte 0 = categoria) ──
	t.eq(Itens.categoria(0x01), Itens.CAT_ARMA, "Faca é arma (cat 1)")
	t.eq(Itens.categoria(0x21), Itens.CAT_CURA, "Erva verde é cura (cat 3)")
	t.eq(Itens.categoria(0x73), Itens.CAT_CHAVE, "Chave do armazém é chave (cat 5)")
	t.check(Itens.equipavel(0x03), "Hand Gun é equipável")
	t.check(not Itens.equipavel(0x21), "erva não é equipável")
	t.eq(Itens.maximo(0x03), 15, "Hand Gun empilha 15 (capacidade do pente)")

	# ── CURA (tabela `0x80010e4c`; "cheio" = (u8)maxHP, 1/2 = >>1, 1/4 = >>2) ──
	var maxhp := 200
	t.eq(int(Itens.cura_de(0x20, maxhp)["hp"]), 200, "F. Aid Spray cura cheio")
	t.eq(int(Itens.cura_de(0x21, maxhp)["hp"]), 50, "Erva verde cura maxHP/4")
	t.eq(int(Itens.cura_de(0x24, maxhp)["hp"]), 100, "Mixed (V+V) cura maxHP/2")
	t.check(bool(Itens.cura_de(0x22, maxhp)["veneno"]), "Erva azul cura veneno")
	t.eq(int(Itens.cura_de(0x22, maxhp)["hp"]), 0, "Erva azul não cura HP")
	t.check(not bool(Itens.cura_de(0x23, maxhp)["valido"]),
		"Erva vermelha sozinha não faz efeito (o handler só mostra a mensagem 7)")
	t.check(bool(Itens.cura_de(0x2A, maxhp)["gasta_um"]),
		"F. Aid Box gasta 1 e não desaparece")

	# ── CONDIÇÃO (`0x8006e598`): limiares exatos ──
	t.eq(Itens.condicao(101, 0), 0, "hp 101 ainda é FINE")
	t.eq(Itens.condicao(100, 0), 1, "hp 100 já é CAUTION")
	t.eq(Itens.condicao(41, 0), 1, "hp 41 é CAUTION")
	t.eq(Itens.condicao(40, 0), 2, "hp 40 é CAUTION 2")
	t.eq(Itens.condicao(21, 0), 2, "hp 21 é CAUTION 2")
	t.eq(Itens.condicao(20, 0), 3, "hp 20 é DANGER")
	t.eq(Itens.condicao(200, 0x200), 4, "veneno vence o HP (flag 0x200)")
	t.eq(Itens.condicao(200, 0x100), 5, "vírus vence tudo (flag 0x100)")

	# ── RECEITAS (`0x800a07c4`, busca linear e SIMÉTRICA em `0x8006a898`) ──
	t.eq(Itens.n_receitas(), 125, "125 receitas na tabela do EXE")
	var r := Itens.receita(0x21, 0x21)
	t.eq(int(r.get("c", 0)), 0x24, "erva+erva = Mixed Herb 0x24")
	t.eq(int(r.get("kind", -1)), Itens.REC_SIMPLES, "erva+erva é receita simples")
	t.eq(int(Itens.receita(0x21, 0x22).get("c", 0)), 0x25, "verde+azul = 0x25")
	t.eq(int(Itens.receita(0x21, 0x23).get("c", 0)), 0x26, "verde+vermelha = 0x26")
	var ra := Itens.receita(0x21, 0x22)
	var rb := Itens.receita(0x22, 0x21)
	t.eq(String(ra.get("addr", "a")), String(rb.get("addr", "b")),
		"a busca é simétrica: a+b e b+a acham o mesmo registro")
	t.eq(int(Itens.receita(0x03, 0x15).get("kind", -1)), Itens.REC_RECARREGAR,
		"arma + munição é recarregar")
	t.check(Itens.receita(0x21, 0x73).is_empty(), "erva + chave não combina")
	t.eq(Itens.municao_da_arma(0x03), 0x15, "Hand Gun usa H. Gun Bullets")
	t.eq(Itens.municao_da_arma(0x04), 0x17, "Shotgun usa Shotgun Shells")

	if not _receitas(t):
		return false
	if not _icones(t):
		return false
	if not _fita_no_facil(t):
		return false

	# ── FONTE (`ETC/TEXU.TIM` + tabela de larguras `0x80098dd0`) ──
	t.eq(Texto.codigo(0x20), 0, "espaço vira cod 0")
	t.eq(Texto.codigo(0x41), 0x41 - 0x24, "cod = ASCII - 0x24 (A)")
	t.eq(Texto.codigo(0x01), -1, "fora da faixa devolve -1")
	t.eq(Texto.avanco(Texto.codigo(0x41)), 14, "'A' avança 14")
	t.eq(Texto.avanco(Texto.codigo(0x69)), 10, "'i' avança 10 (fonte é PROPORCIONAL)")
	t.eq(Texto.trim(Texto.codigo(0x69)), 4, "'i' tem trim_left 4")
	t.check(Texto.largura("iii") < Texto.largura("AAA"),
		"três 'i' são mais estreitos que três 'A' (se der igual, virou monoespaçada)")
	var linhas := Texto.quebrar("A A A A A A A A A A A A A A A A", 60)
	t.check(linhas.size() > 1, "quebra por LARGURA em pixels, não por nº de caracteres",
		"%d linhas" % linhas.size())

	# ── ACENTOS (o bug que comia letras em PT-BR) ──
	# Os glifos acentuados NÃO estão na faixa ASCII: os códigos vêm do mapa lido da folha
	# auto-rotulada do atlas HD (`tools/font_pt.py`). Antes `codigo()` devolvia -1 e o desenho
	# PULAVA o caractere em silêncio.
	t.eq(Texto.codigo_do_char("á"), 139, "á = código 139 no atlas HD")
	t.eq(Texto.codigo_do_char("ç"), 115, "ç = 115")
	t.eq(Texto.codigo_do_char("ã"), 159, "ã = 159 (o encoding.xml do mod diz 88, que é ä aqui)")
	t.eq(Texto.codigo_do_char("à"), 160, "à = 160")
	t.eq(Texto.codigo_do_char("ê"), 103, "ê = 103")
	t.eq(Texto.codigo_do_char("õ"), 129, "õ = 129")
	t.eq(Texto.codigo_do_char("Á"), 138, "Á = 138 (maiúscula tem glifo próprio)")
	var frase := "Está escrito ação, coração e você — não pode faltar letra"
	var perdidas := 0
	for i in frase.length():
		var ch := frase[i]
		if ch == " " or ch == ",":
			continue
		if Texto.codigo_do_char(ch) < 0:
			perdidas += 1
	t.check(perdidas <= 1, "frase em PT-BR não perde letras (só o travessão pode faltar)",
		"%d sem glifo" % perdidas)
	t.check(Texto.largura("Está") > Texto.largura("Est"),
		"o glifo acentuado ENTRA na largura (se não, ele não está sendo desenhado)")

	return true


func _slot(id: int, qtd: int, flags := 0) -> Dictionary:
	return {"id": id, "qtd": qtd, "flags": flags}


func _receitas(t: Object) -> bool:
	## ══ OS 7 TIPOS DE RECEITA (`0x80010e9c[kind]`, executor `0x80068024`) ══
	t.group("combinar")
	## PRIORIDADE DO DONO: Prensadora (`0x82`) + Pólvora A (`0x61`) → Balas de pistola (`0x15`).
	## O registro é `0x800a0abc` (kind 2, `n = 15`). Com o contador de mistura em 0 o bônus é +0%
	## (`0x800a0bf4`: `cnt <= 2` → 0 décimos), então tem de sair EXATAMENTE 15.
	var inv: Array = [_slot(0x82, 3), _slot(0x61, 1)]
	var r := Itens.combinar(inv, 0, 1, {"niveis": [0, 0, 0, 0]})
	t.check(bool(r["ok"]), "Prensadora + Pólvora A COMBINA (era o relato do dono)",
		String(r.get("motivo", "")))
	t.eq(int(r["kind"]), Itens.REC_POLVORA_MUNICAO, "é o kind 2 (pólvora → munição)")
	t.eq(int(r["qtd"]), 15, "quantidade base do registro `0x800a0abc` (n=15), bônus +0%")
	var mud: Dictionary = r["mudancas"]
	t.eq(int((mud[1] as Dictionary)["id"]), 0x15, "o slot da PÓLVORA vira Balas de pistola")
	t.eq(int((mud[1] as Dictionary)["qtd"]), 15, "com a quantidade calculada")
	t.eq(int((mud[0] as Dictionary)["qtd"]), 2,
		"a Prensadora perde 1 unidade por craft (`0x6006821c`: ctx[0x64]=4)")
	t.eq(int((r["niveis"] as Array)[0]), 1,
		"o NÍVEL DE MISTURA do grupo 0 subiu (`inv+0x12c`, `0x80068118`)")

	## A ferramenta na ÚLTIMA unidade some (ctx[0x64] = 3), e o slot da pólvora ainda recebe.
	var inv2: Array = [_slot(0x82, 1), _slot(0x61, 1)]
	var r2 := Itens.combinar(inv2, 0, 1, {"niveis": [0, 0, 0, 0]})
	t.eq(int(((r2["mudancas"] as Dictionary)[0] as Dictionary)["id"]), 0,
		"Prensadora com 1 unidade ESVAZIA o slot (ctx[0x64] = 3)")
	t.eq(int(((r2["mudancas"] as Dictionary)[1] as Dictionary)["id"]), 0x15,
		"e a munição ainda vai para o slot da pólvora")

	## OS TRÊS TIPOS DE PÓLVORA com a Prensadora, cada um com o `n` do registro dele.
	for par: Array in [[0x61, 0x15, 15], [0x62, 0x17, 7], [0x63, 0x18, 10]]:
		var pol := int(par[0])
		var esperado_id := int(par[1])
		var esperado_n := int(par[2])
		var rr := Itens.combinar([_slot(0x82, 5), _slot(pol, 1)], 0, 1, {"niveis": [0, 0, 0, 0]})
		var novo: Dictionary = (rr["mudancas"] as Dictionary)[1]
		t.eq(int(novo["id"]), esperado_id,
			"Prensadora + pólvora 0x%02x -> munição 0x%02x" % [pol, esperado_id])
		t.eq(int(rr["qtd"]), esperado_n,
			"pólvora 0x%02x: n do registro = %d" % [pol, esperado_n])

	## BÔNUS DE PERÍCIA (`0x800a0bf4`, os 4 blocos idênticos): +0/+10/+30/+50/+70%.
	t.eq(Itens.grupo_da_municao(0x15), 0, "H. Gun Bullets é grupo 0 (`0x800a00ec`)")
	t.eq(Itens.grupo_da_municao(0x17), 1, "Shotgun Shells é grupo 1")
	t.eq(Itens.grupo_da_municao(0x16), 2, "Magnum Bullets é grupo 2")
	t.eq(Itens.grupo_da_municao(0x18), 3, "Grenade Rounds é grupo 3")
	t.eq(Itens.bonus_decimos(0, 2), 0, "cnt 2 -> +0% (limiar 2)")
	t.eq(Itens.bonus_decimos(0, 3), 1, "cnt 3 -> +10% (limiar 5)")
	t.eq(Itens.bonus_decimos(0, 6), 3, "cnt 6 -> +30% (limiar 10)")
	t.eq(Itens.bonus_decimos(0, 11), 5, "cnt 11 -> +50% (limiar 20)")
	t.eq(Itens.bonus_decimos(0, 21), 7, "cnt 21 -> +70% (limiar 250)")
	## `qty = n + (n*bonus)/10`, arredondando quando `(n*bonus)%10 >= 5`. n=15, +10% = 16,5 -> 17.
	t.eq(Itens.quantidade_polvora(15, 0x15, 3, false), 17,
		"15 com +10% = 16,5 e o EXE arredonda para cima (`(n*bonus)%10 >= 5`)")
	t.eq(Itens.quantidade_polvora(15, 0x15, 6, false), 20, "15 com +30% = 19,5 -> 20")
	t.eq(Itens.quantidade_polvora(7, 0x17, 11, false), 11, "7 com +50% = 10,5 -> 11")
	## MODO FÁCIL dobra (flag `0x17` do banco 0 = bit `0x100` de `0x800cc858`).
	t.eq(Itens.quantidade_polvora(15, 0x15, 0, true), 30,
		"no MODO FÁCIL a quantidade dobra (`0x80068118`)")
	## Munição "E" ganha bônus MENOR (remap `0x80010e7c`: 3->1, 5->3, 7->5).
	t.eq(Itens.quantidade_polvora(15, 0x1E, 6, false), 17,
		"munição E com cnt 6: bônus 3 vira 1 -> +10% (remap `0x80010e7c`)")

	## A PERGUNTA "normal ou melhorada?" só existe nos grupos 0 e 1 e só com `cnt > 6`.
	var r3 := Itens.combinar([_slot(0x82, 9), _slot(0x61, 1)], 0, 1, {"niveis": [6, 0, 0, 0]})
	t.check(not bool(r3["pergunta"]), "cnt 6 ainda NÃO pergunta (`slt 6, cnt` em `0x80067d80`)")
	var r4 := Itens.combinar([_slot(0x82, 9), _slot(0x61, 1)], 0, 1, {"niveis": [7, 0, 0, 0]})
	t.check(bool(r4["pergunta"]), "cnt 7 PERGUNTA (o '7 vezes' das Instruções do Jogo B)")
	var r5 := Itens.combinar([_slot(0x82, 9), _slot(0x61, 1)],
		0, 1, {"niveis": [7, 0, 0, 0], "melhorada": true})
	t.eq(int(((r5["mudancas"] as Dictionary)[1] as Dictionary)["id"]), 0x1E,
		"respondendo 'melhorada' usa o REGISTRO SEGUINTE do par (`ctx[0x58] += 8`)")
	var r6 := Itens.combinar([_slot(0x82, 9), _slot(0x63, 1)],
		0, 1, {"niveis": [0, 0, 0, 9], "melhorada": true})
	t.check(not bool(r6["pergunta"]),
		"grupo 3 (granada) NUNCA pergunta — não existe munição E para ele")

	## COMBINAÇÃO INVÁLIDA: não consome nada.
	var invx: Array = [_slot(0x21, 1), _slot(0x73, 1)]
	var rx := Itens.combinar(invx, 0, 1, {})
	t.check(not bool(rx["ok"]), "erva + chave não combina")
	t.eq((rx["mudancas"] as Dictionary).size(), 0, "combinação inválida NÃO consome nada")
	t.eq(int((invx[0] as Dictionary)["qtd"]), 1, "o slot de origem fica intacto")
	t.eq(int((invx[1] as Dictionary)["qtd"]), 1, "o slot de destino fica intacto")
	t.eq((Itens.combinar([_slot(0x21, 1), _slot(0, 0)], 0, 1, {})["mudancas"]
		as Dictionary).size(), 0, "slot vazio também não consome nada")

	## LIMITE DE PILHA do item gerado. O EXE **não** faz clamp (`s2->qty = ctx[0x65]` em
	## `0x80068f30`); o resolvedor sinaliza em `estourou_pilha`. A aritmética prova que na prática
	## não estoura: maior `n` = 60, maior bônus +70%, fácil dobra -> 204 <= max 250.
	t.eq(Itens.maximo(0x15), 250, "munição empilha 250 no descritor (`0x800a0514`)")
	var pior := Itens.quantidade_polvora(60, 0x15, 999, true)
	t.eq(pior, 204, "pior caso possível: 60 +70% = 102, dobrado no fácil = 204")
	t.check(pior <= Itens.maximo(0x15), "o pior caso ainda cabe no empilhamento de 250")
	t.check(not bool(Itens.combinar([_slot(0x82, 9), _slot(0x6B, 1)],
		0, 1, {"niveis": [999, 0, 0, 0], "facil": true})["estourou_pilha"]),
		"a receita mais generosa não estoura a pilha")

	## ── kind 0: recarregar (`0x800684dc`) ──
	var rec := Itens.combinar([_slot(0x03, 0), _slot(0x15, 30)], 0, 1, {})
	t.eq(int(rec["qtd"]), 15, "Hand Gun recebe 15 (o `max` do descritor)")
	t.eq(int(((rec["mudancas"] as Dictionary)[1] as Dictionary)["qtd"]), 15,
		"e sobram 15 balas no slot da munição")
	var cheia := Itens.combinar([_slot(0x03, 15), _slot(0x15, 30)], 0, 1, {})
	t.check(not bool(cheia["ok"]), "arma cheia não recarrega")
	t.eq(int(cheia["mensagem"]), 2, "e pede a mensagem 2 (é arma, cat 1)")

	## ── kind 1: simples — a quantidade vem do REGISTRO, não de arredondamento ──
	var ervas := Itens.combinar([_slot(0x21, 1), _slot(0x21, 1)], 0, 1, {})
	t.eq(int(((ervas["mudancas"] as Dictionary)[1] as Dictionary)["id"]), 0x24,
		"erva+erva: sobrevive o 2º selecionado (`swap = 1` quando `rec.a == rec.b`)")
	t.eq(int(((ervas["mudancas"] as Dictionary)[0] as Dictionary)["id"]), 0,
		"e o 1º esvazia")
	var eagle := Itens.combinar([_slot(0x59, 1), _slot(0x5A, 1)], 0, 1, {})
	t.eq(int(eagle["qtd"]), 15,
		"EAGLE Parts A+B -> EAGLE 6.0 já com 15 balas (`n` do registro `0x800a09b4`)")

	## ── kind 3: upgrade de arma (`0x800686ac`) — exige a arma VAZIA ──
	var up_cheia := Itens.combinar([_slot(0x11, 5), _slot(0x15, 20)], 0, 1, {})
	t.check(not bool(up_cheia["ok"]), "SIGPRO E com munição dentro NÃO faz downgrade")
	t.eq(int(up_cheia["mensagem"]), 8, "pede a mensagem 8 ('precisa estar vazia')")
	var up := Itens.combinar([_slot(0x11, 0), _slot(0x15, 20)], 0, 1, {})
	t.check(bool(up["ok"]), "SIGPRO E vazia + balas comuns faz o downgrade")
	t.eq(int(((up["mudancas"] as Dictionary)[0] as Dictionary)["id"]), 0x02,
		"vira Merc's Handgun (`rec.c`)")
	## Com munição INFINITA a arma não precisa estar vazia e devolve a munição antiga.
	var up_inf := Itens.combinar([_slot(0x11, 7, 3), _slot(0x15, 20)], 0, 1, {})
	t.eq(int(((up_inf["mudancas"] as Dictionary)[1] as Dictionary)["id"]), 0x1E,
		"arma infinita devolve a munição antiga pela tabela `0x80010f24` (0x11 -> 0x1e)")
	t.eq(int(((up_inf["mudancas"] as Dictionary)[1] as Dictionary)["qtd"]), 7,
		"com a quantidade que estava DENTRO da arma")

	## ── kind 4: troca de granada (`0x80068854`) — `n` é a munição que VOLTA ──
	var tg := Itens.combinar([_slot(0x06, 4), _slot(0x19, 6)], 0, 1, {})
	t.eq(int(tg["kind"]), Itens.REC_TROCA_GRANADA, "lançador + outra granada é kind 4")
	t.eq(int(((tg["mudancas"] as Dictionary)[0] as Dictionary)["id"]), 0x07,
		"o lançador vira a variante flamejante (`rec.c`)")
	t.eq(int(((tg["mudancas"] as Dictionary)[1] as Dictionary)["id"]), 0x18,
		"e as granadas normais que estavam dentro voltam (`rec.n`)")
	t.eq(int(((tg["mudancas"] as Dictionary)[1] as Dictionary)["qtd"]), 4,
		"exatamente as 4 que estavam carregadas")

	## ── kind 5: pólvora + Grenade Rounds (`0x800688d8`) — consome 6 unidades ──
	var pg := Itens.combinar([_slot(0x18, 10), _slot(0x63, 1)], 0, 1, {"niveis": [0, 0, 0, 0]})
	t.eq(int(pg["kind"]), Itens.REC_POLVORA_GRANADA, "0x18 + pólvora C é kind 5")
	t.eq(int(((pg["mudancas"] as Dictionary)[0] as Dictionary)["qtd"]), 4,
		"consome 6 das 10 granadas normais")
	t.eq(int((pg["niveis"] as Array)[3]), 1, "e sobe o contador do grupo 3 (`inv+0x132`)")
	var pg2 := Itens.combinar([_slot(0x18, 3), _slot(0x63, 1)], 0, 1, {"niveis": [0, 0, 0, 0]})
	t.eq(int(((pg2["mudancas"] as Dictionary)[0] as Dictionary)["id"]), 0,
		"com menos de 7 granadas o slot esvazia")
	t.check(int(pg2["qtd"]) < int(pg["qtd"]),
		"e a quantidade sai PROPORCIONAL (`qty * rounds / 6`)")

	## ── kind 6: munição infinita (`0x80068978`) ──
	var mi := Itens.combinar([_slot(0x03, 15), _slot(0x6E, 1)], 0, 1, {})
	t.eq(int(((mi["mudancas"] as Dictionary)[0] as Dictionary)["flags"]) & 3, 3,
		"arma + Inf. Bullets liga `flags |= 3`")
	t.eq(int(((mi["mudancas"] as Dictionary)[1] as Dictionary)["id"]), 0,
		"e o slot das Inf. Bullets esvazia")
	var mt := Itens.combinar([_slot(0x0C, 0), _slot(0x6E, 1)], 0, 1, {})
	t.eq(int(((mt["mudancas"] as Dictionary)[0] as Dictionary)["id"]), 0x14,
		"o Mine Thrower `0x0c` vira `0x14` M. Thrower E (`0x80069040`)")
	t.eq(int(((mt["mudancas"] as Dictionary)[0] as Dictionary)["flags"]), 7,
		"com flags = 7, como o EXE escreve")

	## Cobertura: TODOS os 7 kinds existem na tabela e nenhum cai no ramo "desconhecido".
	var vistos := {}
	for i in Itens.n_receitas():
		vistos[int(Itens.receita_por_indice(i).get("kind", -1))] = true
	t.eq(vistos.size(), 7, "os 7 kinds aparecem nas 125 receitas")
	return true


func _icones(t: Object) -> bool:
	## ══ DE-PARA DO ÍCONE DA GRADE (o bug relatado: Fita de tinta com ícone de munição) ══
	## O ícone pequeno vem de `ETC/ITEMA.SLD` por `item_id`; o `.webp` HD é casado por HASH
	## EXATO (`tools/hd_match.py hash`). O mapa é `data/hd_status_map.json.itema`.
	t.group("icone HD")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/hd_status_map.json"))
	if not t.check(raw is Dictionary, "hd_status_map.json carrega"):
		return true
	var mapa: Dictionary = (raw as Dictionary).get("itema", {})
	t.check(mapa.size() >= 120, "o mapa de ícones cobre 120+ item_id", "%d" % mapa.size())
	## O CASO DO DONO: `0x81` (Fita de tinta) e `0x17` (Cartuchos de escopeta) NÃO podem
	## compartilhar arquivo — era o `0x81` levando o `.webp` do `0x17`.
	var fita: Dictionary = mapa.get("129", {})
	var cart: Dictionary = mapa.get("023", {})
	t.eq(String(fita.get("webp", "")), "item/733CC610",
		"0x81 Fita de tinta -> o .webp do ROLO DE FITA (hash exato)")
	t.eq(String(cart.get("webp", "")), "item/0980451F",
		"0x17 Cartuchos de escopeta -> a CAIXA DE MUNIÇÃO (era este que estava no 0x81)")
	t.check(String(fita.get("webp", "")) != String(cart.get("webp", "")),
		"a Fita de tinta e os Cartuchos de escopeta NÃO usam o mesmo ícone")
	t.eq(String(fita.get("metodo", "")), "hash", "e o par do 0x81 é EXATO, não por semelhança")

	## Nenhum par por hash pode ser 1:1 forçado: item_id diferentes COMPARTILHAM bitmap. Se
	## alguém reintroduzir a injetividade, estes três param de casar.
	t.eq(String((mapa.get("006", {}) as Dictionary).get("webp", "")),
		String((mapa.get("009", {}) as Dictionary).get("webp", "")),
		"os lança-granadas 0x06 e 0x09 compartilham o MESMO ícone (N:1 é legítimo)")
	t.eq(String((mapa.get("014", {}) as Dictionary).get("webp", "")),
		String((mapa.get("015", {}) as Dictionary).get("webp", "")),
		"o Fuzil 0x0e e 0x0f compartilham o ícone")
	t.eq(String((mapa.get("012", {}) as Dictionary).get("webp", "")),
		String((mapa.get("020", {}) as Dictionary).get("webp", "")),
		"Lança-minas 0x0c e melhorado 0x14 compartilham o ícone")

	## Os itens que o dono vê no jogo: cada um com par EXATO e nenhum repetido entre si.
	var usados := {}
	for chave: String in ["003", "004", "005", "021", "022", "023", "032", "033", "129", "130"]:
		var e: Dictionary = mapa.get(chave, {})
		t.eq(String(e.get("metodo", "")), "hash",
			"item %s tem par HD por hash exato" % chave)
		var w := String(e.get("webp", ""))
		t.check(not usados.has(w), "item %s não repete o .webp de outro item da lista" % chave, w)
		usados[w] = chave

	## O arquivo tem de EXISTIR no disco para o par valer (o mapa sem o asset não conserta nada).
	for chave: String in ["129", "023", "004", "003"]:
		t.check(FileAccess.file_exists("res://assets/MENU/status/hd/itema/%s.webp" % chave),
			"o .webp do item %s está no disco" % chave)
	## E os órfãos do casamento antigo tiveram de sair: o loader acha o HD ANTES do PNG, então um
	## arquivo deixado para trás continuaria mostrando o ícone errado.
	for chave: String in ["053", "062", "073", "074", "113", "118"]:
		t.check(not mapa.has(chave), "item %s não tem par no mapa novo" % chave)
		t.check(not FileAccess.file_exists("res://assets/MENU/status/hd/itema/%s.webp" % chave),
			"e o .webp órfão do item %s foi removido do disco" % chave)
	return true


func _fita_no_facil(t: Object) -> bool:
	## ══ FITA DE TINTA SÓ FORA DO MODO FÁCIL (`0x800575ac`/`0x80057788`) ══
	t.group("item no chão")
	var dif := Itens.item_no_chao(Itens.ITEM_FITA_TINTA, 3, false)
	t.check(bool(dif["colocar"]), "no MODO DIFÍCIL a fita de tinta é colocada")
	t.eq(int(dif["qtd"]), 3, "com as 3 unidades do dado (todas as 17 colocações usam amount 3)")
	var fac := Itens.item_no_chao(Itens.ITEM_FITA_TINTA, 3, true)
	t.check(not bool(fac["colocar"]),
		"no MODO FÁCIL a fita de tinta NÃO é colocada (o handler liga a flag de 'já pego')")
	## O MESMO bloco dobra a munição colocada no chão (faixa `0x15..0x1f`, `sltiu 0xb`).
	t.eq(int(Itens.item_no_chao(0x15, 30, true)["qtd"]), 60,
		"munição no chão vem em DOBRO no fácil (`0x800575f4 sll v0, v0, 1`)")
	t.eq(int(Itens.item_no_chao(0x15, 30, false)["qtd"]), 30, "e normal no difícil")
	t.eq(int(Itens.item_no_chao(0x1F, 8, true)["qtd"]), 16, "0x1f é o ÚLTIMO id dobrado")
	t.eq(int(Itens.item_no_chao(0x20, 1, true)["qtd"]), 1,
		"0x20 (spray) já está FORA da faixa — não dobra")
	t.eq(int(Itens.item_no_chao(0x14, 1, true)["qtd"]), 1,
		"0x14 está ANTES da faixa — não dobra")
	t.check(bool(Itens.item_no_chao(0x21, 1, true)["colocar"]),
		"erva verde continua sendo colocada no fácil")
	return true
