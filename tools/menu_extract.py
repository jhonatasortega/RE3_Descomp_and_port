#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""menu_extract.py - Extrai os graficos das TELAS DE MENU do RE3 (PS1 NTSC-U).

Os arquivos `extracted/ntsc-u/CD_DATA/BIN/*.BIN` (TITLE, JILL_SEL, OPTION,
MEM_CARD, RESULT, SELECT, WARNING, GEARBOX, ...) NAO sao os conteineres de
sala R###.BIN. Sao OVERLAYS EXECUTAVEIS do PS1:

  +0x00  u32  N   (numero de ponteiros da tabela de dispatch)
  +0x04  u32[N]   ponteiros relocados p/ RAM do PS1 (0x8018xxxx..0x801Cxxxx)
  ...            codigo MIPS + strings de rotulo ("OMBG.TIM", "MEMORY CARD BG")
  ...            + os graficos da tela embutidos como TIM (formato padrao PS1)

Ou seja: a tabela de ponteiros e o codigo sao carregados num endereco fixo da
RAM; os TIMs sao os graficos que o overlay envia p/ a VRAM da GPU.

Este modulo faz um SCAN estrutural: procura o magic TIM (0x10 00 00 00) e valida
os blocos CLUT+imagem (tamanho == 12 + w*h*2) p/ descartar os falsos positivos
que aparecem no codigo. Cada TIM valido e renderizado p/ PNG (uma imagem por
CLUT quando ha multiplas paletas).

Uso:
  python tools/menu_extract.py scan   <arq.BIN>            # lista TIMs validos
  python tools/menu_extract.py dump    <arq.BIN> <outdir>  # extrai PNGs de 1 BIN
  python tools/menu_extract.py all     <outdir>            # todos os BIN de menu
