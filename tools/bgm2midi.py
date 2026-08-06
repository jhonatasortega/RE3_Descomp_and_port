#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bgm2midi.py - Extrator EXPERIMENTAL de sequencia dos .BGM do RE3 (PS1).

O .BGM da Capcom NAO e SEQ/pQES padrao. Estrutura observada (engenharia reversa):

  Arquivo .BGM = 1..N blocos de sequencia  +  1 bloco de banco de tons (embutido)

  Cada bloco de sequencia:
    +0   u32 LE   tamanho do bloco (inclui este cabecalho de 12 bytes)
    +4   u32 LE   tempo (microssegundos por semininma; 500000 = 120 BPM)
    +8   u16 LE   PPQN / divisao (ticks por semininma; observado 0x0030 = 48)
    +10  u8       numerador da formula de compasso (obs. 4)
    +11  u8       denominador como potencia de 2 (obs. 2 -> 4/4)
    +12  ...      fluxo de eventos estilo-MIDI:
                    status Cn/Bn/9n/8n... com RUNNING STATUS,
                    delta-time VLQ (MIDI) APOS cada evento (delta "trailing"),
                    encerrado por FF 2F 00 (end of track).

  O bloco de banco (nao e sequencia) aparece quando o u32 de "tamanho" estoura
  o arquivo; e o mapa de programas->amostras PS-ADPCM do .VB pareado.

ATENCAO: os instrumentos corretos estao no .VB/.VH (PS-ADPCM). Este script extrai
SOMENTE a sequencia -> MIDI. Renderizar em WAV com o timbre real exige montar um
SoundFont a partir do VAB (ver docs/formatos/audio_video.md).

Uso:
  python tools/bgm2midi.py <arquivo.BGM> [dir_saida]
Gera <dir_saida>/<nome>_seqNN.mid para cada bloco de sequencia. Somente leitura na origem.
"""
import os
import struct
import sys


def read_vlq(buf, pos):
    """Le um Variable-Length Quantity (MIDI). Retorna (valor, novo_pos)."""
    value = 0
    while True:
        b = buf[pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        if not (b & 0x80):
            break
    return value, pos


def write_vlq(value):
    out = bytearray()
    out.insert(0, value & 0x7F)
    value >>= 7
    while value:
        out.insert(0, (value & 0x7F) | 0x80)
        value >>= 7
    return bytes(out)


# nº de bytes de dados por status MIDI (nibble alto)
DATA_LEN = {0x80: 2, 0x90: 2, 0xA0: 2, 0xB0: 2, 0xC0: 1, 0xD0: 1, 0xE0: 2}


def parse_seq_block(buf, start):
    """Parseia um bloco de sequencia a partir de 'start'. Retorna dict ou None."""
    if start + 12 > len(buf):
        return None
    size, tempo = struct.unpack_from('<II', buf, start)
    ppqn = struct.unpack_from('<H', buf, start + 8)[0]
    ts_num = buf[start + 10]
    ts_den = buf[start + 11]
    # validacao de plausibilidade do bloco de sequencia
    if size < 13 or start + size > len(buf) or ppqn == 0 or ppqn > 960:
        return None

    end = start + size
    pos = start + 12
    events = []          # (evento_bytes, delta_trailing)
    running = None
    ok_eot = False
    while pos < end:
        b = buf[pos]
        if b == 0xFF:                      # meta
            meta_type = buf[pos + 1]
            length, p2 = read_vlq(buf, pos + 2)
            data = buf[p2:p2 + length]
            pos = p2 + length
            if meta_type == 0x2F:          # end of track
                # delta trailing (normalmente 0) e ignorado; encerramos
                ok_eot = True
                break
            ev = bytes([0xFF, meta_type]) + write_vlq(length) + data
            running = None
        else:
            if b & 0x80:                   # novo status
                status = b
                running = status
                pos += 1
            else:                          # running status
                if running is None:
                    return {'error': f'running status invalido em 0x{pos:x}',
                            'events': events, 'ppqn': ppqn}
                status = running
            nd = DATA_LEN.get(status & 0xF0)
            if nd is None:
                return {'error': f'status 0x{status:02x} nao suportado em 0x{pos:x}',
                        'events': events, 'ppqn': ppqn}
            data = buf[pos:pos + nd]
            pos += nd
            ev = bytes([status]) + data
        delta, pos = read_vlq(buf, pos)    # delta TRAILING
        events.append((ev, delta))

    return {'size': size, 'tempo': tempo, 'ppqn': ppqn,
            'ts_num': ts_num, 'ts_den': ts_den,
            'events': events, 'ok_eot': ok_eot, 'end': end, 'error': None}


def build_smf(block):
    """Monta um SMF tipo 0 a partir do bloco parseado."""
    track = bytearray()

    def add(delta, data):
        track.extend(write_vlq(delta))
        track.extend(data)

    # tempo
    add(0, b'\xFF\x51\x03' + struct.pack('>I', block['tempo'])[1:])
    # formula de compasso
    add(0, bytes([0xFF, 0x58, 0x04, block['ts_num'], block['ts_den'], 24, 8]))
    # eventos: converte delta trailing -> leading
    leading = 0
    for ev, dtrail in block['events']:
        add(leading, ev)
        leading = dtrail
    add(leading, b'\xFF\x2F\x00')          # end of track

    ppqn = block['ppqn']
    header = b'MThd' + struct.pack('>IHHH', 6, 0, 1, ppqn)
    chunk = b'MTrk' + struct.pack('>I', len(track)) + bytes(track)
    return header + chunk


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(src) or '.'
    os.makedirs(outdir, exist_ok=True)
    with open(src, 'rb') as f:
        buf = f.read()
    name = os.path.splitext(os.path.basename(src))[0]

    pos, idx, made = 0, 0, 0
    print(f'== {os.path.basename(src)} ({len(buf)} bytes) ==')
    while pos + 12 <= len(buf):
        block = parse_seq_block(buf, pos)
        if block is None:
            print(f'  bloco de banco/tons a partir de 0x{pos:x} '
                  f'({len(buf) - pos} bytes) -> nao e sequencia, fim das musicas')
            break
        if block.get('error'):
            print(f'  seq{idx} @0x{pos:x}: ERRO: {block["error"]} '
                  f'({len(block["events"])} eventos ate falha)')
            break
        notes = sum(1 for ev, _ in block['events'] if (ev[0] & 0xF0) == 0x90 and ev[2] != 0)
        bpm = round(60_000_000 / block['tempo'], 1) if block['tempo'] else 0
        out = os.path.join(outdir, f'{name}_seq{idx:02d}.mid')
        with open(out, 'wb') as g:
            g.write(build_smf(block))
        print(f'  seq{idx}: size={block["size"]} tempo={block["tempo"]}us(~{bpm}bpm) '
              f'ppqn={block["ppqn"]} eventos={len(block["events"])} notes_on={notes} '
              f'eot={"ok" if block["ok_eot"] else "FALTA"} -> {os.path.basename(out)}')
        made += 1
        idx += 1
        pos = block['end']
    print(f'  => {made} MIDI(s) gerado(s)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
