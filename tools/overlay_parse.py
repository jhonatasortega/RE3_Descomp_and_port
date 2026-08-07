#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Loader + desassemblador dos OVERLAYS de menu/tela do RE3 PS1 (`CD_DATA/BIN/*.BIN`).

FORMATO PROVADO (NTSC-U, SLUS_009.23)
=====================================
Os 17 arquivos de `CD_DATA/BIN/*.BIN` sao *imagens de codigo MIPS R3000 ja linkadas
para um endereco fixo de RAM*. NAO existe cabecalho, NAO existe tabela de relocacao
e NAO existe compressao: o arquivo e copiado byte-a-byte para o endereco de destino,
ou seja `RAM[base + i] = arquivo[i]` para todo i.

    offset 0x00 .. tamanho-1   ->   base .. base+tamanho-1

Layout interno tipico (varia por overlay, nao e um header formal):

    +0x00  u32          constante pequena (0x36..0x45), uma por arquivo (16 dos 17;
                        WARNING.BIN nao tem). NINGUEM LE essa palavra - papel NAO
                        PROVADO. Nao use.
    +0x04  u32[N]       POOL DE TABELAS DE `switch` do compilador: ponteiros
                        ABSOLUTOS para LABELS DE CODIGO (nao sao funcoes - nenhuma
                        entrada e prologo). Consumidas por `jr $rX` depois de um
                        `sltiu` de limite; tabelas consecutivas sao separadas por
                        palavras 0x00000000. Em WARNING.BIN comeca em +0x00.
                        -> `dispatch()` devolve isso; `states()` acha o `jr`+bound.
    ...                 dados: strings ASCII de rotulo/nome de asset, format strings,
                        tabelas de glifo (u16 com prefixo 0x82/0x89), descritores,
                        e as TABELAS DE HANDLER por estado (ponteiros de FUNCAO de
                        verdade, geralmente perto do fim) -> `handlers()`.
    ...                 codigo MIPS. O ponto de entrada NAO e o inicio do arquivo:
                        e o campo `entry` do registro do overlay na tabela do EXE.

O laco de cada tela e:  `st = *(u8*)ctx; handlers[st](ctx); yield();` onde
`yield` = EXE `0x8003203c(a0=1)`.

ATENCAO: o loader le SETORES INTEIROS - escreve `ceil(size/2048)*2048` bytes em
`dest`, ou seja ate 2047 bytes ALEM do fim do arquivo.

TABELA DE OVERLAYS NO EXE  ->  `0x8009c944`, registros de 12 bytes:

    +0x00  u32  file_index   indice do arquivo na tabela global de arquivos do CD
                             (`0x800946a4`, stride 8 - ver `FILE_TABLE`)
    +0x04  u32  entry        endereco de entrada JA em RAM (dentro do overlay)
    +0x08  u32  *dest        PONTEIRO para a palavra que contem o endereco de destino
                             (`0x8001031c`, `0x80010320`, `0x80010324` ou `0x80010328`)

Quem carrega: `0x80031f50(a0=task, a1=ovl_id)` e `0x80031fc0(a0=ovl_id)` no EXE;
ambos fazem `rec = 0x8009c944 + ovl_id*12` e chamam
`cd_read_file(0x80012818)(a0=rec->file_index, a1=*rec->dest, a2=0, a3=<nao usado>)`.

