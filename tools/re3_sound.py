#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
re3_sound.py - Monta um SoundFont (.sf2) a partir do VAB REAL do RE3 (PS1).

Fonte (somente leitura): extracted/ntsc-u/CD_DATA/SOUND/<nome>.BGM  (+ .VB)
  - .VB  = corpo PS-ADPCM (amostras dos instrumentos)
  - .BGM = sequencia + banco de tons embutido no fim:
      header do banco (32 B):
        u32 vb_size | u32 bank_size | u32 vagtab_off | u32 ... x5
      programas: 16 B cada (byte0 = numero de tons do programa)
      tons: 32 B cada (VagAtr): [4]center [5]shift [6]min [7]max
                                 [16]adsr1(u16) [18]adsr2(u16) [20]prog(u16) [22]vag(u16)
      tabela VAG: u16[] em vagtab_off = offsets cumulativos (unidades de 8 B) das amostras

Saida: godot/assets/SOUND/BGM/re3.sf2  (cada BGM -> um BANK do SF2)

Uso: python tools/re3_sound.py build
"""
import json
import os
import struct
import sys

import numpy as np

from bgm2midi import build_smf, parse_seq_block
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

SND = 'extracted/ntsc-u/CD_DATA/SOUND'
OUTDIR = paths.assets("SOUND", "BGM")

# BGM -> (bank do SF2, rotulo curto). Ordem = numero do bank.
SONGS = [
    ('MAIN33', 0, 'M33'),
    ('MAIN38', 1, 'M38'),
    ('MAIN39', 2, 'M39'),
    ('MAIN3D', 3, 'M3D'),
    ('SUB_2A', 4, 'S2A'),
]

# ---------------- PS-ADPCM (VAG) decode ----------------
POS = (0, 60, 115, 98, 122)
NEG = (0, 0, -52, -55, -60)


def decode_vag(data, s_init=(0, 0)):
    n = len(data) // 16
    out = np.empty(n * 28, dtype=np.int16)
    s1, s2 = s_init
    k = 0
    for b in range(n):
        base = b * 16
        h = data[base]
        shift = h & 0x0F
        pred = h >> 4
        if pred > 4:
            pred = 0
        if shift > 12:
            shift = 12
        f0 = POS[pred]
        f1 = NEG[pred]
        for j in range(14):
            byte = data[base + 2 + j]
            for nib in (byte & 0x0F, byte >> 4):
                s = nib - 16 if nib >= 8 else nib
                s = (s << 12) >> shift
                pr = s + ((s1 * f0 + s2 * f1) >> 6)
                if pr > 32767:
                    pr = 32767
                elif pr < -32768:
                    pr = -32768
                out[k] = pr
                k += 1
                s2 = s1
                s1 = pr
    return out


def analyze_loop(vb, start_block, end_block):
    """Retorna (loops, loopstart_sample, loopend_sample) para blocos [start,end)."""
    f2 = fs = fe = 0
    lstart = lend = None
    for i in range(start_block, end_block):
        flag = vb[i * 16 + 1]
        if flag == 0x02:
            f2 += 1
        if flag in (0x04, 0x06) and lstart is None:
            lstart = i
        if flag in (0x03, 0x07):
            lend = i
    loops = (f2 > 0) or (lstart is not None and lend is not None and f2 > 0)
    if loops and lstart is not None and lend is not None and lend > lstart:
        return True, (lstart - start_block) * 28, (lend - start_block + 1) * 28
    return False, 0, 0


# ---------------- Parse do banco embutido ----------------
def seq_blocks_end(buf):
    pos = 0
    while pos + 12 <= len(buf):
        size = struct.unpack_from('<I', buf, pos)[0]
        ppqn = struct.unpack_from('<H', buf, pos + 8)[0]
        if size < 13 or pos + size > len(buf) or ppqn == 0 or ppqn > 960:
            break
        pos += size
    return pos


def parse_song(name):
    with open(f'{SND}/{name}.BGM', 'rb') as f:
        bgm = f.read()
    with open(f'{SND}/{name}.VB', 'rb') as f:
        vb = f.read()
    bstart = seq_blocks_end(bgm)
    bank = bgm[bstart:]
    vb_size, bank_size, vagtab_off = struct.unpack_from('<3I', bank, 0)

    # tabela VAG -> fronteiras das amostras
    vt = bank[vagtab_off:bank_size]
    ents = struct.unpack_from('<%dH' % (len(vt) // 2), vt, 0)
    bounds = []
    prev = -1
    for e in ents:
        if e > prev:
            bounds.append(e * 8)
            prev = e
        else:
            break
    if not bounds or bounds[0] != 0:
        bounds = [0] + bounds
    # decodifica cada amostra
    samples = []
    for i in range(len(bounds) - 1):
        a, b = bounds[i], bounds[i + 1]
        a -= a % 16
        b -= b % 16
        pcm = decode_vag(vb[a:b])
        loops, ls, le = analyze_loop(vb, a // 16, b // 16)
        if le > len(pcm) or le <= ls:
            loops, ls, le = False, 0, max(1, len(pcm))
        samples.append({'pcm': pcm, 'loops': loops, 'ls': ls, 'le': le})

    # Tabela de tons: cada tom = 32 B, uma metade "meta" (assinatura SIG@+8,
    # prog@+4, vag@+6) e uma metade "attr" (prior,mode,vol,pan,center,shift,min,max).
    # A ordem interna ([attr][meta] ou [meta][attr]) varia por musica; testa as duas.
    ns = len(samples)
    SIG = b'\xc0\x00\xc1\x00\xc2\x00\xc3\x00'
    first = bank.find(SIG, 32)
    meta_at = (first - 8) if first != -1 else 48

    def parse_tones(tstart, attr_first):
        if tstart < 32 or (vagtab_off - tstart) % 32 != 0:
            return None
        nt = (vagtab_off - tstart) // 32
        progs = {}
        good = 0
        for k in range(nt):
            o = tstart + k * 32
            ao = o if attr_first else o + 16          # attr half
            mo = o + 16 if attr_first else o          # meta half
            vol, pan, center, shift, mn, mx = bank[ao + 2:ao + 8]
            prog, vag = struct.unpack_from('<HH', bank, mo + 4)
            # center (nota-raiz) pode ficar FORA de [min,max]; nao exigir conter.
            if 1 <= vag <= ns and 0 <= mn <= mx <= 127 and 1 <= center <= 127:
                good += 1
                progs.setdefault(prog, []).append(
                    {'center': center, 'shift': shift, 'min': mn, 'max': mx,
                     'vol': vol, 'pan': pan, 'vag': vag})
        return good, nt, progs

    cands = []
    for ts, af in ((meta_at - 16, True), (meta_at, False)):
        r = parse_tones(ts, af)
        if r:
            cands.append((r[0], ts, af, r[1], r[2]))
    if cands:
        cands.sort(reverse=True)                      # maior 'good' primeiro
        good, tstart, attr_first, T, programs = cands[0]
    else:
        tstart, T, programs = meta_at - 16, 0, {}
    P = len(programs)
    ndrop = T - sum(len(v) for v in programs.values())
    if os.environ.get('RE3_DEBUG'):
        print(f"    [{name}] tstart={tstart} NT={T} validos={T-ndrop} "
              f"ns={ns} progs={sorted(programs)}")
        for prog in sorted(programs)[:16]:
            ts = programs[prog]
            rng = f"{min(t['min'] for t in ts)}..{max(t['max'] for t in ts)}"
            ctr = sorted({t['center'] for t in ts})
            vags = sorted({t['vag'] for t in ts})
            print(f"      prog{prog}: {len(ts)} tons key[{rng}] center={ctr} vags={vags}")
    return {'name': name, 'vb_size': vb_size, 'samples': samples,
            'programs': programs, 'nprog': P, 'ntone': T}


# ---------------- SF2 writer ----------------
# generator opcodes
G_KEYRANGE, G_PAN, G_ATT = 43, 17, 48
G_ATTACK, G_RELEASE = 34, 38
G_ROOT, G_FINE, G_MODES, G_SAMPLEID, G_INSTRUMENT = 58, 52, 54, 53, 41


def _s16(v):
    return struct.pack('<h', max(-32768, min(32767, int(v))))


def _u16(v):
    return struct.pack('<H', int(v) & 0xFFFF)


def gen(op, amount_bytes):
    return _u16(op) + amount_bytes


def build_sf2(songs):
    smpl = bytearray()
    shdrs = []          # (name,start,end,ls,le,rate,root,corr,link,type)
    insts = []          # (name, [zones])  zone = list of gen bytes
    presets = []        # (name,bank,prog,instidx)

    for song in songs:
        base = len(shdrs)
        for si, s in enumerate(song['samples']):
            pcm = s['pcm']
            start = len(smpl) // 2
            smpl.extend(pcm.tobytes())
            end = len(smpl) // 2
            smpl.extend(b'\x00\x00' * 46)
            ls = start + s['ls'] if s['loops'] else start
            le = start + s['le'] if s['loops'] else end
            le = min(le, end)
            if le <= ls:
                le = end
            shdrs.append((f"{song['label']}_s{si:02d}", start, end, ls, le,
                          44100, 60, 0, 0, 1))
        for prog in sorted(song['programs']):
            tones = song['programs'][prog]
            if not tones:
                continue
            zones = []
            for t in tones:
                sidx = base + (t['vag'] - 1)
                loops = song['samples'][t['vag'] - 1]['loops']
                z = bytearray()
                z += gen(G_KEYRANGE, bytes([t['min'] & 0x7F, t['max'] & 0x7F]))
                z += gen(G_PAN, _s16(round((t['pan'] - 64) / 64 * 500)))
                att = 0
                if t['vol'] < 127:
                    import math
                    att = min(200, round(-200 * math.log10(max(t['vol'], 1) / 127.0)))
                z += gen(G_ATT, _s16(att))
                z += gen(G_ATTACK, _s16(-8000))     # ~10 ms
                z += gen(G_RELEASE, _s16(-2000))     # ~300 ms
                z += gen(G_ROOT, _u16(t['center']))
                z += gen(G_FINE, _s16(round(t['shift'] * 100 / 128)))
                z += gen(G_MODES, _u16(1 if loops else 0))
                z += gen(G_SAMPLEID, _u16(sidx))     # DEVE ser o ultimo
                zones.append(bytes(z))
            insts.append((f"{song['label']}_p{prog:02d}", zones))
            # numeracao GLOBAL de programa no bank 0 (evita bank-select no fluidsynth)
            presets.append((f"{song['label']}{prog:02d}", 0, song['base'] + prog,
                            len(insts) - 1))

    # ---- monta chunks pdta ----
    # igen + ibag + inst
    igen = bytearray()
    ibag = bytearray()
    inst_rec = bytearray()
    izone_count = 0
    for name, zones in insts:
        inst_rec += name.encode('ascii', 'ignore')[:20].ljust(20, b'\x00') + _u16(izone_count)
        for z in zones:
            ibag += _u16(len(igen) // 4) + _u16(0)   # genndx, modndx
            igen += z
            izone_count += 1
    inst_rec += b'EOI'.ljust(20, b'\x00') + _u16(izone_count)
    ibag += _u16(len(igen) // 4) + _u16(0)
    igen += _u16(0) + _u16(0)

    # pgen + pbag + phdr
    pgen = bytearray()
    pbag = bytearray()
    phdr = bytearray()
    pzone_count = 0
    for name, bank, prog, instidx in presets:
        phdr += name.encode('ascii', 'ignore')[:20].ljust(20, b'\x00')
        phdr += _u16(prog) + _u16(bank) + _u16(pzone_count)
        phdr += struct.pack('<III', 0, 0, 0)
        pbag += _u16(len(pgen) // 4) + _u16(0)
        pgen += gen(G_INSTRUMENT, _u16(instidx))
        pzone_count += 1
    phdr += b'EOP'.ljust(20, b'\x00') + _u16(0) + _u16(0) + _u16(pzone_count)
    phdr += struct.pack('<III', 0, 0, 0)
    pbag += _u16(len(pgen) // 4) + _u16(0)
    pgen += _u16(0) + _u16(0)

    pmod = b'\x00' * 10
    imod = b'\x00' * 10

    shdr = bytearray()
    for (nm, st, en, ls, le, rate, root, corr, link, typ) in shdrs:
        shdr += nm.encode('ascii', 'ignore')[:20].ljust(20, b'\x00')
        shdr += struct.pack('<IIIII', st, en, ls, le, rate)
        shdr += struct.pack('<BbHH', root, corr, link, typ)
    shdr += b'EOS'.ljust(20, b'\x00') + struct.pack('<IIIII', 0, 0, 0, 0, 0)
    shdr += struct.pack('<BbHH', 0, 0, 0, 0)

    def chunk(tag, data):
        d = bytes(data)
        out = tag + struct.pack('<I', len(d)) + d
        if len(d) & 1:
            out += b'\x00'
        return out

    info = (b'INFO'
            + chunk(b'ifil', struct.pack('<HH', 2, 1))
            + chunk(b'isng', b'EMU8000\x00')
            + chunk(b'INAM', b'RE3 VAB\x00'))
    sdta = b'sdta' + chunk(b'smpl', smpl)
    pdta = (b'pdta'
            + chunk(b'phdr', phdr) + chunk(b'pbag', pbag) + chunk(b'pmod', pmod)
            + chunk(b'pgen', pgen) + chunk(b'inst', inst_rec) + chunk(b'ibag', ibag)
            + chunk(b'imod', imod) + chunk(b'igen', igen) + chunk(b'shdr', shdr))
    body = (b'sfbk' + chunk(b'LIST', info) + chunk(b'LIST', sdta) + chunk(b'LIST', pdta))
    return b'RIFF' + struct.pack('<I', len(body)) + body, len(shdrs), len(insts), len(presets)


def seq_channels(bgm):
    """Canais (0-15) que aparecem em eventos de canal da sequencia."""
    pos, chans = 0, set()
    while pos + 12 <= len(bgm):
        blk = parse_seq_block(bgm, pos)
        if not blk or blk.get('error'):
            break
        for ev, _ in blk['events']:
            if 0x80 <= ev[0] < 0xF0:
                chans.add(ev[0] & 0x0F)
        pos = blk['end']
    return chans


def render_midis(song):
    """Gera <NAME>_seqNN.mid com programas reescritos (base+local) e canal 9 remapeado."""
    with open(f"{SND}/{song['name']}.BGM", 'rb') as f:
        bgm = f.read()
    chans = seq_channels(bgm)
    chmap = {}
    if 9 in chans:                                   # canal 9 = percussao GM: remapeia
        free = next(c for c in range(15, -1, -1) if c not in chans)
        chmap[9] = free
    base = song['base']
    outs = []
    pos, idx = 0, 0
    while pos + 12 <= len(bgm):
        blk = parse_seq_block(bgm, pos)
        if not blk or blk.get('error'):
            break
        evs = []
        for ev, delta in blk['events']:
            st = ev[0]
            if st >= 0xF0:                           # meta: inalterado
                evs.append((ev, delta))
                continue
            hi, ch = st & 0xF0, st & 0x0F
            ch = chmap.get(ch, ch)
            if hi == 0xC0:                           # program change: local -> global
                data = bytes([(base + ev[1]) & 0x7F])
            else:
                data = ev[1:]
            evs.append((bytes([hi | ch]) + data, delta))
        blk2 = dict(blk)
        blk2['events'] = evs
        out = os.path.join(OUTDIR, f"{song['name']}_seq{idx:02d}.mid")
        with open(out, 'wb') as g:
            g.write(build_smf(blk2))
        outs.append(os.path.basename(out))
        idx += 1
        pos = blk['end']
    return outs, chmap


def main():
    if len(sys.argv) < 2 or sys.argv[1] != 'build':
        print(__doc__)
        return 1
    os.makedirs(OUTDIR, exist_ok=True)
    songs = []
    base = 0
    for name, bank, label in SONGS:
        s = parse_song(name)
        s['label'] = label
        s['base'] = base
        s['nglobal'] = f"{base}..{base + len(s['programs']) - 1}"
        base += len(s['programs'])
        songs.append(s)

    manifest = {}
    for s in songs:
        mids, chmap = render_midis(s)
        s['midis'] = mids
        nnotes = sum(len(v) for v in s['programs'].values())
        print(f"[{s['name']}] amostras={len(s['samples'])} programas={len(s['programs'])} "
              f"tons_usaveis={nnotes} progGlobal={s['nglobal']} "
              f"ch9remap={chmap or '-'} midis={len(mids)}")
        manifest[s['name']] = {'label': s['label'], 'prog_global_base': s['base'],
                               'programs_local': sorted(s['programs']),
                               'samples': len(s['samples']),
                               'ch9_remap': chmap, 'midis': mids}

    sf2, nsmp, ninst, npre = build_sf2(songs)
    out = os.path.join(OUTDIR, 're3.sf2')
    with open(out, 'wb') as f:
        f.write(sf2)
    with open(os.path.join(OUTDIR, 're3_sf2_manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=2)
    print(f"\n=> {out}: {len(sf2)} bytes | amostras={nsmp} instrumentos={ninst} presets={npre}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
