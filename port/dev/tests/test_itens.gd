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