Tres SLOTS de destino (provados: sao exatamente as palavras apontadas):
    `0x8001031c` -> **0x80194000**  (slot de boot: DIEDEMO, ENDING, TITLE)
    `0x80010320` -> **0x80184000**  (slot do WARNING)
    `0x80010324` -> **0x8011a000**  (slot de overlay de SALA, nao usado por BIN/*.BIN)
    `0x80010328` -> **0x801c2000**  (slot in-game: os outros 13 arquivos)

Uso como biblioteca (mesma interface de `exe_parse.Exe`):

    from overlay_parse import Overlay
    o = Overlay('extracted/ntsc-u/CD_DATA/BIN/PC_SYS.BIN')   # ou Overlay('PC_SYS')
    o.base            # 0x801c2000
    o.entry           # 0x801c2354
    o.disasm(0x801c2354, 60)
    o.dispatch()      # [(0, 0x801c24c4), ...]  tabela de switch do inicio
    o.states()        # [(jr_addr, n_estados, addr_var_estado), ...]
    o.handlers()      # [(jalr_addr, tabela, [ponteiros de funcao]), ...]
    o.call_args()     # [(sitio, alvo, {a0..a3 constantes}), ...]
    o.strings()       # [(vaddr, texto), ...]
    o.xrefs(0x801c24c4)
    o.exe_calls()     # {addr_exe: [sitios]}  - funcoes do EXE chamadas pelo overlay

CLI:

    python tools/overlay_parse.py PC_SYS --dispatch
    python tools/overlay_parse.py PC_SYS --strings
    python tools/overlay_parse.py PC_SYS --disasm 0x801c2354 60
    python tools/overlay_parse.py PC_SYS --calls
    python tools/overlay_parse.py PC_SYS --states
    python tools/overlay_parse.py TITLE  --handlers
    python tools/overlay_parse.py X      --filetable 200
    python tools/overlay_parse.py --all           # resolve a base dos 17 e confere

Ver `docs/decomp/notes/menu_overlays.md` para a prova completa.
"""
import os
import struct
import sys
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN_DIR = os.path.join(REPO, "extracted", "ntsc-u", "CD_DATA", "BIN")
EXE_PATH = os.path.join(REPO, "extracted", "ntsc-u", "SLUS_009.23")

# ---------------------------------------------------------------------------
# Dados lidos do EXE (SLUS_009.23). Cada numero abaixo foi copiado do binario;
# `--all` reconfere a base pelo metodo de votacao, sem usar esta tabela.
# ---------------------------------------------------------------------------

#: Palavras de destino apontadas pelos registros de overlay (EXE `0x8001031c`+)
DEST_SLOTS = {
    0x8001031C: 0x80194000,   # EXE 0x8001031c
    0x80010320: 0x80184000,   # EXE 0x80010320
    0x80010324: 0x8011A000,   # EXE 0x80010324 (overlay de sala)
    0x80010328: 0x801C2000,   # EXE 0x80010328
}

#: Tabela de overlays do EXE em `0x8009c944` (24 registros de 12 bytes; os 17
#: primeiros sao os `BIN/*.BIN`, os 7 seguintes sao overlays de sala em
#: `0x8011a000`). Aqui: ovl_id -> (nome, file_index, entry, dest_ptr, rec_addr)
OVERLAY_TABLE = {
    0x00: ("DIEDEMO",  0x00, 0x80194010, 0x8001031C, 0x8009C968),
    0x01: ("ENDING",   0x01, 0x80194004, 0x8001031C, 0x8009C9B0),
    0x02: ("EPILOG",   0x02, 0x801C204C, 0x80010328, 0x8009C9BC),
    0x03: ("GEARBOX",  0x03, 0x801C2008, 0x80010328, 0x8009CA04),
    0x04: ("JILL_SEL", 0x04, 0x801C2050, 0x80010328, 0x8009C998),
    0x05: ("LTSOUT",   0x05, 0x801C2018, 0x80010328, 0x8009C9E0),
    0x06: ("MEM_CARD", 0x06, 0x801C20AC, 0x80010328, 0x8009C95C),
    0x07: ("MUSICBOX", 0x07, 0x801C2030, 0x80010328, 0x8009C9F8),
    0x08: ("OPENING",  0x08, 0x801C2024, 0x80010328, 0x8009C980),
    0x09: ("OPTION",   0x09, 0x801C21B0, 0x80010328, 0x8009C974),
    0x0A: ("PC_SYS",   0x0A, 0x801C2354, 0x80010328, 0x8009C9D4),
    0x0B: ("R214_OL",  0x0B, 0x801C2020, 0x80010328, 0x8009C9EC),
    0x0C: ("RESULT",   0x0C, 0x801C21EC, 0x80010328, 0x8009C9A4),
    0x0D: ("SELECT",   0x0D, 0x801C2094, 0x80010328, 0x8009C98C),
    0x0E: ("STAFF_R",  0x0E, 0x801C206C, 0x80010328, 0x8009C9C8),
    0x0F: ("TITLE",    0x0F, 0x801940E8, 0x8001031C, 0x8009C944),
    0x10: ("WARNING",  0x10, 0x80185418, 0x80010320, 0x8009C950),
}

#: ovl_id == file_index para os 17 (a tabela global de arquivos do CD esta em
#: ordem alfabetica de diretorio, e `BIN/` e o primeiro diretorio).
NAME2ID = {v[0]: k for k, v in OVERLAY_TABLE.items()}

#: EXE: tabela global de arquivos do CD. Registro de 8 bytes:
#:   +0 u32 size (bytes) | +4 u16 lba_lo | +6 u8 lba_hi | +7 u8 flags(NAO DECODIFICADO)
#: LBA de 24 bits = lba_lo | lba_hi<<16 (lido em `cd_read_file` 0x800128d8..0x800128e8)
FILE_TABLE = 0x800946A4
FILE_TABLE_STRIDE = 8

#: `cd_read_file(a0=file_index, a1=dest, a2=mode, a3=<morto>)`
EXE_CD_READ_FILE = 0x80012818
#: `load_overlay_task(a0=task_slot, a1=ovl_id)` / `load_overlay_run(a0=ovl_id)`
EXE_LOAD_OVERLAY_TASK = 0x80031F50
EXE_LOAD_OVERLAY_RUN = 0x80031FC0

#: fim do segmento de codigo do EXE (acima disto e dado; usado so p/ heuristica)
EXE_CODE_END = 0x80097000
#: faixa em que qualquer slot de overlay pode cair
OVL_LO, OVL_HI = 0x80180000, 0x801E0000


def _s16(x):
    return struct.unpack("<h", struct.pack("<H", x & 0xFFFF))[0]


class Overlay(object):
    """Um `CD_DATA/BIN/*.BIN` mapeado no endereco de RAM em que o jogo o carrega.

    A base e descoberta sozinha (`resolve_base`) por votacao alvo-de-`jal` x
    inicio-de-funcao; `Overlay.base_votes` guarda o placar para auditoria.
    """

    def __init__(self, path, base=None):
        if not os.path.sep in path and not path.lower().endswith(".bin"):
            path = os.path.join(BIN_DIR, path.upper() + ".BIN")
        self.path = path
        self.name = os.path.basename(path).rsplit(".", 1)[0].upper()
        self.text = open(path, "rb").read()      # nome `text` p/ casar com Exe
        self.raw = self.text
        self.size = len(self.text)
        self.words = [struct.unpack_from("<I", self.text, i)[0]
                      for i in range(0, self.size & ~3, 4)]
        self.base_votes = []
        self.base = base if base is not None else self.resolve_base()
        self.vend = self.base + self.size
        self.tsize = self.size
        rec = OVERLAY_TABLE.get(NAME2ID.get(self.name, -1))
        self.ovl_id = NAME2ID.get(self.name)
        self.entry = rec[2] if rec else None
        self.file_index = rec[1] if rec else None

    # ---- descoberta da base ------------------------------------------------
    def _fn_starts(self):
        """Offsets que sao provavel INICIO de funcao.

        Dois sinais independentes:
          (a) `addiu sp, sp, -N`  (prologo de funcao nao-folha) -> 0x27bdXXXX, imm<0
          (b) offset logo depois de `jr $ra` + slot de atraso    -> fim da anterior
        """
        pro, bnd = set(), set()
        for i, w in enumerate(self.words):
            if (w >> 16) == 0x27BD and (w & 0x8000):
                pro.add(i * 4)
            if w == 0x03E00008:                     # jr $ra
                o = (i + 2) * 4
                if o < self.size:
                    bnd.add(o)
        return pro, bnd

    def _local_jal_targets(self):
        c = Counter()
        for w in self.words:
            if (w >> 26) == 3:                      # jal
                t = 0x80000000 | ((w & 0x3FFFFFF) << 2)
                if OVL_LO <= t < OVL_HI:
                    c[t] += 1
        return c

    def _ptr_score(self, base):
        """Quantas palavras do arquivo sao ponteiros COERENTES para esta base.

        Coerente = cai dentro de [base, base+tamanho), 4-alinhado, e o alvo e
        prologo de funcao OU inicio de string ASCII. Serve de desempate quando
        o overlay tem poucos `jal` locais (ex. MUSICBOX tem 1).
        """
        good = 0
        for w in self.words:
            if not (base <= w < base + self.size) or (w - base) & 3:
                continue
            o = w - base
            if o + 4 > self.size:
                continue
            iw = struct.unpack_from("<I", self.text, o)[0]
            prev = self.text[o - 1] if o else 0
            if ((iw >> 16) == 0x27BD and (iw & 0x8000)) or \
               (0x20 <= self.text[o] < 0x7F and prev == 0):
                good += 1
        return good

    def resolve_base(self):
        """Base = alvo_de_jal - offset_de_inicio_de_funcao, por votacao.

        Restricao dura: TODO alvo de `jal` local tem de cair dentro de
        [base, base+tamanho). Criterios, em ordem:
          1. maior numero de alvos de `jal` que caem exatamente num inicio de funcao;
          2. base multipla de 0x1000 - os 4 destinos possiveis lidos do EXE
             (`0x8001031c`..`0x80010328` = 0x80194000/0x80184000/0x8011a000/0x801c2000)
             sao todos alinhados a 4 KiB;
          3. `_ptr_score` (coerencia das palavras-ponteiro do arquivo).
        """
        pro, bnd = self._fn_starts()
        cands = pro | bnd
        jt = self._local_jal_targets()
        votes = Counter()
        for t in jt:
            for o in cands:
                b = t - o
                if OVL_LO <= b < OVL_HI and (b & 3) == 0:
                    votes[b] += 1
        ok = [(b, v) for b, v in votes.items()
              if all(0 <= t - b < self.size for t in jt)]
        if not ok:
            raise RuntimeError("nao consegui resolver a base de %s" % self.name)
        ok.sort(key=lambda x: (-x[1], -(x[0] % 0x1000 == 0),
                               -self._ptr_score(x[0]), x[0]))
        self.base_votes = [(b, v, len(jt), self._ptr_score(b)) for b, v in ok[:5]]
        return ok[0][0]

    # ---- mapeamento vaddr <-> offset (identico a exe_parse.Exe) -----------
    def off(self, vaddr):
        return vaddr - self.base

    def valid_vaddr(self, v):
        return self.base <= v < self.vend

    def u32(self, vaddr):
        o = self.off(vaddr)
        return struct.unpack("<I", self.text[o:o + 4])[0]

    def u16(self, vaddr):
        o = self.off(vaddr)
        return struct.unpack("<H", self.text[o:o + 2])[0]

    def s16(self, vaddr):
        o = self.off(vaddr)
        return struct.unpack("<h", self.text[o:o + 2])[0]

    def u8(self, vaddr):
        return self.text[self.off(vaddr)]

    def bytes_at(self, vaddr, n):
        o = self.off(vaddr)
        return self.text[o:o + n]

    # ---- disassembler ------------------------------------------------------
    def _md(self):
        import capstone
        md = capstone.Cs(capstone.CS_ARCH_MIPS,
                         capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
        md.detail = True
        return md

    def disasm(self, vaddr, count=40, show=True):
        md = self._md()
        o = self.off(vaddr)
        code = self.text[o:o + count * 4]
        out = []
        for insn in md.disasm(code, vaddr):
            out.append((insn.address, insn.mnemonic, insn.op_str, insn.bytes))
            if show:
                print("%08x  %-8s %s" % (insn.address, insn.mnemonic, insn.op_str))
            if len(out) >= count:
                break
        return out

    # ---- tabela de dispatch ------------------------------------------------
    def dispatch(self):
        """[(indice, endereco)] da tabela de ponteiros no inicio do arquivo.

        CUIDADO: apesar do nome, NAO e dispatch de funcoes - sao labels de
        codigo de `switch` (ver docstring do modulo). Para as tabelas de funcao
        por estado use `handlers()`.

        Comeca em +0x04 quando a palavra 0 nao e um ponteiro valido (16 dos 17
        arquivos), senao em +0x00 (WARNING.BIN). Para na primeira palavra que
        nao e NULL nem ponteiro para dentro do proprio overlay.
        Entradas NULL sao mantidas (buracos existem de verdade, ex. JILL_SEL[5]).
        """
        start = 0 if self.valid_vaddr(self.words[0]) else 4
        out = []
        i = start // 4
        while i < len(self.words):
            w = self.words[i]
            if w == 0:
                out.append((len(out), 0))
            elif self.valid_vaddr(w):
                out.append((len(out), w))
            else:
                break
            i += 1
        while out and out[-1][1] == 0:              # corta NULLs de cauda
            out.pop()
        return out

    def states(self):
        """[(jr_addr, n_estados, addr_var_estado)] dos `switch` que usam a tabela.

        Acha o `jr $rX` alimentado por `lw $rX, (tabela + estado*4)`; `n_estados`
        vem do `sltiu` do teste de limite imediatamente anterior (o proprio
        compilador poe o bound), e `addr_var_estado` do ultimo `lw/lhu/lbu` com
        endereco constante antes do teste.
        """
        tbl = self.base + (0 if self.valid_vaddr(self.words[0]) else 4)
        reg, out = {}, []
        bound = None
        state = None
        pend = None
        for i, w in enumerate(self.words):
            op = w >> 26
            if op == 0x0F:
                reg[(w >> 16) & 0x1F] = [(w & 0xFFFF) << 16, False]
            elif op == 0x09:
                rs, rt = (w >> 21) & 0x1F, (w >> 16) & 0x1F
                if rs == 0:
                    reg[rt] = [_s16(w) & 0xFFFFFFFF, False]
                elif rs in reg:
                    reg[rt] = [(reg[rs][0] + _s16(w)) & 0xFFFFFFFF, reg[rs][1]]
                else:
                    reg.pop(rt, None)
            elif op == 0 and (w & 0x3F) == 0x21:        # addu (base+indice)
                rs, rt, rd = (w >> 21) & 0x1F, (w >> 16) & 0x1F, (w >> 11) & 0x1F
                a, b = reg.get(rs), reg.get(rt)
                if a and not b:
                    reg[rd] = [a[0], True]
                elif b and not a:
                    reg[rd] = [b[0], True]
                elif a and b:
                    reg[rd] = [(a[0] + b[0]) & 0xFFFFFFFF, a[1] or b[1]]
                else:
                    reg.pop(rd, None)
            elif op == 0x0B:                            # sltiu -> bound
                bound = w & 0xFFFF
            elif op in (0x20, 0x21, 0x23, 0x24, 0x25):
                rs, rt = (w >> 21) & 0x1F, (w >> 16) & 0x1F
                if rs in reg:
                    ea = (reg[rs][0] + _s16(w)) & 0xFFFFFFFF
                    if op == 0x23 and reg[rs][1] and ea == tbl:
                        pend = (rt, i)
                    elif not reg[rs][1]:
                        state = ea
                reg.pop(rt, None)
            elif op == 0 and (w & 0x3F) == 0x08:        # jr
                if pend and pend[0] == ((w >> 21) & 0x1F) and i - pend[1] <= 3:
                    out.append((self.base + i * 4, bound, state))
                    pend = None
            if w == 0x03E00008:
                reg = {}
        return out

    def handlers(self):
        """Tabelas de HANDLER por estado: `f = tbl[estado]; jalr f`.

        E o laco principal de cada tela:
            st = *(u8*)ctx;  tbl[st](ctx);  yield()   # yield = EXE 0x8003203c
        Retorna [(jalr_addr, tbl_addr, [ponteiros...])]. A tabela e detectada
        pelo padrao `sll idx,2 ; addu base ; lw ; jalr` com `base` constante.
        """
        reg, out = {}, []
        pend = None
        for i, w in enumerate(self.words):
            op = w >> 26
            if op == 0x0F:
                reg[(w >> 16) & 0x1F] = [(w & 0xFFFF) << 16, False]
            elif op == 0x09:
                rs, rt = (w >> 21) & 0x1F, (w >> 16) & 0x1F
                if rs == 0:
                    reg[rt] = [_s16(w) & 0xFFFFFFFF, False]
                elif rs in reg:
                    reg[rt] = [(reg[rs][0] + _s16(w)) & 0xFFFFFFFF, reg[rs][1]]
                else:
                    reg.pop(rt, None)
            elif op == 0 and (w & 0x3F) == 0x21:
                rs, rt, rd = (w >> 21) & 0x1F, (w >> 16) & 0x1F, (w >> 11) & 0x1F
                a, b = reg.get(rs), reg.get(rt)
                if a and not b:
                    reg[rd] = [a[0], True]
                elif b and not a:
                    reg[rd] = [b[0], True]
                elif a and b:
                    reg[rd] = [(a[0] + b[0]) & 0xFFFFFFFF, a[1] or b[1]]
                else:
                    reg.pop(rd, None)
            elif op == 0x23:                            # lw
                rs, rt = (w >> 21) & 0x1F, (w >> 16) & 0x1F
                if rs in reg and reg[rs][1]:
                    ea = (reg[rs][0] + _s16(w)) & 0xFFFFFFFF
                    if self.valid_vaddr(ea):
                        pend = (rt, i, ea)
                reg.pop(rt, None)
            elif op in (0x20, 0x21, 0x24, 0x25):
                reg.pop((w >> 16) & 0x1F, None)
            elif op == 0 and (w & 0x3F) == 0x09:        # jalr
                if pend and pend[0] == ((w >> 21) & 0x1F) and i - pend[1] <= 3:
                    tbl = pend[2]
                    ptrs = []
                    a = tbl
                    while self.valid_vaddr(a) and a + 4 <= self.vend:
                        v = self.u32(a)
                        if not self.valid_vaddr(v):
                            break
                        ptrs.append(v)
                        a += 4
                    out.append((self.base + i * 4, tbl, ptrs))
                    pend = None
            if w == 0x03E00008:
                reg = {}
        return out

    # ---- strings -----------------------------------------------------------
    def strings(self, min_len=4):
        """[(vaddr, texto)] de strings ASCII imprimiveis terminadas em NUL."""
        out = []
        cur = bytearray()
        start = 0
        for i, b in enumerate(self.text):
            if 0x20 <= b < 0x7F:
                if not cur:
                    start = i
                cur.append(b)
            else:
                if b == 0 and len(cur) >= min_len:
                    out.append((self.base + start, cur.decode("ascii")))
                cur = bytearray()
        return out

    # ---- xrefs -------------------------------------------------------------
    def xrefs(self, addr):
        """Quem referencia `addr`: `jal`, `lui/addiu`, `lui/ori` e palavra-ponteiro.

        Retorna lista de (vaddr_do_sitio, tipo).
        """
        out = []
        hi = {}
        for i, w in enumerate(self.words):
            va = self.base + i * 4
            op = w >> 26
            if op == 3 and (0x80000000 | ((w & 0x3FFFFFF) << 2)) == addr:
                out.append((va, "jal"))
            elif op == 0x0F:
                hi[(w >> 16) & 0x1F] = w & 0xFFFF
            elif op in (0x09, 0x0D):
                rs = (w >> 21) & 0x1F
                rt = (w >> 16) & 0x1F
                if rs in hi:
                    h = hi[rs]
                    v = ((h << 16) | (w & 0xFFFF)) if op == 0x0D \
                        else ((h << 16) + _s16(w)) & 0xFFFFFFFF
                    if v == addr:
                        out.append((va, "lui+%s" % ("ori" if op == 0x0D else "addiu")))
                else:
                    hi.pop(rt, None)
            if w == addr:
                # palavra de dado igual ao endereco (tabela de estados/ponteiros)
                out.append((va, "word"))
        # dedup mantendo ordem
        seen, res = set(), []
        for x in out:
            if x not in seen:
                seen.add(x)
                res.append(x)
        return res

    # ---- chamadas para o EXE ----------------------------------------------
    def exe_calls(self):
        """{endereco_no_EXE: [sitios]} para todo `jal` que sai do overlay."""
        out = {}
        for i, w in enumerate(self.words):
            if (w >> 26) == 3:
                t = 0x80000000 | ((w & 0x3FFFFFF) << 2)
                if t < OVL_LO:
                    out.setdefault(t, []).append(self.base + i * 4)
        return out

    def local_calls(self):
        """{endereco_local: [sitios]} para todo `jal` interno."""
        out = {}
        for i, w in enumerate(self.words):
            if (w >> 26) == 3:
                t = 0x80000000 | ((w & 0x3FFFFFF) << 2)
                if OVL_LO <= t < OVL_HI:
                    out.setdefault(t, []).append(self.base + i * 4)
        return out

    def call_args(self):
        """Rastreador linear de constantes: [(sitio, alvo, {reg: valor})].

        Reconstroi imediatos `lui/ori/addiu` em a0..a3 e tira um retrato a cada
        `jal`. Serve p/ ler `cd_read_file(a0=file_index, ...)` e helpers de
        desenho. NAO segue fluxo de controle - so leitura linear.
        """
        A = {4: "a0", 5: "a1", 6: "a2", 7: "a3"}
        reg = {}
        out = []
        pend = None            # jal cujo snapshot sai DEPOIS do delay slot
        for i, w in enumerate(self.words):
            va = self.base + i * 4
            op = w >> 26
            if op == 0x0F:
                reg[(w >> 16) & 0x1F] = (w & 0xFFFF) << 16
            elif op == 0x09:                        # addiu
                rs, rt = (w >> 21) & 0x1F, (w >> 16) & 0x1F
                if rs == 0:
                    reg[rt] = _s16(w) & 0xFFFFFFFF
                elif rs in reg:
                    reg[rt] = (reg[rs] + _s16(w)) & 0xFFFFFFFF
                else:
                    reg.pop(rt, None)
            elif op == 0x0D:                        # ori
                rs, rt = (w >> 21) & 0x1F, (w >> 16) & 0x1F
                if rs == 0:
                    reg[rt] = w & 0xFFFF
                elif rs in reg:
                    reg[rt] = reg[rs] | (w & 0xFFFF)
                else:
                    reg.pop(rt, None)
            elif op == 0 and (w & 0x3F) == 0x21:    # addu
                rs, rt, rd = (w >> 21) & 0x1F, (w >> 16) & 0x1F, (w >> 11) & 0x1F
                if rs == 0 and rt in reg:
                    reg[rd] = reg[rt]
                elif rt == 0 and rs in reg:
                    reg[rd] = reg[rs]
                elif rs in reg and rt in reg:
                    reg[rd] = (reg[rs] + reg[rt]) & 0xFFFFFFFF
                else:
                    reg.pop(rd, None)
            elif op == 3:                           # jal
                t = 0x80000000 | ((w & 0x3FFFFFF) << 2)
                pend = [va, t, None]
                out.append(pend)
                continue                            # o snapshot sai no proximo passo
            elif op in (0x20, 0x21, 0x23, 0x24, 0x25, 0x0B, 0x0A, 0x0C, 0x0E, 0x0F):
                reg.pop((w >> 16) & 0x1F, None)
            if pend is not None:
                # o delay slot do `jal` JA executou: e ali que o compilador
                # costuma por o ultimo argumento (`addiu $a1, $zero, N`).
                pend[2] = dict((A[r], reg[r]) for r in A if r in reg)
                pend = None
            if w == 0x03E00008:
                reg = {}
        if pend is not None:
            pend[2] = dict((A[r], reg[r]) for r in A if r in reg)
        return out


# ---------------------------------------------------------------------------
# tabela global de arquivos do CD (le direto do EXE)
# ---------------------------------------------------------------------------
def cd_file_table(exe_path=EXE_PATH, n=1400):
    """[(index, size, lba, flags)] da tabela `0x800946a4` do EXE.

    Layout provado em `cd_read_file` (`0x800128b4`..`0x800128e8`):
        size  = u32 @ +0
        lba   = u16 @ +4  |  u8 @ +6 << 16      (24 bits)
        flags = u8  @ +7                        (papel NAO decodificado)
    """
    raw = open(exe_path, "rb").read()
    base = struct.unpack("<I", raw[0x18:0x1C])[0]
    text = raw[0x800:0x800 + struct.unpack("<I", raw[0x1C:0x20])[0]]
    o0 = FILE_TABLE - base
    out = []
    for i in range(n):
        o = o0 + i * FILE_TABLE_STRIDE
        if o + 8 > len(text):
            break
        size = struct.unpack_from("<I", text, o)[0]
        lba = struct.unpack_from("<H", text, o + 4)[0] | (text[o + 6] << 16)
        out.append((i, size, lba, text[o + 7]))
    return out


def all_overlays():
    return [Overlay(os.path.join(BIN_DIR, f))
            for f in sorted(os.listdir(BIN_DIR)) if f.upper().endswith(".BIN")]


# ---------------------------------------------------------------------------
def _cli(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--all":
        print("%-10s %6s  %-10s %-10s %-10s %s" %
              ("overlay", "bytes", "base(auto)", "base(EXE)", "entry", "votos"))
        bad = 0
        for o in all_overlays():
            rec = OVERLAY_TABLE.get(NAME2ID.get(o.name, -1))
            exe_base = DEST_SLOTS[rec[3]] if rec else 0
            amb = (len(o.base_votes) > 1 and
                   o.base_votes[0][1] == o.base_votes[1][1] and
                   o.base_votes[0][3] == o.base_votes[1][3])
            ok = (exe_base == o.base) and not amb
            bad += 0 if ok else 1
            print("%-10s %6d  0x%08x 0x%08x 0x%08x %s%s" %
                  (o.name, o.size, o.base, exe_base, rec[2] if rec else 0,
                   ["%d/%d p=%d" % (v, n, p) for _, v, n, p in o.base_votes[:2]],
                   "" if ok else "   <<< CONFERIR"))
        print("\n%d/%d resolvem a base sem ambiguidade e batem com o EXE"
              % (17 - bad, 17))
        return 0

    o = Overlay(argv[0])
    rest = argv[1:]
    if not rest or rest[0] == "--info":
        print("%s  base=0x%08x  size=%d (0x%x)  vend=0x%08x" %
              (o.name, o.base, o.size, o.size, o.vend))
        print("ovl_id=0x%02x  file_index=0x%02x  entry=0x%08x" %
              (o.ovl_id, o.file_index, o.entry))
        print("votos de base: %s" % o.base_votes)
        print("dispatch: %d entradas   strings: %d" %
              (len(o.dispatch()), len(o.strings())))
    elif rest[0] == "--dispatch":
        for i, a in o.dispatch():
            mark = ""
            if a:
                w = o.u32(a)
                mark = "prologo" if (w >> 16) == 0x27BD and (w & 0x8000) else ""
            print("[%2d] 0x%08x  (+0x%04x) %s" % (i, a, (a - o.base) if a else 0, mark))
    elif rest[0] == "--strings":
        for a, s in o.strings():
            print("0x%08x (+0x%04x)  %s" % (a, a - o.base, s))
    elif rest[0] == "--disasm":
        addr = int(rest[1], 0)
        n = int(rest[2]) if len(rest) > 2 else 40
        o.disasm(addr, n)
    elif rest[0] == "--xrefs":
        for a, k in o.xrefs(int(rest[1], 0)):
            print("0x%08x  %s" % (a, k))
    elif rest[0] == "--calls":
        ft = dict((i, (s, l, f)) for i, s, l, f in cd_file_table())
        for site, tgt, args in o.call_args():
            if tgt >= OVL_LO:
                continue
            extra = ""
            if tgt == EXE_CD_READ_FILE and "a0" in args:
                idx = args["a0"]
                extra = "  <= cd_read_file file_index=0x%02x size=%s" % (
                    idx, ft.get(idx, ("?",))[0])
            print("0x%08x  jal 0x%08x  %s%s" %
                  (site, tgt,
                   " ".join("%s=0x%x" % (k, v) for k, v in sorted(args.items())),
                   extra))
    elif rest[0] == "--handlers":
        for a, tbl, ptrs in o.handlers():
            print("jalr 0x%08x  tabela=0x%08x (+0x%x)  %d handlers:" %
                  (a, tbl, tbl - o.base, len(ptrs)))
            for k, p in enumerate(ptrs):
                w = o.u32(p)
                print("   [%2d] 0x%08x (+0x%04x) %s" % (
                    k, p, p - o.base,
                    "prologo" if (w >> 16) == 0x27BD and (w & 0x8000) else ""))
    elif rest[0] == "--states":
        for a, n, sv in o.states():
            print("jr 0x%08x  n_estados=%s  var_estado=%s" %
                  (a, n, ("0x%08x" % sv) if sv else "?"))
    elif rest[0] == "--filetable":
        for i, s, l, f in cd_file_table(n=int(rest[1]) if len(rest) > 1 else 40):
            print("0x%03x size=%9d lba=%7d flags=0x%02x" % (i, s, l, f))
    else:
        print("opcao desconhecida: %s" % rest[0])
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