"""
import os, sys, struct, glob
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tim2png import write_png, bgr555

BIN_DIR = os.path.join("extracted", "ntsc-u", "CD_DATA", "BIN")
ETC_DIR = os.path.join("extracted", "ntsc-u", "CD_DATA", "ETC")

# Os overlays de menu/tela (o resto de CD_DATA/BIN sao salas R###/overlays de logica)
MENU_BINS = [
    "TITLE", "JILL_SEL", "OPTION", "MEM_CARD", "RESULT", "SELECT", "WARNING",
    "GEARBOX", "MUSICBOX", "OPENING", "ENDING", "EPILOG", "STAFF_R", "PC_SYS",
    "DIEDEMO", "LTSOUT", "R214_OL",
]


def u16(b, o): return b[o] | (b[o + 1] << 8)
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


# ---------------------------------------------------------------------------
# Validador/decoder de TIM (suporta multiplas CLUTs)
# ---------------------------------------------------------------------------
def parse_tim(b, off):
    """Valida e le a estrutura TIM em `off`. Retorna dict ou None.
    Campos: bpp, has_clut, cluts(list de list-de-(r,g,b)), iw, ih (pixels),
            vram_x, vram_y, pix (bytes), end (offset apos o TIM)."""
    if off + 8 > len(b):
        return None
    if b[off] != 0x10 or b[off + 1] or b[off + 2] or b[off + 3]:
        return None
    flag = b[off + 4]
    if b[off + 5] or b[off + 6] or b[off + 7]:
        return None
    bpp = flag & 3
    has_clut = (flag >> 3) & 1
    # flag so pode ter bits 0,1 (bpp) e bit 3 (clut); demais reservados=0
    if flag & ~0x0B:
        return None
    if bpp == 3:            # 24bpp: raro em menu, ignora
        return None
    pos = off + 8
    cluts = []
    cw = ch = 0
    if has_clut:
        blen = u32(b, pos)
        cw = u16(b, pos + 8)      # cores por paleta
        ch = u16(b, pos + 10)     # numero de paletas
        if cw == 0 or ch == 0 or cw > 256 or ch > 512:
            return None
        if blen != 12 + cw * ch * 2:
            return None
        if pos + blen > len(b):
            return None
        p = pos + 12
        for pal in range(ch):
            base = p + pal * cw * 2
            cluts.append([bgr555(u16(b, base + 2 * i)) for i in range(cw)])
        pos += blen
    else:
        if bpp in (0, 1):
            return None            # paletado sem CLUT: nao renderizavel sozinho
    if pos + 12 > len(b):
        return None
    blen = u32(b, pos)
    vx = u16(b, pos + 4); vy = u16(b, pos + 6)
    iw = u16(b, pos + 8); ih = u16(b, pos + 10)   # iw em unidades de 16 bits
    if iw == 0 or ih == 0 or iw > 1024 or ih > 1024:
        return None
    if blen != 12 + iw * ih * 2:
        return None
    if pos + blen > len(b):
        return None
    pix = b[pos + 12: pos + blen]
    # largura em pixels
    if bpp == 0:   w = iw * 4
    elif bpp == 1: w = iw * 2
    else:          w = iw
    return dict(bpp=bpp, has_clut=has_clut, cluts=cluts, npal=ch, ncol=cw,
                w=w, h=ih, iw=iw, vram_x=vx, vram_y=vy, pix=pix,
                start=off, end=pos + blen)


def render_tim(t, pal=0):
    """Renderiza o TIM (CLUT `pal`) em bytes RGB w*h*3."""
    bpp, pix, w, h = t["bpp"], t["pix"], t["w"], t["h"]
    out = bytearray(w * h * 3)
    if bpp == 2:
        for i in range(w * h):
            r, g, b = bgr555(u16(pix, 2 * i))
            out[i * 3:i * 3 + 3] = bytes((r, g, b))
        return out
    clut = t["cluts"][pal] if t["cluts"] else []
    if bpp == 0:
        for i in range(w * h):
            byte = pix[i >> 1]
            idx = (byte & 0x0F) if (i & 1) == 0 else (byte >> 4)
            r, g, b = clut[idx] if idx < len(clut) else (0, 0, 0)
            out[i * 3:i * 3 + 3] = bytes((r, g, b))
    else:  # bpp==1
        for i in range(w * h):
            idx = pix[i]
            r, g, b = clut[idx] if idx < len(clut) else (0, 0, 0)
            out[i * 3:i * 3 + 3] = bytes((r, g, b))
    return out


def scan_tims(b):
    """Varre o BIN e devolve a lista de TIMs validos (nao sobrepostos)."""
    out = []
    i = 0
    n = len(b)
    while i < n - 8:
        if b[i] == 0x10 and b[i + 1] == 0 and b[i + 2] == 0 and b[i + 3] == 0:
            t = parse_tim(b, i)
            if t:
                out.append(t)
                i = t["end"]
                continue
        i += 1
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def cmd_scan(path):
    b = open(path, "rb").read()
    tims = scan_tims(b)
    print("%s  (%d bytes)  ->  %d TIM(s)" % (os.path.basename(path), len(b), len(tims)))
    for k, t in enumerate(tims):
        print("  [%2d] off=0x%05x  %4dx%-4d %dbpp  npal=%d ncol=%d  vram=(%d,%d)"
              % (k, t["start"], t["w"], t["h"], (4, 8, 16)[t["bpp"]],
                 t["npal"], t["ncol"], t["vram_x"], t["vram_y"]))


def dump_bin(path, outdir):
    b = open(path, "rb").read()
    tims = scan_tims(b)
    name = os.path.splitext(os.path.basename(path))[0]
    sub = os.path.join(outdir, name)
    os.makedirs(sub, exist_ok=True)
    made = []
    for k, t in enumerate(tims):
        npal = max(1, t["npal"] if t["has_clut"] else 1)
        # p/ paletado: renderiza ate 4 paletas (estados/idiomas); 16bpp: 1
        pals = range(min(npal, 4)) if t["bpp"] in (0, 1) else [0]
        for p in pals:
            rgb = render_tim(t, p)
            suffix = "" if len(list(pals)) == 1 else "_pal%d" % p
            fn = "%s_%02d_%dx%d%s.png" % (name, k, t["w"], t["h"], suffix)
            dest = os.path.join(sub, fn)
            write_png(dest, t["w"], t["h"], rgb)
            made.append(dest)
    return tims, made


def cmd_dump(path, outdir):
    tims, made = dump_bin(path, outdir)
    for m in made:
        print("  ->", os.path.relpath(m))
    print("%d TIM(s), %d PNG(s)" % (len(tims), len(made)))


def cmd_all(outdir):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    total_t = total_p = 0
    summary = []
    for name in MENU_BINS:
        path = os.path.join(root, BIN_DIR, name + ".BIN")
        if not os.path.exists(path):
            print("  (ausente) %s" % name); continue
        tims, made = dump_bin(path, outdir)
        total_t += len(tims); total_p += len(made)
        summary.append((name, len(tims), len(made),
                        ["%dx%d" % (t["w"], t["h"]) for t in tims]))
        print("  %-12s %2d TIM  %2d PNG" % (name, len(tims), len(made)))
    print("\nTOTAL: %d TIM(s) -> %d PNG(s) em %s" % (total_t, total_p, outdir))
    return summary


# ---------------------------------------------------------------------------
# Catalogo de TELAS: overlay BIN -> tela -> assets graficos (ETC), NTSC-U.
# A ligacao vem das STRINGS de codigo de cada overlay (rotulos dos arquivos que
# o overlay carrega p/ a VRAM). Assets `*U`/sem sufixo = versao NTSC-U/EN.
# ---------------------------------------------------------------------------
ETC = os.path.join("extracted", "ntsc-u", "CD_DATA", "ETC")

MENU_CATALOG = [
    # (overlay, tela, [assets ETC], nota)
    ("TITLE",    "01_title",       ["TITLEU.DAT", "CAPCOM.TIM"],
     "Tela de titulo + logo Capcom. Overlay ref.: TITLE_DAT, Capcom.tim, Pdemo, OMAKE/OPTION BGM."),
    ("JILL_SEL", "02_jill_select", ["JILL_BGU.TIM", "JILL_OBU.TIM"],
     "Selecao/apresentacao da Jill (inicio). Overlay ref.: 'Jill BG', 'Jill', WEP DATA."),
    ("SELECT",   "03_game_select", ["SELE_BGU.TIM", "SELE_OBU.TIM"],
     "Selecao de jogo/dificuldade. Overlay ref.: 'Select BG', 'Select', WEP DATA."),
    ("OPTION",   "04_option",      ["OPTIONU.DAT", "CORE00.TIM"],
     "Menu de Opcoes (som/gamepad/cor). Overlay ref.: Option.dat, CORE00_TIM, PaddD/PaddN/Color.tim."),
    ("MEM_CARD", "05_memory_card", ["CHECKJ.TIM"],
     "Cartao de memoria (save/load). Overlay ref.: 'MEMORY CARD BG', codigo de save 'BASLUS-00923'. "
     "O painel de slots do cartao e desenhado pelo proprio overlay (sem TIM dedicado em ETC). "
     "CHECKJ.TIM incluido aqui e, na verdade, a tela-TUTORIAL 'como examinar objetos' (JP: "
     "armario/mesa/prateleira/corredor) usada no guia inicial -- classificar melhor futuramente."),
    ("RESULT",   "06_result",      ["RES0_BGU.TIM", "RES2_BGU.TIM", "RES3_BGU.TIM",
                                    "RES4_BGU.TIM", "RES5_BGU.TIM", "RES0_OBU.TIM", "OMBG_U.DAT"],
     "Tela de RESULTADO/estatisticas (tempo, saves, personagem). Overlay ref.: 'RESULT BG', "
     "'OMBG.TIM', CARLOS/NICHOLAI/MIKHAIL, EXIT, Time."),
    ("WARNING",  "07_warning",     ["WARNU.TIM", "WARNINGT.TIM", "WARNJ.TIM"],
     "Aviso legal de abertura (SOFTWARE TERMINATED / CONSOLE MAY HAVE BEEN MODIFIED)."),
    ("DIEDEMO",  "08_game_over",   ["DIEDEMO.TIM", "CONTINUE.TIM"],
     "Game Over ('YOU DIED') + tela de Continue. Overlay ref.: DIEDEMO.TIM."),
    ("STAFF_R",  "09_staff_roll",  ["STR_BG.DAT", "STAFF_U.DAT"],
     "Rolagem de creditos/staff. Overlay ref.: STR_BG_DAT, STAFF_U_DAT."),
    ("OPENING",  "10_opening",     ["OPENING0.DAT", "OPENING1.DAT"],
     "Abertura (paineis do prologo). Overlay ref.: OPENING0_DAT, OPENING1_DAT."),
    ("EPILOG",   "11_epilogue",    ["EPIS_U.DAT"],
     "Epilogos (slides de encerramento por personagem). Overlay ref.: EPIS.TIM, OMBG.TIM."),
    ("PC_SYS",   "12_pc_terminal", [],
     "Terminal de PC no jogo (Umbrella Security System). Overlay so-texto: renderiza strings "
     "('NOTICE TO STARS PERSONNEL', senhas) sobre fonte; sem BG proprio em ETC."),
    ("GEARBOX",  "13_gearbox",     [],
     "Caixa de extras/bonus ('GEAR'). Overlay so-codigo, sem asset grafico dedicado em ETC."),
    ("MUSICBOX", "14_musicbox",    [],
     "Sound test / jukebox (extra). Overlay so-codigo, sem asset grafico dedicado em ETC."),
    ("ENDING",   "15_ending",      [],
     "Ending (codigo; usa END0.CPT/END1.CPT + STR MDEC). Sem TIM dedicado em ETC."),
    ("LTSOUT",   "16_live_select", [],
     "UI de 'Live Selection' (decisao em cutscene). Overlay so-codigo; texto via fonte."),
    ("R214_OL",  "17_room214_ol",  [],
     "Overlay especifico da sala 214 (nao e menu de sistema); listado por estar em BIN/."),
]

# STMAIN/STMOJI/TEX/FILEI/RADAR/FONTST* pertencem as unidades inventory/hd_ui.


def cmd_menu(outdir):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    catalog = {"screens": []}
    tot_scr = tot_tim = tot_png = 0
    scr_with_gfx = 0
    for overlay, screen, assets, note in MENU_CATALOG:
        tot_scr += 1
        sub = os.path.join(outdir, screen)
        entry = {"overlay": overlay + ".BIN", "screen": screen, "note": note,
                 "assets": [], "pngs": []}
        got_any = False
        for asset in assets:
            path = os.path.join(root, ETC, asset)
            if not os.path.exists(path):
                entry["assets"].append({"file": asset, "status": "AUSENTE"})
                continue
            b = open(path, "rb").read()
            tims = scan_tims(b)
            if not tims:
                entry["assets"].append({"file": asset, "status": "sem TIM"})
                continue
            os.makedirs(sub, exist_ok=True)
            aname = os.path.splitext(asset)[0]
            pnginfo = []
            for k, t in enumerate(tims):
                pals = range(min(t["npal"] if t["has_clut"] else 1, 4)) \
                    if t["bpp"] in (0, 1) else [0]
                pals = list(pals) or [0]
                for p in pals:
                    rgb = render_tim(t, p)
                    sfx = "" if len(pals) == 1 else "_pal%d" % p
                    fn = "%s_%02d_%dx%d%s.png" % (aname, k, t["w"], t["h"], sfx)
                    write_png(os.path.join(sub, fn), t["w"], t["h"], rgb)
                    pnginfo.append(fn)
                    tot_png += 1
            tot_tim += len(tims)
            got_any = True
            entry["assets"].append({"file": asset, "status": "OK",
                                    "n_tim": len(tims), "pngs": pnginfo,
                                    "sizes": ["%dx%d/%dbpp" % (t["w"], t["h"], (4, 8, 16)[t["bpp"]]) for t in tims]})
            entry["pngs"] += pnginfo
        if got_any:
            scr_with_gfx += 1
        catalog["screens"].append(entry)
        print("  %-16s -> %-16s %s" % (overlay, screen,
              "%d PNG" % len(entry["pngs"]) if entry["pngs"] else "(sem asset grafico)"))
    os.makedirs(outdir, exist_ok=True)
    import json
    jp = os.path.join(outdir, "catalog.json")
    catalog["summary"] = {"screens": tot_scr, "screens_com_grafico": scr_with_gfx,
                          "tims": tot_tim, "pngs": tot_png}
    json.dump(catalog, open(jp, "w"), indent=1, ensure_ascii=False)
    print("\nTelas=%d (com grafico=%d)  TIMs=%d  PNGs=%d\n-> %s"
          % (tot_scr, scr_with_gfx, tot_tim, tot_png, jp))
    return catalog


# ---------------------------------------------------------------------------
# (bonus) Casamento HD: telas full-screen (320x240) <-> hires/ do GOG (bgd/slide).
# O hires e nomeado por CRC-32 do bloco BGRA (ver docs/formatos/hd_ui.md) e NAO
# e reproduzivel estaticamente; telas cheias tambem sao tiladas. Aqui casamos por
# CONTEUDO (NCC em thumbnail cinza) contra os HD 1280x960 (=4x de 320x240).
# Requer Pillow. SOMENTE LEITURA do GOG; copia o candidato p/ <tela>/hd/.
# ---------------------------------------------------------------------------
GOG_HIRES = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"


def _thumb_gray(im, tw=64, th=48):
    from PIL import Image
    im = im.convert("RGBA")
    bg = Image.new("RGBA", im.size, (0, 0, 0, 255))
    im = Image.alpha_composite(bg, im).convert("L").resize((tw, th), Image.BILINEAR)
    px = list(im.getdata())
    n = len(px); mean = sum(px) / n
    dev = [p - mean for p in px]
    ss = sum(d * d for d in dev) ** 0.5 or 1.0
    return [d / ss for d in dev]


def _ncc(a, b):
    return sum(x * y for x, y in zip(a, b))


def cmd_hdmatch(outdir, thr=0.55):
    from PIL import Image
    import glob, shutil
    # 1) alvos: PNGs full-screen 320x240 ja extraidos
    targets = []
    for scr in sorted(os.listdir(outdir)):
        d = os.path.join(outdir, scr)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if fn.endswith("_320x240.png"):
                with Image.open(os.path.join(d, fn)) as im:
                    targets.append((scr, fn, _thumb_gray(im)))
    print("alvos full-screen:", len(targets))
    # 2) candidatos HD 1280x960 (bgd + slide)
    cands = []
    for cat in ("bgd", "slide"):
        for f in glob.glob(os.path.join(GOG_HIRES, cat, "*.webp")):
            try:
                with Image.open(f) as im:
                    if im.size != (1280, 960):
                        continue
                    cands.append((cat, f, _thumb_gray(im)))
            except Exception:
                continue
    print("candidatos HD 1280x960:", len(cands))
    # 3) melhor NCC por alvo
    results = []
    for scr, fn, tv in targets:
        best = (-2.0, None, None)
        for cat, f, cv in cands:
            s = _ncc(tv, cv)
            if s > best[0]:
                best = (s, cat, f)
        results.append((scr, fn, best))
        tag = "OK " if best[0] >= thr else "   "
        print("  %s%-14s %-28s ncc=%.3f  %s/%s"
              % (tag, scr, fn, best[0], best[1], os.path.basename(best[2]) if best[2] else "-"))
    # 4) copia os que passam do threshold
    ncopied = 0
    for scr, fn, (s, cat, f) in results:
        if s >= thr and f:
            hd = os.path.join(outdir, scr, "hd")
            os.makedirs(hd, exist_ok=True)
            dst = os.path.join(hd, "%s__%s_%s" % (os.path.splitext(fn)[0], cat, os.path.basename(f)))
            shutil.copy2(f, dst)
            ncopied += 1
    print("copiados %d HD (ncc>=%.2f) p/ <tela>/hd/" % (ncopied, thr))
    return results


# ===========================================================================
# LAYOUT INTERATIVO — desmontagem MIPS dos overlays p/ achar as COORDENADAS de
# blit dos sprites de cada tela (ver docs/decomp/notes/menus.md secao 8).
#
# Os overlays de menu sao codigo MIPS R3000 do PS1 (nao os graficos). Cada tela
# desenha seus sprites chamando um "helper de blit" local (uma funcao propria do
# overlay, endereco 0x801Cxxxx ou 0x8019xxxx) com a POSICAO em (a0=x, a1=y) e um
# ponteiro de rotulo/atributo em a2. Rastreando as constantes carregadas nos
# registradores ate cada `jal`, recuperamos a lista (x,y,label) — o LAYOUT real.
#
# Funcoes de UI COMPARTILHADAS no EXE (identificadas por frequencia entre telas):
#   0x80078930  desenha STRING de texto (fonte)      — telas de texto (PC_SYS, MUSICBOX)
#   0x800746c0  desenha SPRITE/primitiva na OT        — quase todas as telas
#   0x800788dc  helper de texto/medida               — telas de texto
#   0x8001b484  SPAWN de entidade (ver exe_ai.md)     — LTSOUT / R214_OL (nao-menu)
# ===========================================================================
from collections import defaultdict


def _s16(v):
    return v - 0x10000 if v & 0x8000 else v


def mips_scan_calls(d):
    """Disassembler MIPS-I minimo + rastreador linear de CONSTANTES em registrador.
    Retorna {func_addr: [(file_off, (a0,a1,a2,a3)), ...]} — os args constantes (ou
    None se desconhecido) em cada `jal`. Cobre lui/ori/addiu/addi p/ montar imediatos
    (inclui `li` = lui+ori/addiu). Aproxima delay-slots por varredura linear."""
    reg = [None] * 32
    calls = defaultdict(list)
    n = len(d) & ~3
    for o in range(0, n, 4):
        w = u32(d, o)
        op = w >> 26
        rs = (w >> 21) & 31; rt = (w >> 16) & 31; rd = (w >> 11) & 31
        imm = w & 0xFFFF; tgt = w & 0x3FFFFFF
        if op == 0x0F:                              # lui
            reg[rt] = (imm << 16) & 0xFFFFFFFF
        elif op == 0x0D:                            # ori
            reg[rt] = (reg[rs] | imm) if reg[rs] is not None else None
        elif op in (0x09, 0x08):                    # addiu / addi
            if rs == 0:
                reg[rt] = _s16(imm) & 0xFFFFFFFF
            elif reg[rs] is not None:
                reg[rt] = (reg[rs] + _s16(imm)) & 0xFFFFFFFF
            else:
                reg[rt] = None
        elif op == 0x03:                            # jal
            calls[(tgt << 2) | 0x80000000].append((o, tuple(reg[4:8])))
        else:
            if op == 0x00:                          # R-type: invalida rd (menos jr/jalr)
                if (w & 0x3F) != 0x08 and rd != 0:
                    reg[rd] = None
            elif rt != 0:                           # demais I-type: invalida rt
                reg[rt] = None
        reg[0] = 0
    return calls


def detect_load_base(d):
    """Base de carga (RAM) do overlay por correlacao ponteiro<->inicio-de-string.
    Retorna (base_estimado, hits). Os overlays usam 2 slots: ~0x80184000/0x80194000
    (boot: WARNING/TITLE/DIEDEMO) e ~0x801c2000 (menus in-game)."""
    ptrs = []
    for o in range(0, len(d) - 3, 4):
        w = u32(d, o)
        if 0x80183000 <= w < 0x801d0000:
            ptrs.append(w)
    # inicios de string ASCII
    soffs = []
    i = 0; n = len(d)
    while i < n:
        j = i
        while j < n and 32 <= d[j] < 127:
            j += 1
        if j - i >= 3:
            soffs.append(i)
        i = j + 1 if j > i else i + 1
    c = defaultdict(int)
    for w in ptrs:
        for so in soffs:
            c[w - so] += 1
    if not c:
        return None, 0
    base, hits = max(c.items(), key=lambda kv: kv[1])
    return base, hits


def extract_ascii(d, base, minlen=4):
    """Strings ASCII (>=minlen) com endereco RAM (se base) e file offset."""
    out = []
    i = 0; n = len(d)
    while i < n:
        j = i
        while j < n and 32 <= d[j] < 127:
            j += 1
        if j - i >= minlen:
            ram = (base + i) if base else None
            out.append((i, ram, d[i:j].decode("latin1")))
        i = j + 1 if j > i else i + 1
    return out


# overlays com LAYOUT interativo desmontavel (telas de menu que desenham sprites)
LAYOUT_BINS = ["TITLE", "JILL_SEL", "SELECT", "OPTION", "MEM_CARD", "RESULT",
               "DIEDEMO", "PC_SYS", "MUSICBOX", "GEARBOX", "LTSOUT", "ENDING",
               "R214_OL"]

SHARED_UI = {0x80078930: "flag_test(a0=bitfield,a1=bit)", 0x800746c0: "draw_sprite(OT)",
             0x800788dc: "text_helper", 0x8001b484: "spawn_entity",
             0x80089114: "center/fullscreen(160,120)"}

# ---------------------------------------------------------------------------
# BASE DE CARGA (RAM) — PROVADA por alinhamento de ponteiros (ver menus.md 8.1).
# Todos os overlays de menu IN-GAME sao carregados no MESMO slot fixo 0x801c2000
# (um de cada vez); os de BOOT em 0x80194000. Prova: reconstruindo os imediatos
# lui+addiu de cada overlay e testando bases, SO 0x801c2000 (in-game) / 0x80194000
# (boot) fazem 100% dos ponteiros cairem em inicio-de-string ou palavra 4-alinhada
# (residuo "meio-de-dado" = 0; qualquer outra base gera ponteiros desalinhados).
# `detect_load_base` (correlacao) erra por poucos bytes nos overlays code-heavy
# (poucos ponteiros-palavra) — por isso fixamos aqui.
OVERLAY_BASE = {
    # boot slot ~0x80194000
    "TITLE": 0x80194000, "WARNING": 0x80194000, "DIEDEMO": 0x80194000,
    "ENDING": 0x80194000,
    # in-game slot 0x801c2000 (fixo; overlays trocados em runtime)
    "JILL_SEL": 0x801c2000, "SELECT": 0x801c2000, "OPTION": 0x801c2000,
    "MEM_CARD": 0x801c2000, "RESULT": 0x801c2000, "PC_SYS": 0x801c2000,
    "MUSICBOX": 0x801c2000, "GEARBOX": 0x801c2000, "LTSOUT": 0x801c2000,
    "R214_OL": 0x801c2000,
}

# Primitivas de desenho COMPARTILHADAS no EXE (assinaturas PROVADAS por desmontagem
# do EXE em 0x800746c0 [file 0x64ec0] e pelos sitios de chamada):
#   0x800746c0  draw_sprite/enqueue_prim(a0=sprite_id, a1=ptr_template16, a2->prim+0x1a,
#               a3->prim+0x18=camada/OT). PROVADO: copia a1[0..15]->prim+8..0x14 e EMPACOTA
#               o id de a0 em prim+0x1c(hword=id&0xff), prim+0x1f(byte=id>>8=PAGINA),
#               prim+0x1e(byte=id>>16); avanca o ponteiro do buffer *(0x800e10e4) em 32B.
#               Nos overlays de menu a1=0 SEMPRE (sitios SELECT 0x1240/0x281c etc.): a
#               geometria (x,y,u,v,w,h) NAO vem do overlay — e RESOLVIDA depois (ver
#               SPRITE_PIPELINE). O que o overlay codifica = o sprite_id (pagina+indice).
#   0x80074770  resolve_sprite(a0=prim): le prim+0x1f(page)/+0x1c(index), indexa o
#               registro 0x800e0610 [page*4 -> tabela por-pagina; entrada 4B {b0,b1,
#               b2:&0x1f=tile-span/&0x80=flag, b3:anim}] e chama o compositor.
#   0x800749a0  compose_geom(a0=prim, a2=descritor): MONTA a primitiva GPU final (u,v,w,h)
#               encadeando descritor -> struct clut/tpage (0x800e0610+fp*8, +0x14->+0xc) ->
#               tabela VRAM por-tile (32B/entrada, byte6=v). u,v COMPUTADOS em runtime a
#               partir do upload VRAM do atlas *_OBU + grade de tiles (NAO ha rect estatico).
#   0x80089114  blit/env de tela — em SELECT/JILL_SEL recebe (a0=cx=160, a1=cy=120,
#               a2=src img, a3=fb) = BG FULL-SCREEN centralizado. (Em DIEDEMO recebe
#               ptr de primitiva -> utilitario generico; papel varia.)
#   0x80078930  flag_test(a0=ptr_bitfield, a1=bit) -> (a0[bit>>5] & (0x80000000>>(bit&31))).
#               CORRECAO: NAO e draw_string (disasm: srl a1,5; ...; and v0). As chamadas
#               antes rotuladas "draw_string" no draw_seq sao TESTES DE FLAG condicionais
#               (a1=indice de bit, nao string; a3=lixo, nao cor). O desenho de glifos usa
#               os helpers de fonte (0x800788dc etc.).
DRAW_FNS = {0x800746c0: "draw_sprite", 0x80089114: "blit_bg", 0x80078930: "flag_test"}

# ATLAS por tela INDEXADA (o *_OBU/TIM que o draw_seq referencia). Dimensoes/bpp/npal
# LIDAS do header TIM (byte-a-byte via parse_tim). VRAM(x,y) no header = 0,0 (placeholder;
# o destino real e setado no upload pelo loader). O atlas e uma imagem unica (grade de
# sprites); o recorte por sprite_id e resolvido em runtime (SPRITE_PIPELINE).
ATLAS_MAP = {
    "SELECT":   ["SELE_OBU.TIM"],
    "JILL_SEL": ["JILL_OBU.TIM"],
    "RESULT":   ["RES0_OBU.TIM"],
    "DIEDEMO":  ["DIEDEMO.TIM", "CONTINUE.TIM"],
}

# Pipeline de sprite (enderecos PROVADOS no SLUS_009.23). Doc-only, gravado em layout.json.
SPRITE_PIPELINE = {
    "registry_base": "0x800e0610",
    "registry_layout": {
        "+0x000": "array de PONTEIROS por-pagina (page = sprite_id>>8); page*4 -> tabela",
        "per_page_entry": "4B {b0, b1, b2:&0x1f=tile-span/&0x80=flag, b3:anim} por index (=sprite_id&0xff)",
        "+0x4c0": "array de tile-primitivas GPU de 32B (montadas no load)",
        "+0xad4": "ponteiro CORRENTE do buffer de primitivas/OT (draw_sprite avanca +32B)",
        "+0xb5c": "estado de animacao por-tile",
    },
    "enqueue": "0x800746c0 draw_sprite(a0=sprite_id, a1=0): empaca id em prim+0x1c/+0x1e/+0x1f",
    "resolve": "0x80074770 resolve_sprite(a0=prim): id -> descritor via 0x800e0610",
    "compose": "0x800749a0 compose_geom(a0=prim,a2=descritor): u,v,w,h de VRAM+grade de tiles",
    "static_source": "os PIXELS e as DIMENSOES do atlas estao no *_OBU.TIM (ATLAS_MAP, header "
                      "byte-a-byte); o recorte (u,v,w,h) por sprite_id NAO e uma tabela estatica "
                      "flat: e COMPOSTO em runtime por 0x800749a0 (atlas-VRAM + descritor id->tile).",
}


def build_atlas_descriptor(root):
    """Le o header TIM de cada atlas das telas indexadas (dims/bpp/npal). PROVA estatica
    do que o draw_seq indexa. Retorna {tela: {atlas: [ {file,w,h,bpp,npal,ncol,...} ]}}."""
    out = {}
    for screen, files in ATLAS_MAP.items():
        atlas = []
        for fn in files:
            p = os.path.join(root, ETC_DIR, fn)
            if not os.path.exists(p):
                atlas.append({"file": fn, "error": "missing"})
                continue
            b = open(p, "rb").read()
            t = parse_tim(b, 0)
            if not t:
                atlas.append({"file": fn, "error": "nao-TIM"})
                continue
            bppmap = {0: "4bpp", 1: "8bpp", 2: "16bpp"}
            atlas.append({
                "file": fn, "bytes": len(b),
                "bpp": bppmap.get(t["bpp"], "?"),
                "img_w": t["w"], "img_h": t["h"],
                "has_clut": bool(t["has_clut"]), "npal": t["npal"], "ncol": t["ncol"],
                "vram_xy_header": [t["vram_x"], t["vram_y"]],
                "nota": "VRAM(x,y) do header = placeholder; destino real setado no upload.",
            })
        out[screen] = {"atlas": atlas}
    return out


def _s16m(v):
    return v - 0x10000 if (v is not None and v & 0x8000) else v


def mips_trace_draws(d, base):
    """Rastreador de CONSTANTES + CARGAS DE MEMORIA ESTATICA (segue a tabela).
    Alem de lui/ori/addiu/addi/sll/move, resolve lh/lhu/lb/lbu/lw quando o reg-base
    ja contem um ponteiro CONHECIDO para dentro do proprio overlay (le os bytes de
    `d`). Isso permite SEGUIR a tabela indexada de sprites/coords quando o indice e
    constante. Retorna a lista ordenada de chamadas as primitivas de DRAW_FNS com
    (a0..a3) resolvidos (None = desconhecido/runtime)."""
    N = len(d)
    reg = [None] * 32

    def rd(addr, size, signed):
        if addr is None:
            return None
        off = addr - base
        if off < 0 or off + size > N:
            return None
        if size == 2:
            v = u16(d, off); return _s16m(v) if signed else v
        if size == 1:
            v = d[off]; return (v - 256 if (signed and v & 0x80) else v)
        if size == 4:
            return u32(d, off)
        return None

    seq = []
    for o in range(0, N & ~3, 4):
        w = u32(d, o); op = w >> 26; rs = (w >> 21) & 31; rt = (w >> 16) & 31
        rd_ = (w >> 11) & 31; sa = (w >> 6) & 31; fn = w & 0x3F
        imm = w & 0xFFFF; si = _s16(imm); tgt = w & 0x3FFFFFF
        if op == 0x0F:
            reg[rt] = (imm << 16) & 0xFFFFFFFF
        elif op == 0x0D:
            reg[rt] = (reg[rs] | imm) if reg[rs] is not None else None
        elif op in (0x09, 0x08):
            if rs == 0:
                reg[rt] = si & 0xFFFFFFFF
            elif reg[rs] is not None:
                reg[rt] = (reg[rs] + si) & 0xFFFFFFFF
            else:
                reg[rt] = None
        elif op == 0x21:
            reg[rt] = rd(reg[rs], 2, True)
        elif op == 0x25:
            reg[rt] = rd(reg[rs], 2, False)
        elif op == 0x20:
            reg[rt] = rd(reg[rs], 1, True)
        elif op == 0x24:
            reg[rt] = rd(reg[rs], 1, False)
        elif op == 0x23:
            reg[rt] = rd(reg[rs], 4, False)
        elif op == 0x00:
            if fn == 0x00:
                reg[rd_] = ((reg[rt] << sa) & 0xFFFFFFFF) if reg[rt] is not None else None
            elif fn == 0x02:
                reg[rd_] = (reg[rt] >> sa) if reg[rt] is not None else None
            elif fn == 0x21 and rt == 0:
                reg[rd_] = reg[rs]
            elif fn == 0x21 and rs == 0:
                reg[rd_] = reg[rt]
            elif fn != 0x08 and rd_ != 0:
                reg[rd_] = None
        elif op == 0x03:
            fa = (tgt << 2) | 0x80000000
            if fa in DRAW_FNS:
                seq.append((o, fa, tuple(reg[4:8])))
        else:
            if rt != 0:
                reg[rt] = None
        reg[0] = 0
    return seq


def ascii_groups(d, base, minlen=3, gap=1):
    """Agrupa runs contiguos de strings ASCII terminadas em NUL (tabelas de texto,
    ex.: lista de loadout do SELECT). Retorna [{start,ram,items:[str,...]}]."""
    strs = []
    i = 0; n = len(d)
    while i < n:
        j = i
        while j < n and 32 <= d[j] < 127:
            j += 1
        if j - i >= minlen:
            strs.append((i, d[i:j].decode("latin1")))
        i = j + 1 if j > i else i + 1
    groups = []
    cur = None
    last_end = -99
    for (off, s) in strs:
        if cur and off - last_end <= gap + 1:
            cur["items"].append(s)
        else:
            cur = {"start": "0x%05x" % off,
                   "ram": ("0x%08x" % (base + off)) if base else None,
                   "items": [s]}
            groups.append(cur)
        last_end = off + len(s)
    return [g for g in groups if len(g["items"]) >= 3]


def analyze_overlay(d, base_override=None):
    """Extrai o LAYOUT de um overlay: base, helper de blit dominante e a lista
    ordenada de (x, y, label_ptr) das chamadas + perfil de chamadas ao EXE."""
    base, hits = detect_load_base(d)
    if base_override is not None:
        base = base_override            # base PROVADA (OVERLAY_BASE) sobrepoe a estimada
    calls = mips_scan_calls(d)
    # helper de blit local dominante = funcao 0x801Cxxxx/0x8019xxxx mais chamada
    # com (a0,a1) em faixa de tela (0..340, 0..256)
    def in_screen(a):
        return (a[0] is not None and a[1] is not None
                and 0 <= a[0] <= 340 and 0 <= a[1] <= 256 and (a[0] or a[1]))
    localfns = {}
    for addr, lst in calls.items():
        if 0x801c0000 <= addr < 0x801d0000 or 0x80180000 <= addr < 0x801a0000:
            ncoord = sum(1 for _o, a in lst if in_screen(a))
            if ncoord:
                localfns[addr] = ncoord
    helper = max(localfns, key=localfns.get) if localfns else None
    sprites = []
    if helper is not None:
        for o, a in calls[helper]:
            sprites.append(dict(off=o, x=None if a[0] is None else _s16(a[0] & 0xFFFF),
                                y=None if a[1] is None else _s16(a[1] & 0xFFFF),
                                label_ptr=(("0x%08x" % a[2]) if a[2] is not None else None)))
    # perfil de chamadas ao EXE (funcoes de UI/logica compartilhadas)
    exe = sorted(((a, len(l)) for a, l in calls.items() if 0x80010000 <= a < 0x80100000),
                 key=lambda x: -x[1])
    exe_prof = [dict(fn="0x%08x" % a, n=n, role=SHARED_UI.get(a, ""))
                for a, n in exe[:12]]
    # SEQUENCIA DE DESENHO (segue a tabela indexada): draw_sprite/blit_bg/draw_string
    # com args resolvidos (inclui cargas de memoria estatica). Para as telas que
    # posicionam por TABELA INDEXADA (SELECT/JILL_SEL/RESULT/DIEDEMO), esta e a
    # forma que o overlay codifica estaticamente o layout: sequencia de sprite-ids
    # (a0) + camada/OT (a3) + o BG full-screen (blit_bg cx,cy) + as strings.
    draw_seq = []
    if base:
        for o, fa, a in mips_trace_draws(d, base):
            role = DRAW_FNS[fa]
            e = {"off": "0x%05x" % o, "fn": "0x%08x" % fa, "role": role}
            if role == "draw_sprite":
                sid = a[0]
                e["sprite_id"] = None if sid is None else sid
                if sid is not None:
                    # PROVADO (resolve_sprite 0x80074770): page = prim+0x1f = id>>8;
                    # index = prim+0x1c = id&0xff. O overlay codifica so isto (a1=0).
                    e["atlas_page"] = (sid >> 8) & 0xff
                    e["atlas_index"] = sid & 0xff
                e["layer"] = None if a[3] is None else a[3]
                e["geom"] = "runtime(compose_geom 0x800749a0)"
            elif role == "flag_test":
                # 0x80078930: teste de flag/bit condicional (NAO draw_string). a0=bitfield,
                # a1=indice de bit. Antes rotulado draw_string por engano.
                e["bit"] = None if a[1] is None else (a[1] if a[1] < 0x8000 else "0x%08x" % a[1])
                e["bitfield_ptr"] = None if a[0] is None else "0x%08x" % a[0]
            elif role == "blit_bg":
                # cx/cy sao coords quando <0x8000 (SELECT/JILL_SEL: 160,120);
                # quando >=0x8000 sao PONTEIROS (uso generico do helper, ex. DIEDEMO)
                def _cc(v):
                    if v is None: return None
                    return v if v < 0x8000 else "0x%08x" % v
                e["cx"], e["cy"] = _cc(a[0]), _cc(a[1])
                e["src"] = None if a[2] is None else "0x%08x" % a[2]
            elif role == "draw_string":
                e["str_ptr"] = None if a[1] is None else (
                    "0x%08x" % a[1] if a[1] >= 0x8000 else a[1])
                e["color"] = None if a[3] is None else "0x%08x" % a[3]
            draw_seq.append(e)
    # TABELA DE LOADOUT (SELECT): entradas ASCII (nome de personagem terminado em ']'
    # e itens "[NNN<nome>]") separadas por ~20 bytes de ponteiro/atributo — nao sao um
    # run contiguo; capturamos pelo PADRAO de colchetes. Prova: bytes ASCII literais no
    # overlay retail (SELECT.BIN @0x36e8+): 4 personagens x loadout (Mercenaries).
    def _looks_label(t):
        alpha = sum(c.isalpha() or c.isspace() for c in t)
        if len(t) >= 2 and t[0] == "[" and t[1].isdigit():   # "[NNN<nome>]" item
            return True
        return t.rstrip().endswith("]") and alpha >= 3        # "NOME]" personagem
    bl = [t for (o, r, t) in extract_ascii(d, base, 3) if _looks_label(t)]
    return dict(base=("0x%08x" % base) if base else None, base_hits=hits,
                base_proven=(base_override is not None),
                helper=("0x%08x" % helper) if helper else None,
                n_sprites=len([s for s in sprites if s["x"] is not None]),
                n_draw=len(draw_seq), draw_seq=draw_seq,
                text_tables=ascii_groups(d, base) if base else [],
                bracket_list=bl if len(bl) >= 4 else [],
                sprites=sprites, exe_calls=exe_prof)


def cmd_layout(outdir=None):
    """Desmonta cada overlay de menu e escreve o layout (coords de blit + perfil de
    chamadas) em <outdir>/layout.json. Imprime um resumo por tela."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = outdir or paths.assets("MENU")
    atlas_desc = build_atlas_descriptor(root)
    result = {
        "_sprite_pipeline": SPRITE_PIPELINE,
        "_atlas_indexed_screens": atlas_desc,
        "screens": {},
    }
    for name in LAYOUT_BINS:
        path = os.path.join(root, BIN_DIR, name + ".BIN")
        if not os.path.exists(path):
            continue
        d = open(path, "rb").read()
        info = analyze_overlay(d, OVERLAY_BASE.get(name))
        # strings ASCII (texto de tela — vale p/ PC_SYS) com endereco RAM
        base_val = int(info["base"], 16) if info["base"] else None
        info["strings"] = [dict(off="0x%05x" % o, ram=("0x%08x" % r) if r else None, text=t)
                           for (o, r, t) in extract_ascii(d, base_val, 4)]
        if name in atlas_desc:
            info["atlas"] = atlas_desc[name]["atlas"]
        result["screens"][name] = info
        print("  %-9s base=%s helper=%s sprites=%d draw=%d strings=%d"
              % (name, info["base"], info["helper"], info["n_sprites"],
                 info["n_draw"], len(info["strings"])))
    os.makedirs(outdir, exist_ok=True)
    import json
    jp = os.path.join(outdir, "layout.json")
    json.dump(result, open(jp, "w"), indent=1, ensure_ascii=False)
    print("-> %s" % jp)
    return result


def cmd_disasm(path):
    """Debug: lista as chamadas (jal) do overlay com args constantes rastreados."""
    d = open(path, "rb").read()
    calls = mips_scan_calls(d)
    for addr in sorted(calls, key=lambda a: -len(calls[a])):
        lst = calls[addr]
        sample = [tuple(None if x is None else _s16(x & 0xFFFF) if x < 0x10000 else "0x%x" % x
                        for x in a) for _o, a in lst[:4]]
        print("  jal 0x%08x  x%-3d %s %s" % (addr, len(lst),
              SHARED_UI.get(addr, ""), sample))


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); return 1
    if a[0] == "scan":   cmd_scan(a[1])
    elif a[0] == "dump": cmd_dump(a[1], a[2])
    elif a[0] == "all":  cmd_all(a[1])
    elif a[0] == "menu": cmd_menu(a[1] if len(a) > 1 else paths.assets("MENU"))
    elif a[0] == "hdmatch": cmd_hdmatch(a[1] if len(a) > 1 else paths.assets("MENU"))
    elif a[0] == "layout": cmd_layout(a[1] if len(a) > 1 else None)
    elif a[0] == "disasm": cmd_disasm(a[1])
    else:
        print("comando desconhecido:", a[0]); print(__doc__); return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
