#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
re3_text.py - Decodifica as tabelas de TEXTO do RE3 (nomes/exames de item + mensagens).

DUAS FONTES cruzadas:
  1) mod PT-BR "mod_BH3_Portuguese" (GOG) -> XML editavel:
       xml/encoding.xml   = charset (byte -> caractere da fonte propria do RE3)
       xml/items_simple.xml = NOMES de item em PT, array indexado por item_id (idx 0 = vazio)
       xml/system.xml       = EXAMES de item em PT, array; item_id = idx - 16
       xml/prompt.xml       = mensagens de porta/acao (EN+PT embutidos)
       xml/rdt/R###.xml     = mensagens por sala (documentos/exame de objeto) em PT
  2) executavel PS1 US (NTSC-U) SLUS_009.23 -> texto EN na MESMA fonte codificada:
       tabela de NOMES  em 0x8c6e5 (entradas separadas por 0xF7, comeca em "Knife" = 0x01)
       tabela de EXAMES em 0x8a124 (entradas separadas por 0xFE, comeca em item 0x01;
                                    item_id = indice + 1)
       codigos de controle no fluxo EN: 0xFC = nova linha, 0xFD = nova pagina/clear,
                                        0xFE = fim de string, 0xF7 = fim de nome,
                                        0xEA XX = glifo especial (S.T.A.R.S. full-width)

PROVA do charset (byte -> string), ex.:
   0x27 0x2A 0x25 0x22 0x21 = "KNIFE"
   0x23 0x4E 0x41 0x41 0x4A = "Green"   (achado em 0x8c86c no SLUS)
   0x15 x30 (item_id) = "H. Gun Bullets" (casa com sce_item_names.json)

Uso:
   python tools/re3_text.py --dump                # imprime tabela alinhada EN/PT
   python tools/re3_text.py --build-items         # gera godot/data/re3_items.json
   python tools/re3_text.py --build-messages      # gera godot/data/re3_messages.json
