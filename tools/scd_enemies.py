#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Extrai a COLOCACAO + ESPECIE de personagem/inimigo por sala do RE3 (PS1 NTSC-U)
a partir do opcode SCD 0x7d (sce_em_set / spawn de char de combate) e reescreve o
campo `enemies[]` em godot/data/STAGE{n}/{sala}_scd.json (preservando doors/items/
triggers/flags/messages). Tambem (re)gera godot/data/sce_enemies.json (tabela
class->especie + cobertura).

================================================================================
OPCODE SCD 0x7d  (handler 0x80056a2c no SLUS_009.23; base 0x80010000)
================================================================================
Provado byte-a-byte no handler (ver docs/decomp/notes/exe_ai.md sec 6 / este round):
  - O descritor lido do script vive em *(0x800e0198) = obj+0x1c (o proprio PC do
    script). PC avanca 0x18 (24) bytes no fim (0x80056d9c) -> opcode = 24 bytes.
  - O handler ALOCA uma char-struct de 0x1fc B, registra no array de personagens
    (gamestruct+0x265c[slot]) e copia os campos do descritor:

  offset  tam  ->char        significado                                   prova
  ------  ---  ------------  --------------------------------------------  --------------
  +0x00   u8   -             opcode = 0x7d                                 (dispatch VM)
  +0x01   u8   -             (nao lido pelo 0x7d; sempre 0x00 nas 169 salas) invariante
  +0x02   s8   slot idx      indice do char no array (val; -1 = sem count) 0x80056b50
  +0x03   u8   char+0x4a     CLASSE / type_id (= id de ESPECIE, num. EM##) 0x80056c64
                             (0x5b/0x5f reescritos p/ modelo do player)     0x80056acc
  +0x04   u16  char+0x46     ARMA (|0x100 no fim); bits 0x4000/0x8000=flags 0x80056c78
  +0x06   u16  char+0xd2     flags de condicao/status inicial              0x80056c84
  +0x08   u8   char+0x09     id (tambem -> char+0x122 e char+0x12e&7)       0x80056cb8
  +0x09   u8   char+0x12f    id (tabela de modelo 0x800e0198.. / +0x1498)   0x80056bb8
  +0x0a   u8   char+0x4b     id                                            0x80056ca4
  +0x0b   u8   char+0x147    MODEL id (checado vs 0xff / 0x80078930);       0x80056c90
                             0xff = sem modelo dedicado de sala (NPC/PLD/spawn)
  +0x0c   s16  char+0x34/40  POSICAO X                                      0x80056c08
  +0x0e   s16  char+0x38/42  POSICAO Y (altura)                             0x80056c20
  +0x10   s16  char+0x3c/44  POSICAO Z                                      0x80056c38
  +0x12   s16  char+0x6e     DIRECAO / angulo (12-bit)                      0x80056c50
  +0x14   u16  char+0xd8     yaw de mira inicial                            0x80056d00
  +0x16   u16  char+0xda     pitch de mira inicial                          0x80056d0c

  NAO HA campo de HP no descritor (confirma exe_ai.md sec 3.7): o HP do inimigo/
  boss vive em char+0xcc e e' setado por SCRIPT via member-set 0x80053f84 (SET) /
  0x80051b9c (SUB), nao pelo 0x7d. -> task bonus HP: NEGATIVO (nada novo aqui).

ESPECIE (class = char+0x4a):
  A CLASSE e' o type_id de combate (indexa a tabela de dano por-tipo 16..48, e a IA).
  O nome de especie vem da convencao EM## (arquivos EMD do port de PC/GOG,
  identificados por render em docs/decomp/notes/enemy_mesh.md): a hipotese e'
  class == numero-do-arquivo-EM## (hex). ANCORA: sala R101 (zumbi) usa class 0x10 e
  EM10 = zumbi confirmado (EM10.TIM == R101.BIN blk6). Demais especies: inferidas
  pela convencao + roster (docs/referencias/evilresource.md) -> confianca marcada.
  (Nota: e' um espaco de id DIFERENTE do indice T64 da IA/work-struct 0xD4, cujo
   mapeamento por-tamanho em exe_ai.md tambem e' 🟡; os dois pools coexistem.)
"""
import struct, glob, os, json, sys
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, "tools")
import scd_decode as S

CHAR_CREATE_OP = 0x80056a2c   # handler do opcode 0x7d
OP = 0x7d
OPLEN = 24

# ---------------------------------------------------------------------------
# Tabela class(char+0x4a) -> especie. Fonte dos nomes: docs/decomp/notes/enemy_mesh.md
# (renders dos EMD do GOG) + roster evilresource.md. Confianca:
#   ALTA   = ancorado (render + correlacao de sala byte-a-byte)
#   MEDIA  = render de especie claro + convencao class==EM## + papel plausivel
#   BAIXA  = palpite por convencao/silhueta (marcado _incerto no asset)
# ---------------------------------------------------------------------------
SPECIES = {
    0x10: ("Zumbi (macho)",              "ALTA",  "enemy"),   # R101; EM10 render+TIM
    0x11: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x12: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x13: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x14: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x15: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x16: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x17: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x18: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x19: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x1a: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x1b: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x1c: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x1d: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x1e: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x1f: ("Zumbi (variante)",           "MEDIA", "enemy"),
    0x20: ("Cao zumbi (Cerberus)",       "MEDIA", "enemy"),   # EM20 render (dobermann)
    0x21: ("Corvo",                      "MEDIA", "enemy"),   # EM21 render
    0x22: ("Hunter beta",                "BAIXA", "enemy"),   # EM22 bipede
    0x23: ("Hunter gamma",               "BAIXA", "enemy"),   # EM23 bipede
    0x24: ("(bipede a confirmar)",       "BAIXA", "enemy"),   # EM24
    0x25: ("Aranha gigante",             "MEDIA", "enemy"),   # EM25 render
    0x26: ("Aranha (cria/pequena)",      "BAIXA", "enemy"),   # EM26; model_id=ff (spawn)
    0x27: ("(spawn/parte a confirmar)",  "BAIXA", "enemy"),   # EM27
    0x28: ("Drain Deimos",               "BAIXA", "enemy"),   # EM28 render insectoide
    0x29: ("Sliding Worm (?)",           "BAIXA", "enemy"),   # roster
    0x2a: ("(a confirmar)",              "BAIXA", "enemy"),
    0x2b: ("(a confirmar)",              "BAIXA", "enemy"),
    0x2c: ("(humanoide a confirmar)",    "BAIXA", "enemy"),   # EM2C
    0x2d: ("(humanoide a confirmar)",    "BAIXA", "enemy"),   # EM2D (emd corrompido)
    0x2e: ("(humanoide a confirmar)",    "BAIXA", "enemy"),   # EM2E
    0x2f: ("(a confirmar)",              "BAIXA", "enemy"),   # EM2F
    0x30: ("Verme (Grave Digger?)",      "BAIXA", "enemy"),   # EM30
    0x31: ("(a confirmar)",              "BAIXA", "enemy"),
    0x32: ("Verme (Sliding Worm?)",      "BAIXA", "enemy"),   # EM32
    0x33: ("Verme (Grave Digger?)",      "BAIXA", "enemy"),   # EM33
    0x34: ("(comum/ubiquo - a confirmar)", "BAIXA", "enemy"), # EM34 insectoide? mas em 37 salas
    0x35: ("Drain Deimos (?)",           "BAIXA", "enemy"),   # EM35 insectoide
    0x36: ("(humanoide a confirmar)",    "BAIXA", "enemy"),   # EM36
    0x37: ("(spawn/parte a confirmar)",  "BAIXA", "enemy"),   # EM37
    0x38: ("Nemesis (?)",                "BAIXA", "boss"),    # EM38 bipede grande; 1 sala; model_id=ff
    0x39: ("(spawn/parte a confirmar)",  "BAIXA", "enemy"),
    0x3a: ("(humanoide a confirmar)",    "BAIXA", "enemy"),   # EM3A
    0x3b: ("(spawn/parte a confirmar)",  "BAIXA", "enemy"),
    0x3e: ("Helicoptero/veiculo (evento)", "BAIXA", "enemy"), # EM3E = HELICOPTERO (render, ver EMD_ROSTER)
    0x3f: ("Helicoptero/veiculo (evento)", "BAIXA", "enemy"), # EM3F = HELICOPTERO (render, ver EMD_ROSTER)
    0x40: ("(spawn/parte a confirmar)",  "BAIXA", "enemy"),
    0x44: ("(a confirmar)",              "BAIXA", "enemy"),
    0x78: ("(evento/misc a confirmar)",  "BAIXA", "enemy"),
}


# ---------------------------------------------------------------------------
# CAMADA DE ANOTACAO POR ARQUIVO EMD  (EM##.EMD do port de PC/GOG -> especie)
# ---------------------------------------------------------------------------
# ESTA E' UMA ANOTACAO, NAO PROVA. O mapa canonico EM##<->especie NAO existe
# estaticamente no EXE (sem tabela de nomes) e NAO esta publicado 1:1 em wiki de
# modding (o unico esquema EMD publicado e' o do RE1, numeracao diferente -- busca
# web jul/2026: evilresource/tapatalk trazem ROSTER de especies, nao o n. do arquivo).
# Fonte da anotacao: (a) render texturizado front (montage 1-launch, tools_enemy_montage.gd),
# (b) roster canonico RE3 (zumbi, Cerberus, corvo, Hunter b/g, aranha, Drain Deimos,
# Brain Sucker, Sliding Worm, Grave Digger, Nemesis, helicoptero, NPCs), (c) n. de ossos/
# verts/anims e contexto de sala. Confianca do render:
#   ALTA     = silhueta/skin inequivoca + 1 especie no roster (ou byte-prova, p/ EM10)
#   MEDIA    = categoria clara no render + 1 especie plausivel no roster + convencao
#   categoria= e' humano (NPC) sem duvida, mas QUAL humano (Nicholai/Carlos/...) nao fecha
#   BAIXA    = fragmento/parte (1-6 ossos) ou humanoide gerico sem tra o distintivo
# Campos: (nome_anotado, conf_render, ossos, verts, anims, evidencia).
EMD_ROSTER = {
    "EM10": ("Zumbi (macho)",                 "ALTA",  15, 418, 8,  "EM10.TIM==R101.BIN blk6 (byte-prova) + render"),
    "EM11": ("Zumbi (variante)",              "MEDIA", 15, 460, 8,  "render humanoide zumbi"),
    "EM12": ("Zumbi (variante)",              "MEDIA", 15, 502, 8,  "render humanoide zumbi"),
    "EM13": ("Zumbi (variante)",              "MEDIA", 15, 520, 8,  "render humanoide zumbi"),
    "EM14": ("Zumbi (variante)",              "MEDIA", 15, 496, 8,  "render humanoide zumbi"),
    "EM15": ("Zumbi (variante)",              "MEDIA", 15, 533, 8,  "render humanoide zumbi"),
    "EM16": ("Zumbi (variante)",              "MEDIA", 11, 376, 5,  "render humanoide zumbi (flags no u16 alto, corrigido)"),
    "EM17": ("Zumbi (variante)",              "MEDIA", 15, 610, 8,  "render humanoide zumbi"),
    "EM18": ("Zumbi (variante)",              "MEDIA", 11, 392, 5,  "render humanoide zumbi"),
    "EM19": ("Zumbi (variante)",              "MEDIA", 11, 362, 5,  "render humanoide zumbi"),
    "EM1A": ("Zumbi (variante)",              "MEDIA", 11, 439, 5,  "render humanoide zumbi"),
    "EM1B": ("Zumbi (variante)",              "MEDIA", 11, 415, 5,  "render humanoide zumbi"),
    "EM1C": ("Zumbi (variante)",              "MEDIA", 11, 347, 5,  "render humanoide zumbi"),
    "EM1D": ("Zumbi (variante)",              "MEDIA", 11, 401, 5,  "render humanoide zumbi"),
    "EM1E": ("Zumbi (variante)",              "MEDIA", 11, 376, 5,  "render humanoide zumbi (flags no u16 alto, corrigido)"),
    "EM1F": ("Zumbi (variante)",              "MEDIA", 11, 391, 5,  "render humanoide zumbi"),
    "EM20": ("Cao zumbi (Cerberus)",          "ALTA",  17, 395, 27, "render: dobermann esfolado (quadrupede)"),
    "EM21": ("Corvo",                         "ALTA",  10, 134, 10, "render: ave/corvo"),
    "EM22": ("Hunter (beta?)",                "MEDIA", 20, 737, 32, "render: bipede reptiliano; beta vs gamma nao distinguido"),
    "EM23": ("Hunter (gamma?)",               "MEDIA", 21, 1100,32, "render: bipede reptiliano; beta vs gamma nao distinguido"),
    "EM24": ("Bipede (Hunter/variante?)",     "BAIXA", 20, 686, 34, "render: bipede escuro, especie nao fechada"),
    "EM25": ("Aranha gigante",                "ALTA",  20, 726, 13, "render: aracnideo 8-patas listrado"),
    "EM26": ("Fragmento (aranha cria?)",      "BAIXA", 1,  18,  0,  "1 osso, 18 verts: particula/parte, nao criatura"),
    "EM27": ("Fragmento/parte",               "BAIXA", 2,  97,  3,  "2 ossos: parte/spawn"),
    "EM28": ("Insectoide (Drain Deimos/Brain Sucker)", "MEDIA", 21, 750, 36, "render: insectoide crawler"),
    "EM2C": ("Humanoide (a confirmar)",       "BAIXA", 15, 518, 2,  "render humanoide gerico"),
    "EM2D": ("Indeterminado (forma esparsa)", "BAIXA", 15, 529, 6,  "geometria esparsa (era 'corrompido'; agora integro, mas render nao identificavel)"),
    "EM2E": ("Humanoide (a confirmar)",       "BAIXA", 15, 718, 8,  "render humanoide gerico"),
    "EM2F": ("Humanoide (a confirmar)",       "BAIXA", 15, 694, 8,  "render humanoide gerico"),
    "EM30": ("Verme/alongado (Grave Digger?)","MEDIA", 17, 1121,26, "render: corpo alongado segmentado"),
    "EM32": ("Verme/alongado (Sliding Worm?)","MEDIA", 6,  109, 12, "render: corpo alongado afilado"),
    "EM33": ("Verme/alongado (Grave Digger?)","MEDIA", 17, 1121,14, "render: alongado (geom == EM30)"),
    "EM34": ("Insectoide (Brain Sucker/Drain Deimos)", "MEDIA", 16, 985, 31, "render: insectoide"),
    "EM35": ("Insectoide (Drain Deimos?)",    "MEDIA", 16, 972, 33, "render: insectoide"),
    "EM36": ("Humanoide grande (a confirmar)","BAIXA", 16, 1209,37, "render humanoide grande"),
    "EM37": ("Fragmento/parte",               "BAIXA", 6,  62,  10, "6 ossos, 62 verts: parte"),
    "EM38": ("Nemesis (forma)",               "MEDIA", 22, 1184,30, "render: bipede grande/musculoso; forma nao fechada"),
    "EM39": ("Fragmento/parte",               "BAIXA", 6,  62,  2,  "6 ossos, 62 verts: parte"),
    "EM3A": ("Humanoide grande (a confirmar)","BAIXA", 16, 1209,5,  "render humanoide grande (geom == EM36)"),
    "EM3B": ("Fragmento/parte",               "BAIXA", 6,  62,  1,  "6 ossos, 62 verts: parte"),
    "EM3E": ("Helicoptero (civil, azul)",     "ALTA",  5,  365, 0,  "render INEQUIVOCO: helicoptero (rotor/cauda/skids). VEICULO, nao verme"),
    "EM3F": ("Helicoptero (militar, cinza)",  "ALTA",  8,  915, 0,  "render INEQUIVOCO: helicoptero militar. VEICULO, nao verme"),
    "EM40": ("Fragmento/objeto",              "BAIXA", 5,  110, 0,  "5 ossos, 110 verts: parte/objeto"),
    "EM50": ("NPC humano",                    "categoria", 16, 966, 17, "render humano; qual NPC nao fechado"),
    "EM51": ("NPC humano",                    "categoria", 16, 997, 7,  "render humano"),
    "EM52": ("NPC humano",                    "categoria", 16, 978, 7,  "render humano"),
    "EM53": ("NPC humano",                    "categoria", 16, 810, 7,  "render humano"),
    "EM54": ("NPC humano",                    "categoria", 15, 676, 7,  "render humano"),
    "EM55": ("NPC humano",                    "categoria", 15, 718, 7,  "render humano"),
    "EM56": ("NPC humano",                    "categoria", 16, 978, 7,  "render humano (camisa/jeans)"),
    "EM57": ("NPC humano (civil)",            "categoria", 15, 694, 7,  "render humano (civil, vestido)"),
    "EM58": ("NPC humano",                    "categoria", 15, 705, 7,  "render humano"),
    "EM59": ("NPC humano",                    "categoria", 15, 675, 7,  "render humano"),
    "EM5A": ("NPC humano",                    "categoria", 15, 520, 7,  "render humano"),
    "EM5B": ("NPC humano",                    "categoria", 16, 778, 7,  "render humano"),
    "EM5C": ("NPC humano",                    "categoria", 16, 1017,17, "render humano"),
    "EM5D": ("NPC humano",                    "categoria", 16, 1005,17, "render humano"),
    "EM5E": ("NPC humano",                    "categoria", 16, 1034,7,  "render humano"),
    "EM5F": ("NPC humano",                    "categoria", 16, 781, 7,  "render humano"),
    "EM60": ("NPC humano",                    "categoria", 15, 887, 7,  "render humano"),
    "EM61": ("NPC humano",                    "categoria", 15, 525, 7,  "render humano"),
    "EM62": ("NPC humano",                    "categoria", 16, 680, 7,  "render humano"),
    "EM63": ("NPC humano",                    "categoria", 16, 659, 7,  "render humano"),
    "EM64": ("NPC humano",                    "categoria", 15, 670, 0,  "render humano (hierarquia invalida -> sem FK, geometria ok)"),
    "EM65": ("NPC humano",                    "categoria", 16, 721, 7,  "render humano"),
    "EM66": ("NPC humano",                    "categoria", 16, 750, 7,  "render humano"),
    "EM67": ("NPC humano",                    "categoria", 15, 669, 17, "render humano"),
    "EM70": ("NPC humano",                    "categoria", 16, 778, 7,  "render humano"),
    "EM71": ("NPC humano",                    "categoria", 16, 680, 7,  "render humano"),
}


def emd_annotation(cls):
    """Anotacao do EMD de mesmo numero (convencao class==EM## hex). Retorna dict ou None.
    NB: o link class->EM## e' CONVENCAO (nao provada, exceto ancora EM10<->class 0x10)."""
    key = "EM%02X" % cls
    r = EMD_ROSTER.get(key)
    if not r:
        return None
    return {"emd_file": key + ".EMD", "render_species": r[0], "render_conf": r[1],
            "bones": r[2], "verts": r[3], "anims": r[4], "evidencia": r[5]}


def species_of(cls):
    if cls < 0x08:
        return ("Player/aliado", "ALTA", "player_ally")
    if 0x50 <= cls <= 0x71:
        return ("NPC humano (Nicholai/Carlos/Mikhail/Brad/...)", "categoria", "npc")
    if cls in SPECIES:
        return SPECIES[cls]
    return ("(desconhecido)", "BAIXA", "enemy" if cls < 0x50 else "npc")


# ---------------------------------------------------------------------------
# CRUZAMENTO COM O CONTEXTO DE SALA (catalog.json dos meshes embutidos no R###.BIN)
# -----------------------------------------------------------------------------
# godot/assets/ENEMY/catalog.json agrupa as salas pelo HASH do mesh de inimigo
# embutido no R###.BIN. Cruzando class->salas->hash da' um BOUND estatico da especie:
#   * ANCORA provada: hash 605afd27 = mesh de R101 = EM10 = ZUMBI (EM10.TIM == R101 blk6).
#   * model_id (desc+0x0b) e' um SLOT de mesh carregado por sala (varia por sala p/ a mesma
#     class) -> NAO nomeia especie estaticamente. Confirmado: model_id INSTAVEL por class
#     (ex.: class 0x10 usa model_id 25..186; NPCs 0x50+ usam sempre 0xff).
#   * Logo class<->mesh e' MUITOS-p/-MUITOS por sala (varias classes numa sala de 1 mesh;
#     1 classe em salas de meshes diferentes). A especie so se resolve em RUNTIME (qual mesh
#     a sala carregou no slot). O melhor bound ESTATICO = o hash de mesh DOMINANTE da class.
CATALOG_PATH = paths.assets("ENEMY", "catalog.json")
MESH_ANCHOR = {"605afd27": "Zumbi (mesh EM10, ancora R101)"}  # unico hash provado


def load_catalog():
    try:
        cat = json.load(open(CATALOG_PATH, encoding="utf-8"))
    except Exception:
        return {}
    r2m = {}
    for k, v in cat.get("room_to_meshes", {}).items():
        rn = os.path.basename(k).split(".")[0]           # STAGE1/R101.BIN -> R101
        r2m[rn] = [h for h, sz in v if h != "empty"]
    return r2m


def class_mesh_profile(rooms, room2mesh):
    """rooms = set de salas onde a class aparece. Retorna (Counter de hash, dominante, frac)."""
    hh = {}
    for r in rooms:
        for h in room2mesh.get(r, []):
            hh[h] = hh.get(h, 0) + 1
    if not hh:
        return {}, None, 0.0
    order = sorted(hh.items(), key=lambda x: -x[1])
    dom, domn = order[0]
    frac = domn / sum(hh.values())
    return hh, dom, round(frac, 2)


def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def s8(b, o):
    return struct.unpack_from("<b", b, o)[0]


def script_region(rdt):
    offs = struct.unpack_from("<22I", rdt, 8)
    so = offs[16]
    later = [t for t in offs if so < t <= len(rdt)]
    end = min(later) if later else len(rdt)
    return so, end


def extract(path):
    """Retorna (enemies, actors) do 0x7d. enemies = class>=0x10 (inimigo/boss/npc);
    actors = class<0x10 (player/aliado). Dedup por (class,x,y,z,dir,weapon)."""
    data = open(path, "rb").read()
    rdt = S.rdt_of(data)
    so, end = script_region(rdt)
    b = rdt
    dedup = {}
    order = []
    i = so
    while i < end - OPLEN:
        if b[i] == OP and b[i + 1] == 0x00:
            cls = b[i + 3]
            x = s16(b, i + 0xc); y = s16(b, i + 0xe); z = s16(b, i + 0x10)
            if 0x08 <= cls <= 0x78 and abs(x) < 32000 and abs(z) < 32000:
                d = s16(b, i + 0x12)
                wpn = u16(b, i + 0x04)
                key = (cls, x, y, z, d, wpn)
                if key in dedup:
                    dedup[key]["occurrences"] += 1
                else:
                    name, conf, kind = species_of(cls)
                    rec = {
                        "class": cls, "class_hex": "0x%02x" % cls,
                        "species": name, "species_conf": conf, "kind": kind,
                        "x": x, "y": y, "z": z, "dir": d,
                        "weapon": wpn, "slot": s8(b, i + 0x02),
                        "model_id": b[i + 0x0b],
                        "status_flags": u16(b, i + 0x06),
                        "ids": [b[i + 0x08], b[i + 0x09], b[i + 0x0a], b[i + 0x0b]],
                        "aim": [u16(b, i + 0x14), u16(b, i + 0x16)],
                        "occurrences": 1,
                        "opcode": OP,
                        "raw": b[i:i + OPLEN].hex(),
                    }
                    dedup[key] = rec
                    order.append(key)
                i += OPLEN
                continue
        i += 1
    recs = [dedup[k] for k in order]
    enemies = [r for r in recs if r["kind"] != "player_ally"]
    actors = [r for r in recs if r["kind"] == "player_ally"]
    return enemies, actors


def main(update_json=True):
    files = sorted(glob.glob("extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD"))
    per_room = {}
    class_room_count = {}    # class -> nº de salas onde aparece
    class_total = {}         # class -> nº de placements (dedup)
    class_rooms = {}         # class -> set de nomes de sala (p/ cruzar com catalog.json)
    room2mesh = load_catalog()
    tot_enemy = tot_npc = tot_boss = 0
    rooms_with_enemy = 0
    missing = []
    for f in files:
        stage_dir = os.path.basename(os.path.dirname(f))
        name = os.path.splitext(os.path.basename(f))[0]
        enemies, actors = extract(f)
        per_room[name] = (enemies, actors, stage_dir)
        classes_here = set()
        for r in enemies:
            classes_here.add(r["class"])
            class_total[r["class"]] = class_total.get(r["class"], 0) + 1
            if r["kind"] == "npc":
                tot_npc += 1
            elif r["kind"] == "boss":
                tot_boss += 1
            else:
                tot_enemy += 1
        for c in classes_here:
            class_room_count[c] = class_room_count.get(c, 0) + 1
            class_rooms.setdefault(c, set()).add(name)
        real = [r for r in enemies if r["kind"] in ("enemy", "boss")]
        if real:
            rooms_with_enemy += 1

        if update_json:
            jp = os.path.join(paths.data(), stage_dir, name + "_scd.json")
            if not os.path.exists(jp):
                missing.append(name)
                continue
            d = json.load(open(jp, encoding="utf-8"))
            # preserva o antigo 0x61/0x62 (modelos de objeto/NPC) sob 'objects'
            old = d.get("enemies")
            if old and "objects" not in d and old and old[0].get("opcode") in (0x61, 0x62, 97, 98):
                d["objects"] = old
            d["enemies"] = enemies
            if actors:
                d["actors"] = actors
            m = d.setdefault("_meta", {})
            m["aviso_inimigos"] = (
                "enemies[] = spawns REAIS do opcode SCD 0x7d (sce_em_set/char de combate, "
                "handler 0x80056a2c). class(+3)=char+0x4a=type_id de especie (convencao EM##; "
                "ancora zumbi=0x10). pos=x/y/z, dir=angulo. dedup por (class,x,y,z,dir,weapon); "
                "occurrences=nº de vezes declarado (branches de cenario Jill/Carlos/dificuldade). "
                "kind: enemy|boss|npc. 'objects' = antigo 0x61/0x62 (modelos posicionados). "
                "Especie: confianca em species_conf. Ver tools/scd_enemies.py e godot/data/sce_enemies.json.")
            json.dump(d, open(jp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # ---- tabela sce_enemies.json ----
    n_species_conf = sum(1 for c in class_total if species_of(c)[1] in ("ALTA", "MEDIA"))
    n_classes = len(class_total)
    struct_doc = {
        "opcode": "0x7d",
        "handler_exe": "0x80056a2c",
        "descriptor_ptr": "0x800e0198 (= obj+0x1c, PC do script)",
        "size_bytes": 24,
        "prova": "PC += 0x18 em 0x80056d9c; campos lidos do handler (ver tools/scd_enemies.py)",
        "campos": {
            "+0x00": "u8  opcode 0x7d",
            "+0x01": "u8  nao usado pelo 0x7d (sempre 0x00 nas 169 salas)",
            "+0x02": "s8  slot idx (indice no array de personagens; -1 = especial)",
            "+0x03": "u8  CLASSE/type_id -> char+0x4a (= id de especie; indexa tabela de dano)",
            "+0x04": "u16 ARMA -> char+0x46 (|0x100; bits 0x4000/0x8000 = flags)",
            "+0x06": "u16 flags de condicao/status inicial -> char+0xd2",
            "+0x08": "u8  id -> char+0x09 (e char+0x122 / char+0x12e&7)",
            "+0x09": "u8  id -> char+0x12f (selecao de modelo)",
            "+0x0a": "u8  id -> char+0x4b",
            "+0x0b": "u8  MODEL id -> char+0x147 (0xff = sem modelo dedicado: NPC/PLD/spawn)",
            "+0x0c": "s16 POS X -> char+0x34/+0x40",
            "+0x0e": "s16 POS Y (altura) -> char+0x38/+0x42",
            "+0x10": "s16 POS Z -> char+0x3c/+0x44",
            "+0x12": "s16 DIRECAO/angulo -> char+0x6e",
            "+0x14": "u16 yaw de mira inicial -> char+0xd8",
            "+0x16": "u16 pitch de mira inicial -> char+0xda",
        },
        "hp": "SEM campo de HP no descritor (confirma exe_ai.md 3.7). HP do inimigo/boss "
              "= char+0xcc, setado por script (member-set 0x80053f84 / sub 0x80051b9c).",
    }
    class_table = {}
    for c in sorted(class_total):
        name, conf, kind = species_of(c)
        hh, dom, frac = class_mesh_profile(class_rooms.get(c, set()), room2mesh)
        # cruzamento com o mesh DOMINANTE do R###.BIN (bound estatico da especie).
        # so' emite o hint quando ha' concentracao real (frac>=0.4) p/ nao superestimar:
        # NB achado honesto -- ate a class-ancora 0x10 concentra so' ~0.25 no mesh do zumbi,
        # confirmando que o mesh de sala NAO determina a especie da class de forma limpa.
        mesh_hint = MESH_ANCHOR.get(dom) if (dom and frac >= 0.4) else None
        # upgrade honesto: class do range zumbi (0x10..0x1f) cujo mesh dominante e' o do
        # zumbi (605afd27) => familia zumbi CONFIRMADA pelo contexto de sala
        if 0x10 <= c <= 0x1f and dom == "605afd27" and frac >= 0.5 and conf == "MEDIA":
            conf = "MEDIA+"   # convencao EM## + mesh de sala concordam
        entry = {
            "class": c, "species": name, "conf": conf, "kind": kind,
            "n_rooms": class_room_count.get(c, 0), "n_placements": class_total[c],
            # --- ANOTACAO por EMD de mesmo numero (convencao class==EM## hex; ver EMD_ROSTER) ---
            "emd_annotation": emd_annotation(c),
            # --- cruzamento com contexto de sala (catalog.json) ---
            "mesh_hashes": hh,                    # hash do mesh embutido -> nº de salas da class
            "dominant_mesh": dom, "dominant_frac": frac,
            "mesh_species_hint": mesh_hint,       # so' preenchido p/ hash provado (605afd27=zumbi)
        }
        class_table["0x%02x" % c] = entry

    # ---- camada de anotacao por EMD (roster completo dos 69 arquivos) ----
    emd_ann = {}
    conf_count = {"ALTA": 0, "MEDIA": 0, "categoria": 0, "BAIXA": 0}
    for key in sorted(EMD_ROSTER):
        nm, cf, nb, nv, na, ev = EMD_ROSTER[key]
        emd_ann[key] = {"render_species": nm, "render_conf": cf, "bones": nb,
                        "verts": nv, "anims": na, "evidencia": ev}
        conf_count[cf] = conf_count.get(cf, 0) + 1
    n_emd = len(EMD_ROSTER)
    emd_cov = {
        "total_emd": n_emd,
        "ALTA": conf_count["ALTA"], "MEDIA": conf_count["MEDIA"],
        "categoria_humano": conf_count["categoria"], "BAIXA": conf_count["BAIXA"],
        "pct_ALTA": round(100.0 * conf_count["ALTA"] / n_emd, 1),
        "pct_ALTA_ou_MEDIA": round(100.0 * (conf_count["ALTA"] + conf_count["MEDIA"]) / n_emd, 1),
        "pct_categoria_ou_melhor": round(100.0 * (n_emd - conf_count["BAIXA"]) / n_emd, 1),
    }
    out = {
        "_meta": {
            "descricao": "Colocacao + especie de personagem/inimigo por sala do RE3 (PS1 NTSC-U) "
                         "via opcode SCD 0x7d (sce_em_set). Gerado por tools/scd_enemies.py.",
            "gerado_por": "tools/scd_enemies.py (extractor) + disasm de 0x80056a2c (struct)",
            "cobertura": {
                "salas_com_inimigo_real": rooms_with_enemy,
                "placements_enemy": tot_enemy, "placements_boss": tot_boss,
                "placements_npc": tot_npc,
                "classes_distintas": n_classes,
                "classes_com_especie_conf": n_species_conf,
                "pct_class_com_especie": round(100.0 * n_species_conf / max(1, n_classes), 1),
            },
            "confianca": "struct do 0x7d: ALTA (byte-a-byte). class->especie: ancora zumbi(0x10) ALTA; "
                         "cao/corvo/aranha MEDIA; demais BAIXA (convencao EM## nao provada 1:1 no exe).",
            "cobertura_emd_render": emd_cov,
            "camada_anotacao": (
                "A NOMEACAO de especie e' uma CAMADA DE ANOTACAO sobre o dado extraido (a extracao "
                "do 0x7d e' 100% byte-a-byte; a especie por-nome NAO e'). Fontes da anotacao: render "
                "texturizado dos 69 EMD (montage 1-launch) + roster canonico RE3 + ossos/verts/anims + "
                "contexto de sala. O mapa canonico EM##<->especie NAO existe estaticamente no EXE e NAO "
                "esta publicado 1:1 (busca web jul/2026: so' o esquema EMD do RE1 e' publico; para RE3 "
                "as wikis listam o ROSTER de especies, nao o numero do arquivo). Logo o teto honesto e' "
                "esta anotacao com confianca explicita por EMD (ver emd_annotations) e por class "
                "(class_to_species[*].emd_annotation). CORRECAO deste round: EM3E/EM3F sao HELICOPTEROS "
                "(render inequivoco), nao vermes; EM2D deixou de ser 'corrompido' (bug de parser corrigido) "
                "e agora exporta integro (mas o render nao identifica a especie -> BAIXA)."),
            "cruzamento_sala": {
                "fonte": "godot/assets/ENEMY/catalog.json (hash do mesh embutido no R###.BIN por sala)",
                "campos": "class_to_species[*].mesh_hashes/dominant_mesh/dominant_frac/mesh_species_hint",
                "ancora_provada": "hash 605afd27 = mesh de R101 = EM10 = ZUMBI (EM10.TIM == R101 blk6)",
                "residuo_exato": (
                    "class<->especie NAO e' 100% determinavel estaticamente. PROVA: (1) model_id "
                    "(desc+0x0b, o SLOT de mesh real) e' INSTAVEL por class (class 0x10 usa model_id "
                    "25..186; NPC 0x50+ sempre 0xff); (2) class<->mesh e' muitos-p/-muitos por sala "
                    "(varias classes numa sala de 1 mesh; 1 class em salas de meshes diferentes). "
                    "A especie so se resolve em RUNTIME (qual mesh a sala carregou no slot model_id). "
                    "O bound estatico maximo = o hash de mesh DOMINANTE da class (dominant_mesh) + a "
                    "convencao EM##. So o hash 605afd27 esta ligado a uma especie por prova byte-a-byte."),
            },
            "linkage_investigation": {
                "hipotese": "Existe tabela ESTATICA type(char+0x4a)->fileid EM## no EXE (analoga a tabela "
                            "de portas 0x8009dfd0[stage][room])? -> RESPOSTA: NAO. Provado em 3 niveis (EXE/BIN/ARD).",
                "prova_exe_sem_tabela_de_nome": (
                    "Unicas strings de modelo no SLUS_009.23: 'bio19/room/emd/em10.tim' (@file 0x88300 / "
                    "vaddr 0x80097b00), '.../em10.emd' (0x88328/0x80097b28), '.../emd08/em10.emd' "
                    "(0x88350/0x80097b50). So 'em10' (nao ha %02X/%d nem uma por type); nao sao referenciadas "
                    "por nenhum ponteiro u32 no EXE -> leftovers de dev/mortos. NAO existe tabela de nomes por type."),
                "prova_spawn_usa_slot_nao_type": (
                    "Handler 0x7d (0x80056a2c): o MODELO vem de desc+0x0b (model_id), checado contra um BITMAP "
                    "de modelos carregados em gs+0x7890 via 0x80078930 (bit-test: word[model_id>>5], bit[model_id&0x1f]). "
                    "Se o bit nao esta setado, o spawn e' ABORTADO (0x80056aa8 -> 0x80056d94). O type (desc+0x03) "
                    "so vai p/ char+0x4a (AI/dano); NAO deriva arquivo. Logo o modelo e' um SLOT carregado por sala."),
                "prova_room_load_sem_type_tag": (
                    "O loader de modelo do room-load (0x800137f0+, chama 0x800150b0) itera a TABELA DE BLOCOS do "
                    "R###.BIN (stride 8: size@0, tag@4) e carrega por TAG = endereco de RAM (0x80xx0000 p/ modelo). "
                    "O tag e' destino de carga, NAO um id de type. A ARD (script SCD) posiciona por opcode, sem tabela "
                    "type->modelo. MODEL_TBL 0x800ba728 (chave=type) e' RUNTIME, populada no room-load."),
                "empirico_ids_estaveis": (
                    "PS1 embute so 1-2 meshes de inimigo por sala (limite de RAM) e reusa em TODOS os spawns. "
                    "model_id->mesh e' 83/189 unico; class->mesh 15/47 -> ambos contaminados (1 mesh serve varias "
                    "classes/model_ids da sala). TIM byte-identico (ground truth): 35 salas casam o skin de inimigo "
                    "com um EM##.TIM do PC. A mesh 605afd27 aparece com os TIM EM10/EM18/EM1B => 605afd27 = FAMILIA "
                    "ZUMBI confirmada (varios skins, um mesh); e um mesmo tamanho de TIM (99872) tem 2 texturas "
                    "distintas (EM10 vs EM23). Ou seja, o linkage e' m:n em TODO id estavel (type, model_id, mesh, TIM)."),
                "conclusao": (
                    "A intuicao do usuario ('tem tags/ids') esta certa quanto a EXISTIREM ids estaveis (type=char+0x4a "
                    "p/ AI; identidade de mesh/TIM), mas NAO existe TABELA ESTATICA canonica type->EM##/especie no jogo. "
                    "A especie liga-se ao modelo em ROOM-LOAD, a partir dos blocos embutidos no R###.BIN (sem type-tag). "
                    "Melhor bound estatico = mesh embutida por sala (byte-casavel a EM## via TIM) + classe dominante. "
                    "Confianca NAO elevada a ALTA por convencao pois nao ha tabela que a sustente; a familia ZUMBI "
                    "(mesh 605afd27, 14 salas por TIM byte-identico) segue a unica ancora byte-provada."),
            },
        },
        "opcode_0x7d": struct_doc,
        "class_to_species": class_table,
        "emd_annotations": emd_ann,
    }
    json.dump(out, open(paths.data("sce_enemies.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    # ---- relatorio ----
    print("== 0x7d (sce_em_set) — colocacao + especie ==")
    print("salas processadas:", len(files), "| com inimigo real:", rooms_with_enemy)
    print("placements: enemy=%d boss=%d npc=%d | classes distintas=%d" % (
        tot_enemy, tot_boss, tot_npc, n_classes))
    print("classes com especie (ALTA/MEDIA): %d/%d (%.0f%%)" % (
        n_species_conf, n_classes, 100.0 * n_species_conf / max(1, n_classes)))
    print("EMD render annot: %d EMD | ALTA=%d MEDIA=%d categoria(humano)=%d BAIXA=%d "
          "| ALTA+MEDIA=%.0f%% | categoria-ou-melhor=%.0f%%" % (
              emd_cov["total_emd"], emd_cov["ALTA"], emd_cov["MEDIA"],
              emd_cov["categoria_humano"], emd_cov["BAIXA"],
              emd_cov["pct_ALTA_ou_MEDIA"], emd_cov["pct_categoria_ou_melhor"]))
    if missing:
        print("SEM _scd.json (%d):" % len(missing), missing[:10])
    print("\nclass  hex   especie                              conf   salas  placements")
    for c in sorted(class_total):
        name, conf, kind = species_of(c)
        print("  %3d 0x%02x  %-36s %-6s %4d   %4d" % (
            c, c, name[:36], conf, class_room_count.get(c, 0), class_total[c]))


if __name__ == "__main__":
    main(update_json="--dry" not in sys.argv)
