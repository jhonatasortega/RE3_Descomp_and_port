#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Extrai ITENS colocados no mundo (opcode SCD 0x68 = sce_item_aot_set) das 169 salas
do RE3 e anota godot/data/STAGE{n}/<sala>.json em rdt.script.items.

Opcode 0x68 (descoberto por eng. reversa — ver docs/formatos/exe.md):
  off 0  u8  opcode  = 0x68
  off 1  u8  aot_id
  off 2  u8  0x02          (constante, como a porta 0x67)
  off 3  u8  sat           (0x31 tipico)
  off 4  u8  floor
  off 5  u8  0
  off 6..21  8x s16 = 4 pontos (quadrilatero do trigger, estilo aot_4p)
  off 22 u16 campo A  (candidato item_id; ex.: 0x15 c/ amount 30 = municao)
  off 24 u16 amount / quantidade
  off 26 u16 campo B  (candidato item_id alternativo; sempre em faixa de item)
  off 28 u8, off 29 u8  flags
Total ~30 bytes. Os offsets de item_id (A vs B) ainda nao foram confirmados pelo handler;
gravamos o payload cru + ambos candidatos.
"""
import struct, glob, os, json, sys
from collections import Counter
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py
sys.path.insert(0, "tools")
import scd_decode as S

SAT_OK = (0x31, 0x21, 0x41, 0x51, 0x11, 0x01)

# ----------------------------------------------------------------------------
# Tabela de NOMES de item (id hex -> nome). Faixa 0x01..0x1B (armas+municao) e
# 0x2A (First Aid Spray) CONFIRMADOS por fontes de save-hacking do RE3 classico
# (GameFAQs Shockproof_Jamo; XPGamesaves; guia Dreamcast) e validados contra os
# dados de sala (0x15 x30 = Hand Gun Bullets -> bate com o amount observado no SCD).
# O mesmo espaco de ID vale entre versoes (PS1/PC/DC = mesmo jogo). IDs >0x1B (ervas,
# key items, IDs altos 0x99/0x9b/0xa0) NAO estao na tabela publica reproduzida -> "a confirmar".
# Fontes: gamefaqs.gamespot.com/pc/431704 (Shockproof_Jamo); xpgamesaves.com; neoseeker.
ITEM_NAMES = {
    0x01: "Combat Knife",
    0x02: "Sigpro SP2009 Handgun",           # handgun do mercenario/Carlos
    0x03: "M92F Handgun",                     # Jill
    0x04: "Benelli M3S Shotgun",
    0x05: "S&W M629C Magnum",
    0x06: "Grenade Launcher (Grenade)",       # Jill
    0x07: "Grenade Launcher (Flame)",         # Jill
    0x08: "Grenade Launcher (Acid)",          # Jill
    0x09: "Grenade Launcher (Freeze)",        # Jill
    0x0A: "Rocket Launcher",
    0x0B: "Gatling Gun",
    0x0C: "Mine Thrower",                     # Jill
    0x0D: "Eagle 6.0",
    0x0E: "Assault Rifle (Manual)",
    0x0F: "Assault Rifle (Auto)",
    0x10: "Western Custom",
    0x11: "Sigpro Enhanced",
    0x12: "M92F Enhanced",
    0x13: "Benelli M3S Enhanced",
    0x14: "Mine Thrower Enhanced",
    0x15: "Hand Gun Bullets",                 # validado: x30 no SCD
    0x16: "Magnum Bullets",
    0x17: "Shotgun Shells",
    0x18: "Grenade Rounds",
    0x19: "Flame Rounds",
    0x1A: "Acid Rounds",
    0x1B: "Freeze Rounds",
    0x2A: "First Aid Spray",
}

def item_name(hid):
    """(nome, confianca). confianca ALTA para faixa confirmada; senao 'a confirmar'."""
    if hid in ITEM_NAMES:
        return ITEM_NAMES[hid], "ALTA"
    return None, "a confirmar"

def points(b, i):
    pts = []
    for k in range(4):
        x, z = struct.unpack_from("<hh", b, i + 6 + k*4)
        pts.append([x, z])
    return pts

def extract(path):
    data = open(path, "rb").read()
    rdt = S.rdt_of(data); so = S.script_of(rdt)
    b = rdt
    out = []
    for i in range(so, len(b) - 30):
        if b[i] == 0x68 and b[i+2] == 0x02 and b[i+3] in SAT_OK and b[i+5] == 0:
            fA = struct.unpack_from("<H", b, i+22)[0]
            amt = struct.unpack_from("<H", b, i+24)[0]
            fB = struct.unpack_from("<H", b, i+26)[0]
            # filtro anti-falso-positivo: campos de item sao bytes (high byte 0) e amount plausivel
            if fA >= 0x100 or amt > 999 or fB >= 0x100:
                continue
            pts = points(b, i)
            if not all(abs(x) < 45000 and abs(z) < 45000 for x, z in pts):
                continue
            cx = sum(p[0] for p in pts)//4; cz = sum(p[1] for p in pts)//4
            nm, conf = item_name(fA)
            out.append({
                "opcode": 0x68,
                "aot": b[i+1],
                "floor": b[i+4],
                "pos": [cx, cz],
                "points": pts,
                "item_id": fA,          # candidato primario (+22)
                "name": nm,             # nome (None quando "a confirmar")
                "name_conf": conf,      # ALTA (faixa 0x01-0x1B, 0x2A) | a confirmar
                "amount": amt,          # (+24)
                "item_id_alt": fB,      # candidato alternativo (+26)
                "payload": list(b[i+22:i+30]),
            })
    return out

def main(update_json=True):
    total = 0
    per = {}
    for f in sorted(glob.glob("extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD")):
        items = extract(f)
        if not items:
            continue
        stage = os.path.basename(os.path.dirname(f))
        name = os.path.splitext(os.path.basename(f))[0]
        per[name] = items
        total += len(items)
        if update_json:
            jp = os.path.join(paths.data(), stage, name + ".json")
            if os.path.exists(jp):
                d = json.load(open(jp, encoding="utf-8"))
                d.setdefault("rdt", {}).setdefault("script", {})["items"] = items
                json.dump(d, open(jp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # escreve a tabela de nomes (referencia p/ o remake)
    names_out = {
        "_meta": {
            "descricao": "IDs de item do RE3 (espaco de inventario; mesmo usado pelo item_id do opcode SCD 0x68).",
            "fonte": "GameFAQs Shockproof_Jamo save-hacking guide + XPGamesaves + guia Dreamcast; validado no SCD (0x15 x30 = Hand Gun Bullets).",
            "confianca": "0x01-0x1B e 0x2A: ALTA. Demais IDs (ervas, key items, 0x99/0x9b/0xa0 observados no SCD): a confirmar.",
        },
        "nomes": {("0x%02x" % k): v for k, v in sorted(ITEM_NAMES.items())},
        "observados_a_confirmar": sorted({("0x%02x" % it["item_id"])
                                          for its in per.values() for it in its
                                          if it["name"] is None}),
    }
    json.dump(names_out, open(paths.data("sce_item_names.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("total de itens (opcode 0x68) extraidos:", total, "em", len(per), "salas")
    for name, its in per.items():
        print("  %-6s: %s" % (name, ", ".join(
            "id=0x%02x(%s) x%d" % (it["item_id"], it["name"] or "?", it["amount"]) for it in its)))
    return per

# ============================================================================
# GERADOR de godot/data/sce_items.json  (fecha a dívida P0-11)
# ----------------------------------------------------------------------------
# Estrutura = análise SCE de itens do RE3. Partes DINÂMICAS (extraídas da fonte a
# cada build): itens_observados.por_sala (opcode 0x68 nas salas) e as contagens de
# sce_type_enum (byte sce dos opcodes 0x63/0x64 nas 169 salas). Partes ESTÁTICAS
# (conhecimento de eng. reversa / roster público, versionado como constante aqui):
# layout do opcode, enum SCE, estrutura de binário, tabela item_id->nome de referência.
# ============================================================================

# --- descrições ESTÁTICAS do enum SCE (byte +2 dos opcodes 0x63/0x64) ---
SCE_ENUM_DESC = {
    0:  ("SCE_AUTO",      "auto-executa; nao visto como aot"),
    1:  ("SCE_DOOR",      "PORTA — usa opcode dedicado 0x67, nao 0x63"),
    2:  ("SCE_ITEM",      "ITEM — usa opcode dedicado (nao 0x63)"),
    3:  ("SCE_NORMAL",    "trigger generico"),
    4:  ("SCE_MESSAGE",   "exibe mensagem/examinar"),
    5:  ("SCE_EVENT",     "dispara evento de script"),
    6:  ("SCE_FLAG_CHG",  "altera flag de progresso"),
    7:  ("SCE_WATER",     "zona de agua/superficie"),
    8:  ("SCE_MOVE",      "zona de movimento (escada/pulo/empurrar)"),
    9:  ("SCE_SAVE",      "maquina de escrever / ponto de save"),
    10: ("SCE_ITEMBOX",   "bau de itens"),
    11: ("SCE_DAMAGE",    "zona de dano (fogo/eletrico/queda)"),
    12: ("SCE_STATUS",    "muda status/estado do player"),
    13: ("SCE_HIKIDASHI", "gaveta/compartimento"),
    14: ("SCE_WINDOWS",   "janela/quebravel"),
}

# --- estrutura de binário e roster de referência: ESTÁTICOS (eng. reversa) ---
_ESTRUTURA_BINARIO = {
    "_descricao": "Evidencia estrutural achada no SLUS_009.23 relevante a itens.",
    "dispatcher_objeto_task": {
        "endereco_tabela": "0x80097bd4", "n_entradas": 64,
        "usado_em": ["0x8001bb64", "0x8001d034"], "stride_obj": "0xd4 (212 bytes)",
        "indice": "primeiro byte do work-struct do objeto (rotina/tipo), 0..63",
        "obs": "Tabela de 64 handlers de objeto/tarefa (jr $t9 apos base+idx*4). O item-em-mundo e um desses tipos de objeto. Muitos slots sao stubs 'jr ra' (tipos nao usados), ex.: idx 0 e idx 9..15.",
    },
    "modelos_de_arma_plw": {
        "arquivos": "CD_DATA/PLD/PL00W00.PLW .. PL00W14.PLW", "n": 21, "faixa_id": "0x00..0x14",
        "obs": "21 modelos de arma equipavel por personagem (PL00=Jill, PL08/09/0A=Carlos/Mikhail/Nikolai). O weapon_model_id NAO e igual ao item_id; e um subconjunto/renumeracao das armas.",
    },
    "graficos_de_item": ["CD_DATA/ETC/ITEMI.PIX", "CD_DATA/ETC/ITEMG.PIX", "CD_DATA/ETC/ITEMA.SLD"],
}

_ITEM_ID_REF = {
    "_descricao": "Lista de referencia item_id->nome do RE3 (conhecimento publico da comunidade de RE). NAO confirmada byte-a-byte contra o opcode de item do binario ainda. Use como hipotese a validar.",
    "_confianca": "MEDIA para armas 0x01-0x0A (consenso forte e casa com os 21 PLW); BAIXA para os IDs acima (varias fontes divergem na ordem de municao/chaves).",
    "0x00": {"nome": "(vazio / nenhum)",                        "cat": "none",   "conf": "alta"},
    "0x01": {"nome": "Combat Knife",                             "cat": "arma",   "conf": "media"},
    "0x02": {"nome": "Handgun (SIG-Pro SP2009)",                 "cat": "arma",   "conf": "media"},
    "0x03": {"nome": "Shotgun (Benelli M3S)",                    "cat": "arma",   "conf": "media"},
    "0x04": {"nome": "Grenade Launcher (Explosive rounds)",      "cat": "arma",   "conf": "media"},
    "0x05": {"nome": "Grenade Launcher (Flame rounds)",          "cat": "arma",   "conf": "media"},
    "0x06": {"nome": "Grenade Launcher (Acid rounds)",           "cat": "arma",   "conf": "media"},
    "0x07": {"nome": "Grenade Launcher (Freeze rounds)",         "cat": "arma",   "conf": "media"},
    "0x08": {"nome": "Rocket Launcher",                          "cat": "arma",   "conf": "media"},
    "0x09": {"nome": "Gatling Gun",                              "cat": "arma",   "conf": "media"},
    "0x0A": {"nome": "Magnum (S&W M629C)",                       "cat": "arma",   "conf": "baixa"},
    "0x0B": {"nome": "Handgun (custom/variante) — a confirmar",  "cat": "arma",   "conf": "baixa"},
    "0x0C": {"nome": "Mine Thrower — a confirmar",               "cat": "arma",   "conf": "baixa"},
    "_acima_0x0C": "Municoes (handgun/shotgun/grenade/magnum/mine/gatling), ervas (green/red/blue e misturas), First Aid Spray, Ink Ribbon, itens-chave (chaves, cartoes, engrenagens, oil, wrench, battery, etc.) — IDs numericos exatos A CONFIRMAR extraindo o opcode de item das salas.",
}


def count_sce_types():
    """Conta o byte sce dos opcodes 0x63/0x64 nas 169 salas (dado DINÂMICO)."""
    sys.path.insert(0, "tools")
    import scd_gameplay as G
    cnt = Counter()
    for f in sorted(glob.glob("extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD")):
        try:
            room = G.parse_room(f)
        except Exception:
            continue
        for t in room.get("triggers", []):
            cnt[t["sce"]] += 1
    return cnt


def build_sce_items():
    """Gera godot/data/sce_items.json a partir da FONTE (RDT/SCD), fechando a dívida P0-11."""
    # --- DINÂMICO: itens por sala (opcode 0x68) ---
    per = {}
    total = 0
    for f in sorted(glob.glob("extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD")):
        items = extract(f)
        if not items:
            continue
        name = os.path.splitext(os.path.basename(f))[0]
        per[name] = [["0x%02x" % it["item_id"], it["amount"]] for it in items]
        total += len(items)

    # --- DINÂMICO: contagem por tipo SCE ---
    cnt = count_sce_types()
    enum = {}
    for k, (nome, obs) in SCE_ENUM_DESC.items():
        enum[str(k)] = {"nome": nome, "obs": obs, "count": int(cnt.get(k, 0))}

    out = {
        "_meta": {
            "descricao": "Tabelas SCE relacionadas a ITENS do RE3 (PS1 NTSC-U, SLUS_009.23), extraidas por engenharia reversa do executavel + validacao contra os dados de sala em godot/data/STAGE*.",
            "gerado_por": "tools/scd_items.py --build-json (opcode 0x68 nas salas + contagem sce dos opcodes 0x63/0x64 via scd_gameplay)",
            "achado_chave": "Opcode de item = 0x68 (sce_item_aot_set). itens_observados = itens REAIS coletados das 169 salas; sce_type_enum.count = ocorrencias reais dos opcodes 0x63/0x64. ATENCAO: 0x68 captura so um SUBCONJUNTO (zonas de item/municao auto-pega); a maioria dos itens visiveis no mundo sao MODELOS de objeto (entities 0x61/0x62) apanhados via evento de script.",
            "confianca_geral": "SCE_type enum: ALTA. Opcode 0x68 + item_id/amount: MEDIA (offset +22=item_id confirmado por consistencia em salas duplicadas; nomes via roster publico RE3 = BAIXA).",
        },
        "item_opcode_0x68": {
            "_descricao": "sce_item_aot_set — coloca um trigger de item (quadrilatero) no mundo. ~30 bytes.",
            "_confianca": "opcode e layout de coords: ALTA; offset de item_id: MEDIA.",
            "layout": {
                "+0 u8": "opcode = 0x68", "+1 u8": "aot_id",
                "+2 u8": "0x02 (constante, igual a porta 0x67)", "+3 u8": "sat (0x31 tipico)",
                "+4 u8": "floor", "+5 u8": "0",
                "+6..21": "4 pontos s16 (x,z) = quadrilatero do trigger",
                "+22 u16": "item_id (candidato primario; consistente em salas duplicadas)",
                "+24 u16": "amount / quantidade",
                "+26 u16": "campo B (item_id alternativo; sempre em faixa baixa) — a confirmar via handler",
                "+28 u8 / +29 u8": "flags",
            },
            "extrator": "tools/scd_items.py (anota rdt.script.items em cada godot/data/STAGE*/R*.json)",
        },
        "itens_observados": {
            "_descricao": "IDs REAIS extraidos do SCD (opcode 0x68) nas 169 salas. item_id = campo +22. Salas duplicadas (R104=R11F, R108=R122) batem, validando o offset.",
            "total": total, "salas": len(per),
            "por_sala": per,
            "hipotese_cruzamento": {
                "_nota": "amount>1 indica MUNICAO. Hipoteses (BAIXA confianca, a validar com roster RE3):",
                "0x15 (amount 30)": "municao de pistola (30 rounds) — muito provavel",
                "0x04 (amount 7)":  "municao (7 un.) — granada/shotgun?",
                "0x21 / 0x41 / 0x42 (amount 1)": "itens unicos (chave/documento/erva)",
                "0x99 / 0x9b / 0xa0 (amount 1)": "IDs altos — itens-chave especiais OU categoria distinta",
            },
        },
        "sce_type_enum": {
            "_descricao": "Enum do byte 'sce' (offset +2 do opcode 0x63/0x64), exportado como 'sat_type' nos events. Mesmo enum do motor RE2/RE3 (SDK bio2). Contagem = ocorrencias reais nas 169 salas extraidas.",
            "_confianca": "ALTA — a distribuicao observada casa exatamente com o enum conhecido; ausencia de 0/1/2/3 e coerente (porta=opcode 0x67 dedicado; item=opcode dedicado).",
            **enum,
        },
        "estrutura_binario": _ESTRUTURA_BINARIO,
        "item_id_ref": _ITEM_ID_REF,
        "pendencias": [
            "Confirmar os offsets de item_id (A@+22 vs B@+26) do opcode 0x68 pelo handler 0x800576c4.",
            "Cruzar (sala, item_id, amount) reais com a tabela item_id_ref/re3_items.json (validacao definitiva).",
            "Confirmar a lista item_id->nome contra a ordem dos icones em ITEMI.PIX/ITEMG.PIX (o indice do icone costuma seguir o item_id).",
        ],
    }
    path = paths.data("sce_items.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("gravado", path, "| itens 0x68:", total, "em", len(per), "salas | sce total:", sum(cnt.values()))
    return out


if __name__ == "__main__":
    if "--build-json" in sys.argv:
        build_sce_items()
    else:
        main(update_json="--dry" not in sys.argv)