"""
import re, os, sys, json, argparse
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.stdout.reconfigure(encoding="utf-8")

GOG = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3"
MOD = os.path.join(GOG, "mod_BH3_Portuguese", "xml")
ENC_XML = os.path.join(GOG, "mod_BH3_Portuguese", "encoding.xml")
SLUS = os.path.join(os.path.dirname(__file__), "..", "extracted", "ntsc-u", "SLUS_009.23")
DATA_DIR = paths.data()

NAMES_OFF = 0x8c6e5   # SLUS: inicio da tabela de nomes EN ("Knife" = item 0x01)
EXAM_OFF  = 0x8a124   # SLUS: inicio da tabela de exames EN (item 0x01)

# Tabela de DESCRITORES de item do EXE (usada pela lógica de inventário):
# RAM 0x800a0514, 4 bytes/entrada indexados por item_id. PROVADO por desmontagem
# (0x8006d0a8/0x80069cb8 leem daqui) e por casamento com os exames/SCD:
#   b0 = CLASSE (0x01 arma,0x02 munição,0x03 recuperação,0x04 key-item,0x05 chave,
#                0x06 ferramenta,0x07 documento,0x08 mapa,0x00 não-usado) — as faixas
#        batem 1:1 com os itens conhecidos (0x2a=F.Aid Box início da faixa key etc.)
#   b1 = STACK MÁX / CAPACIDADE (0x02 pistola=15, 0x04 escopeta=7, 0x2a caixa=3,
#        munição=250) — casa com os exames e com o amount do SCD (0x04→7, 0x15→30).
#   b3 = atributo (tipo de munição carregada p/ armas). Base EXE 0x80010000, texto @0x800.
DESC_OFF = 0x800a0514
DESC_CAT = {0x01: "weapon", 0x02: "ammo", 0x03: "recovery", 0x04: "key_item",
            0x05: "key", 0x06: "tool", 0x07: "file", 0x08: "map", 0x00: "unused"}

def parse_slus_desc():
    """Le a tabela de descritores 0x800a0514 -> {item_id: {cat,max,attr}}."""
    data = open(SLUS, "rb").read()
    o = (DESC_OFF - 0x80010000) + 0x800
    desc = {}
    for i in range(1, 0xC2):
        b = data[o + i * 4: o + i * 4 + 4]
        if len(b) < 4:
            break
        desc[i] = {"cat": b[0], "max": b[1], "attr": b[3]}
    return desc

# ---------------------------------------------------------------- charset
def load_charset():
    xml = open(ENC_XML, encoding="utf-8").read()
    b2c = {}
    for m in re.finditer(r'Encode="0x([0-9A-Fa-f]{2})"\s+Char="([^"]*)"', xml):
        code = int(m.group(1), 16)
        ch = (m.group(2).replace("&#34;", '"').replace("&#39;", "'")
                        .replace("&#129;", "").replace("&#130;", ""))
        if code not in b2c:      # primeira definicao vence
            b2c[code] = ch
    return b2c

def enc_word(b2c, s):
    c2b = {ch: c for c, ch in sorted(b2c.items(), reverse=True) if len(ch) == 1}
    return bytes(c2b[ch] for ch in s)

# ---------------------------------------------------------------- normalizacao
def _clean(s, collapse=True):
    """Converte codigos de controle em texto legivel."""
    s = s.replace("{FC}", "\n").replace("{FD}", "\n").replace("{FE}", "")
    s = s.replace("{F7}", "").replace("{FF}", "")
    # glifos especiais (0xEA <byte>): a sequencia de 5 = S.T.A.R.S. full-width; {EA}6 = '&'
    s = s.replace("{EA}H{EA}I{EA}J{EA}K{EA}H", "S.T.A.R.S.")
    s = s.replace("{EA}6", "&")
    # full-width STARS do lado PT
    for fw in ("ＳＴＡＲＳ", "Ｓ Ｔ Ａ ＲＳ", "Ｓ Ｔ Ａ Ｒ Ｓ", "Ｓ Ｔ Ａ ＲＳ"):
        s = s.replace(fw, "S.T.A.R.S.")
    if collapse:
        s = re.sub(r"\s+", " ", s).strip()
    return s

KNOWN_CTRL = {"FC", "FD", "FE", "F7", "FF", "EA"}

def decode(b2c, bs):
    out = []
    for b in bs:
        if 0x00 <= b <= 0xA0 and b in b2c and b2c[b]:
            out.append(b2c[b])
        else:
            out.append("{%02X}" % b)
    return "".join(out)

def _garbage(dec):
    """conta tokens {XX} que NAO sao codigos de controle conhecidos (indicio de fim de tabela)"""
    return sum(1 for t in re.findall(r"\{([0-9A-F]{2})\}", dec) if t not in KNOWN_CTRL)

# ---------------------------------------------------------------- EN (SLUS)
def parse_slus():
    data = open(SLUS, "rb").read()
    b2c = load_charset()
    # nomes: split por 0xF7
    names = {}
    raw = data[NAMES_OFF:NAMES_OFF + 0x900]
    parts = raw.split(b"\xf7")
    for i, p in enumerate(parts):
        if i == 0:
            item_id = 1
        else:
            item_id = i + 1
        dec = decode(b2c, p)
        # detecta fim da tabela (lixo com bytes desconhecidos)
        if _garbage(dec) > 2 and item_id > 4:
            break
        names[item_id] = _clean(dec)
    # exames: split por 0xFE
    exam = {}
    raw = data[EXAM_OFF:EXAM_OFF + 0x2d00]
    parts = raw.split(b"\xfe")
    for i, p in enumerate(parts):
        item_id = i + 1
        dec = decode(b2c, p)
        if _garbage(dec) > 3 and item_id > 4:
            break
        exam[item_id] = _clean(dec)
    return names, exam

# ---------------------------------------------------------------- PT (mod XML)
def _texts(path):
    xml = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"<Text>(.*?)</Text>", xml, re.S):
        t = m.group(1)
        t = (t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
              .replace("&#34;", '"').replace("&#39;", "'").replace("&quot;", '"'))
        out.append(t)
    return out

def _clean_pt(t):
    # remove tags de controle do formato XML do mod: {clear 0} {color n} {branch} {scroll} etc.
    t = re.sub(r"\{[^}]*\}", " ", t)
    t = t.replace("\\n", "\n")
    for fw in ("ＳＴＡＲＳ", "Ｓ Ｔ Ａ ＲＳ", "Ｓ Ｔ Ａ Ｒ Ｓ"):
        t = t.replace(fw, "S.T.A.R.S.")
    t = re.sub(r"\s+", " ", t).strip()
    return t

def parse_pt():
    items = _texts(os.path.join(MOD, "items_simple.xml"))   # idx = item_id (idx0 vazio)
    system = _texts(os.path.join(MOD, "system.xml"))         # item_id = idx - 16
    names_pt, exam_pt = {}, {}
    for idx, t in enumerate(items):
        if idx == 0:
            continue
        names_pt[idx] = _clean_pt(t)
    for idx, t in enumerate(system):
        item_id = idx - 16
        if item_id >= 1:
            exam_pt[item_id] = _clean_pt(t)
    return names_pt, exam_pt

# ---------------------------------------------------------------- combinar
def build_table():
    names_en, exam_en = parse_slus()
    names_pt, exam_pt = parse_pt()
    desc = parse_slus_desc()
    ids = sorted(set(names_en) | set(names_pt) | set(exam_en) | set(exam_pt))
    table = {}
    for i in ids:
        ne, np = names_en.get(i, ""), names_pt.get(i, "")
        ee, ep = exam_en.get(i, ""), exam_pt.get(i, "")
        unused = (ne in ("BOTU", "", "no item")) and (np in ("BOTU", "", "Nada"))
        di = desc.get(i, {})
        table["0x%02x" % i] = {
            "name_en": ne, "name_pt": np,
            "exam_en": ee, "exam_pt": ep,
            # descritor REAL do EXE (0x800a0514): classe + capacidade/stack
            "inv_cat": DESC_CAT.get(di.get("cat"), "unused") if di else "unused",
            "inv_max": di.get("max", 0),
            "unused": unused,
        }
    return table

# ---------------------------------------------------------------- CLI
# ---------------------------------------------------------------- build re3_items.json
# chave semantica (usada por inventory.gd / default_loadout) -> item_id real
KEY2ID = {
    "knife": 0x01, "handgun_sigpro": 0x02, "handgun_beretta": 0x03, "shotgun": 0x04,
    "magnum": 0x05, "grenade_launcher": 0x06, "mine_thrower": 0x0c, "gatling": 0x0b,
    "handgun_bullets": 0x15, "shotgun_shells": 0x17, "magnum_rounds": 0x16,
    "grenade_rounds": 0x18, "flame_rounds": 0x19, "rifle_rounds": 0x1d,
    "reload_tool": 0x82, "first_aid_spray": 0x20, "green_herb": 0x21, "red_herb": 0x23,
    "blue_herb": 0x22, "mixed_herb_gg": 0x24, "mixed_herb_gb": 0x25, "mixed_herb_gr": 0x26,
    "mixed_herb_grb": 0x29, "gunpowder_a": 0x61, "gunpowder_b": 0x62, "gunpowder_c": 0x63,
    "ink_ribbon": 0x81, "lockpick": 0x72, "wrench": 0x3c, "oil": 0x39, "stars_card": 0x2f,
    "recorder": 0x40, "green_gem": 0x44, "blue_gem": 0x45, "amber": 0x46,
    # correspondencias plausiveis (confianca media/baixa)
    "handgun_custom": 0x11, "shotgun_custom": 0x13, "id_card": 0x60, "manual": 0x83,
    "key_ornate": 0x77,
}
# Loadouts do modo de selecao de personagem (SELECT.BIN @0x36e8, strings ASCII literais
# no overlay retail — PROVADO byte-a-byte). Marcador no jogo: '007'=arma equipada, '005'=demais.
MERCENARIES_LOADOUTS = {
    "_fonte": "SELECT.BIN @0x36e8 (ASCII literal); '[007..]'=arma equipada, '[005..]'=demais itens",
    "NICHOLAI": {"equipped": "SIGPRO SP2009",
                 "items": ["KNIFE", "Blue Herb", "First Aid Spray", "First Aid Spray", "First Aid Spray"]},
    "CARLOS": {"equipped": "M4A1",
               "items": ["EAGLE 6.0", "Hand Gun Bullets", "Mixed Herb", "Mixed Herb", "Mixed Herb"]},
    "MIKHAIL": {"equipped": "BENELLI M3S",
                "items": ["M629C", "ROCKET LAUNCHER", "Shotgun Shells", "Magnum Bullets", "Mixed Herb"]},
    "Chris Redfield": {"equipped": "Beretta-M92FS.",
                       "items": ["Remington M1100.", "Rocket Launcher", "Ink Ribbon", "F.Aid Spray"]},
}

# ---------------------------------------------------------------- LOADOUT DE NOVO JOGO (EXE)
# A rotina de NOVO JOGO 0x8006d0d8 (SLUS_009.23) monta o inventario inicial: zera o array
# 0x800d2134 (gs+0x79fc; MAIN 10 slots @+0, BOX 64 slots @+0x28) e COPIA um TEMPLATE ESTATICO.
# PROVADO byte-a-byte (desmontagem):
#   - loop de escrita 0x8006d304+ : slot.b0 = tmpl[0] = item_id ; slot.b1 = tmpl[1] = qtd ;
#     slot.hword+2 = tmpl[2..3] = flags16(LE). Entrada = 4 bytes {id, qtd, flags16}.
#     Terminador da lista = FFFFFFFF (primeiro byte 0xFF, `lb;beq -1`).
#   - equip inicial (0x800d225d = gs+0x7b25) = id do PRIMEIRO item (0x8006d5a8 `sb v0,0x7b25(s6)`).
#   - Game Instructions (0x83/0x84) sao PULADAS quando a flag 0x800d1f3e != 0 (so na 1a jogada).
#   - Ramo s5<2 (jogo principal da Jill) ANEXA as armas-bonus de pos-zeramento gated por flags
#     em gs+0x77f8: bit6->0x0a R.Launcher, bit7->0x0b Gatling, bit8->0x0f AsltRifle (qtd 0xff = infinito).
# Modo s5 vem de jump-table @0x80010f9c (5 entradas). Enderecos dos templates lidos do proprio
# dispatch (0x8006d258..0x8006d2f8). s5=2 (mercenarios) indexado por gs+0x24d6 (8/9/0xA).
NEWGAME_INIT_FN   = 0x8006d0d8
NEWGAME_JUMPTBL   = 0x80010f9c
NEWGAME_ARRAY     = 0x800d2134  # gs+0x79fc: MAIN@+0 (10 slots), BOX@+0x28 (64 slots)
NEWGAME_EQUIP_OFF = 0x800d225d  # equip inicial = 1o item do template
# chave -> (ram_addr_do_template, rotulo/prova)
NEWGAME_TEMPLATES = {
    "s5_0_jill_main":     (0x800a018c, "s5=0 MAIN - jogo principal da Jill (dificuldade HARD: so pistola)"),
    "s5_1_jill_main":     (0x800a01b4, "s5=1 MAIN - jogo principal da Jill (dificuldade EASY: fuzil+kit)"),
    "s5_1_jill_box":      (0x800a0298, "s5=1 BOX  - item box inicial (modo EASY)"),
    "s5_2_carlos_merc":   (0x800a01e4, "s5=2 char=8 - CARLOS (The Mercenaries)"),
    "s5_2_mikhail_merc":  (0x800a021c, "s5=2 char=9 - MIKHAIL (The Mercenaries)"),
    "s5_2_nicholai_merc": (0x800a0200, "s5=2 char=0xA - NICHOLAI (The Mercenaries)"),
    "s5_3_main":          (0x800a0238, "s5=3 MAIN - preset (EAGLE+escopeta+Blue Gem)"),
    "s5_4_main":          (0x800a0258, "s5=4 MAIN - preset Jill armada (lanca-granadas+todas municoes)"),
}

def parse_newgame_loadouts(table):
    """Le os templates estaticos de loadout do SLUS (0x800a018c+) e decodifica byte-a-byte.
    Cada entrada = {id, qtd, flags16(LE)}; lista termina em FFFFFFFF. Retorna dict serializavel."""
    data = open(SLUS, "rb").read()
    def ram2off(r):
        return (r - 0x80010000) + 0x800
    out = {}
    for key, (ram, label) in NEWGAME_TEMPLATES.items():
        o = ram2off(ram); ents = []; raw = b""
        for _ in range(16):
            b = data[o:o + 4]
            if b == b"\xff\xff\xff\xff":
                break
            raw += b
            hx = "0x%02x" % b[0]
            ents.append({
                "id": hx,
                "name_en": table.get(hx, {}).get("name_en", ""),
                "qty": b[1],
                "flags": "0x%04x" % (b[2] | (b[3] << 8)),
                "raw": b.hex(),
            })
            o += 4
        out[key] = {
            "ram": "0x%08x" % ram,
            "label": label,
            "bytes": raw.hex() + "ffffffff",   # inclui o terminador FFFFFFFF
            "entries": ents,
        }
    return out

# chaves semanticas sem item real correspondente no RE3 (nao inventar exame)
KEY_SEM_ID = {"smg", "key_iron", "key_bronze", "key_wood"}
KEY_CONF = {"handgun_custom": "media", "shotgun_custom": "media", "id_card": "media",
            "manual": "media", "key_ornate": "baixa"}

# Resíduo de curadoria (esqueleto de UI do protótipo): mapeia chave-semântica -> ícone/
# tipo/ammo + loadout demo. NÃO deriva do disco/EXE; vive versionado em godot/data. É a
# ÚNICA entrada de re3_items.json que não sai da fonte — o resto (id/nome/exame/loadouts)
# é extraído do EXE+mod PT. Antes, build_items() lia o PRÓPRIO re3_items.json (falhava em
# pasta limpa); agora lê este resíduo mínimo -> --build-items funciona do zero. (P0-11)
CURATION = os.path.join(os.path.dirname(__file__), "..", "godot", "data", "re3_items_curation.json")


def load_curation():
    """Lê o esqueleto de curadoria (chaves semânticas + UI + default_loadout). Fallback:
    um re3_items.json antigo, se existir, para compatibilidade."""
    if os.path.isfile(CURATION):
        c = json.load(open(CURATION, encoding="utf-8"))
        return c.get("items", {}), c.get("default_loadout", [])
    legacy = os.path.join(DATA_DIR, "re3_items.json")
    if os.path.isfile(legacy):
        old = json.load(open(legacy, encoding="utf-8"))
        return old.get("items", {}), old.get("default_loadout", [])
    return {}, []


def build_items():
    table = build_table()
    newgame = parse_newgame_loadouts(table)
    cur_items, cur_loadout = load_curation()
    items = {}
    for key, e in cur_items.items():
        ne = dict(e)
        iid = KEY2ID.get(key)
        # limpa campos antigos de descricao aproximada
        for k in ("desc_en", "desc_pt", "item_id"):
            ne.pop(k, None)
        if iid is not None:
            hx = "0x%02x" % iid
            t = table[hx]
            ne["id"] = hx
            ne["name_en"] = t["name_en"] or ne.get("name_en", "")
            ne["name_pt"] = t["name_pt"] or ne.get("name_pt", "")
            ne["exam_en"] = t["exam_en"]
            ne["exam_pt"] = t["exam_pt"]
            ne["inv_cat"] = t.get("inv_cat")
            ne["inv_max"] = t.get("inv_max")
            # desc_* = alias do exame real (inventory.gd le desc_*)
            ne["desc_en"] = t["exam_en"]
            ne["desc_pt"] = t["exam_pt"]
            if key in KEY_CONF:
                ne["id_conf"] = KEY_CONF[key]
        else:
            ne["id"] = ""
            ne["exam_en"] = ""
            ne["exam_pt"] = ""
            ne["desc_en"] = ""
            ne["desc_pt"] = ""
            ne["id_conf"] = "sem_id"
            ne["_todo"] = "sem correspondencia confirmada na tabela de itens do RE3"
        items[key] = ne
    out = {
        "_meta": {
            "descricao": "Itens do RE3. name_*/exam_* EXTRAIDOS das tabelas reais do jogo "
                         "(nao inventados). 'items' = chaves semanticas p/ inventory.gd + loadout; "
                         "'by_id' = tabela COMPLETA indexada por item_id (0x00 do opcode SCD 0x68). "
                         "desc_* e alias de exam_* (compat inventory.gd).",
            "fontes": {
                "PT": "GOG mod_BH3_Portuguese/xml (items_simple.xml=nomes idx=id; system.xml=exames, id=idx-16; encoding.xml=charset)",
                "EN": "PS1 NTSC-U SLUS_009.23: tabela de nomes @0x8c6e5 (sep 0xF7, Knife=0x01), tabela de exames @0x8a124 (sep 0xFE, id=idx+1)",
                "descritor_inv": "SLUS_009.23 @0x800a0514 (4B/id): inv_cat=classe(b0), inv_max=stack/capacidade(b1). Lido pela logica de inventario do jogo (0x8006d0a8/0x80069cb8).",
                "charset": "encoding.xml (fonte propria RE3): 0x00=' ',digitos~0x0C,'A'=0x1D,'a'=0x3D; acentos 0x57+. Provado: 0x15x30='H. Gun Bullets' casa com sce_item_names.json; 0x21='Green Herb'.",
            },
            "cobertura": "193 IDs (0x01-0xC1). 168 com nome real EN+PT. TODOS os itens jogaveis "
                         "(0x01-0x84) com exame real EN+PT. Documentos/mapas/keys-alt 0x85-0xC1 tem "
                         "so NOME (+ inv_cat/inv_max) e NAO tem exame de inventario em NENHUMA fonte: "
                         "PROVADO byte-a-byte que a tabela de exames @0x8a124 TERMINA em 0x84 (idx 0x85 "
                         "e 0x86 = strings vazias 0xFE 0xFE; 0x87 = lixo/fim). O texto desses itens vive "
                         "nos RDT (leitor de documento), nao numa tabela de exame de item.",
            "confirmacao_item_id": "item_id 100% confirmado por 3 fontes independentes concordantes: "
                         "(1) nomes EN @0x8c6e5 x exames EN @0x8a124 x nomes/exames PT (ancoras: 0x01 faca, "
                         "0x15 balas pistola, 0x20 spray, 0x21 erva verde, 0x2a F.Aid Box); "
                         "(2) descritor de inventario @0x800a0514 (classe+capacidade batem: 0x04 escopeta "
                         "stack 7, 0x2a caixa 3, 0x20 spray 1); "
                         "(3) SCD opcode 0x68 (sce_item_aot_set, campo +22) — 8 ids observados nas salas "
                         "(0x04 amount 7, 0x15 amount 30, 0x21,0x41,0x42,0x99,0x9b,0xa0) TODOS batem com by_id. "
                         "(obs.: opcode SCD 0x7d = sce_em_set e de INIMIGO, nao de item — item usa 0x68).",
            "ferramenta": "tools/re3_text.py --build-items",
            "notas": [
                "0x0A: exame='M66 Rocket Launcher' e nome EN='R. Launcher' (rocket); "
                "o items_simple.xml PT rotula 0x0A como 'Lança granadas' (provavel erro do mod). "
                "Autoridade = exame + sce_item_names + nome EN => Rocket Launcher.",
                "0x02 name='Merc's Handgun'/'Pistola de mercenário' mas exame='SIGPRO SP2009'; "
                "0x03 name='Hand Gun'/'Pistola' mas exame='M92F Custom made for S.T.A.R.S.'. "
                "Quirk dos dados originais do RE3 (fiel).",
                "'BOTU' = slot nao usado/placeholder presente no proprio binario retail (marcado unused).",
            ],
            "loadout": "FECHADO: a rotina de NOVO JOGO do EXE (0x8006d0d8) monta o inventario inicial "
                       "COPIANDO um TEMPLATE ESTATICO (0x800a018c+) para o array 0x800d2134 — entrada de "
                       "4B {id,qtd,flags16}, terminador FFFFFFFF, PROVADO byte-a-byte (loop 0x8006d304+; "
                       "equip=1o item @0x800d225d). Ver 'newgame_loadout_templates' (todos os templates com "
                       "enderecos+bytes) e 'default_loadout_jill' (template s5=0). O add-item por-item da "
                       "familia 0x80069c3c/0x8006a020 e o PRIMITIVO de conceder 1 item (janela de obter), "
                       "usado no gameplay; o novo-jogo usa a copia de template acima. HONESTIDADE: os "
                       "templates de MERCENARIOS (s5=2) sao RETAIL-verificados (byte-identicos ao SELECT.BIN "
                       "@0x36e8). Os templates de modo-Jill (s5=0/1/3/4) contem itens de dev/debug "
                       "(Reloading Tool x250, Game Inst. A/B, Blue Gem, arsenal completo): o classico "
                       "'Faca+Pistola' NAO existe como tabela estatica discreta no SLUS (varredura do EXE "
                       "inteiro: Faca 0x01 so aparece nos templates de NICHOLAI e do item-box). "
                       "default_loadout = loadout DEMO do prototipo (inventory.gd), mantido p/ compat. "
                       "loadouts_mercenaries = REAL (SELECT.BIN @0x36e8).",
            "exame_0x85_plus": "PROVADO byte-a-byte: tabela de exames EN @0x8a124 (sep 0xFE) termina no "
                       "item 0x84 (entrada real de 111B); idx 0x85 e 0x86 = vazios (1 byte '00'); idx 0x87 "
                       "= fim/lixo (2161B sem separador). Itens 0x85-0xC1 NAO tem exame de inventario = "
                       "100% dos exames que EXISTEM estao cobertos (0x01-0x84).",
        },
        "items": items,
        "by_id": table,
        "loadouts_mercenaries": MERCENARIES_LOADOUTS,
        "default_loadout_jill": {
            "_fonte": "SLUS_009.23: rotina de novo-jogo 0x8006d0d8 copia o template estatico s5=0 "
                      "@0x800a018c p/ 0x800d2134. PROVADO byte-a-byte. equip inicial = 1o item (0x800d225d).",
            "template": newgame["s5_0_jill_main"],
            "nota_honesta": "Este e o template que o dispatch s5=0 (jogo principal da Jill, dificuldade "
                            "HARD) copia. O conteudo (Hand Gun x15 + Reloading Tool x250 + Game Inst. A/B) "
                            "indica um preset de desenvolvimento; NAO foi inventado 'Faca+municao avulsa' "
                            "(nao existe como tabela estatica no SLUS). Game Inst. A/B (0x83/0x84) so entram "
                            "na 1a jogada (gate flag 0x800d1f3e). A Faca e a arma corpo-a-corpo permanente.",
        },
        "newgame_loadout_templates": {
            "_fonte": "SLUS_009.23 rotina de novo-jogo 0x8006d0d8; jump-table de modo @0x80010f9c; "
                      "templates estaticos @0x800a018c+ copiados p/ 0x800d2134 (MAIN@+0/10, BOX@+0x28/64). "
                      "Entrada=4B {id,qtd,flags16(LE)}; terminador FFFFFFFF. PROVADO byte-a-byte.",
            "_modos": "s5=0/1 = jogo principal da Jill (HARD/EASY; ramo s5<2 anexa armas-bonus de "
                      "pos-zeramento gated em gs+0x77f8). s5=2 = The Mercenaries (char por gs+0x24d6: "
                      "8=Carlos,9=Mikhail,0xA=Nicholai; RETAIL-verificado vs SELECT.BIN). s5=3/4 = presets.",
            "templates": newgame,
        },
        "default_loadout": cur_loadout,
    }
    path = os.path.join(DATA_DIR, "re3_items.json")
    json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("gravado", path, "| items:", len(items), "| by_id:", len(table))

# ---------------------------------------------------------------- build re3_messages.json
def build_messages():
    system = _texts(os.path.join(MOD, "system.xml"))
    prompt = _texts(os.path.join(MOD, "prompt.xml"))
    # 17 primeiras entradas de system.xml = mensagens de sistema (pegar/combinar/etc.)
    sysmsg_pt = [_clean_pt(t) for t in system[:17]]
    prompt_pt = [_clean_pt(t) for t in prompt]
    # mensagens por sala (documentos / exame de objeto / portas) - PT
    rooms = {}
    rdt_dir = os.path.join(MOD, "rdt")
    for fn in sorted(os.listdir(rdt_dir)):
        if not fn.lower().endswith(".xml"):
            continue
        room = os.path.splitext(fn)[0]
        msgs = [_clean_pt(t) for t in _texts(os.path.join(rdt_dir, fn))]
        rooms[room] = msgs
    out = {
        "_meta": {
            "descricao": "Mensagens de texto do RE3 (sistema, portas/acoes, e por sala). "
                         "PT extraido do GOG mod_BH3_Portuguese/xml (real). Tags de controle "
                         "do formato ({clear},{color},{branch},{scroll},{s}) removidas p/ leitura.",
            "fontes": "system.xml (sistema), prompt.xml (portas/acoes), rdt/R###.xml (por sala). "
                      "A ordem de cada array = indice de mensagem referenciado pelo SCD da sala.",
            "en_todo": "EN das mensagens de sala/porta esta nos RDT do jogo base (nao extraido "
                       "aqui); NAO inventar. Ver SLUS/RDT numa proxima passada.",
            "ferramenta": "tools/re3_text.py --build-messages",
        },
        "system_pt": sysmsg_pt,
        "prompt_pt": prompt_pt,
        "rooms_pt": rooms,
    }
    path = os.path.join(DATA_DIR, "re3_messages.json")
    json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("gravado", path, "| salas:", len(rooms), "| prompt:", len(prompt_pt))

def cmd_dump():
    names_en, exam_en = parse_slus()
    names_pt, exam_pt = parse_pt()
    ids = sorted(set(names_en) | set(names_pt))
    for i in ids:
        print("0x%02x | %-18s | %-24s | EN: %s" % (
            i, names_en.get(i, "?"), names_pt.get(i, "?"),
            (exam_en.get(i, "") or "")[:50]))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", action="store_true")
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--build-items", action="store_true")
    ap.add_argument("--build-messages", action="store_true")
    args = ap.parse_args()
    if args.dump:
        cmd_dump()
    elif args.table:
        print(json.dumps(build_table(), ensure_ascii=False, indent=1))
    elif args.build_items:
        build_items()
    elif args.build_messages:
        build_messages()
    else:
        ap.print_help()

if __name__ == "__main__":
    main()
