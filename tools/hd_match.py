#!/usr/bin/env python3
"""Casamento dos assets HD do Seamless com os do PS1. Dois metodos, nesta ordem de confianca:

  1. `hash`  -- EXATO. O nome do .webp do pack HD **e** o CRC-32 do bloco SD que ele
     substitui, e esse hash E REPRODUZIVEL. Ver `cmd_hash` e a secao abaixo.
  2. `bgd`   -- content-matching por NCC, para os backgrounds de sala (nao tem hash
     reproduzivel porque o bloco blitado depende das coordenadas do engine).

=============================================================================
METODO 1 -- O HASH EXATO (achado de 2026-08-08; corrige o de-para dos icones)
=============================================================================
O `hd_ui_map.json` registrava `reproducivel_estaticamente: false` para o hash do
`bio3hd.asi` (funcao em VA 0x10002280, tabela CRC em 0x10001d60). O motivo alegado era
"a unidade de hash e o sub-retangulo blitado, precisa das coordenadas do engine".
Para os icones de item e para as placas isso NAO se aplica: o bloco blitado E a imagem
inteira, entao o hash da para calcular. Reproduzido byte a byte:

    hash = zlib.crc32( BGRA do bloco, linha a linha )     -> nome do .webp em MAIUSCULA

com a conversao de cor **medida** (unica das 24 combinacoes testadas que casa):
    5 bits -> 8 bits por REPLICACAO DE BITS ALTOS:  c8 = (c5 << 3) | (c5 >> 2)
    ordem dos bytes: B, G, R, A   com A = 0xFF
    (o `c5 * 255 // 31` e o `c5 << 3` dao ZERO acertos -- nao e questao de gosto)

Fontes SD e resultado medido:
  * icones 40x30: `ETC/ITEMA.SLD` descomprimido (LZ de 0x80010000), offset por item_id na
    tabela `0x8009F678`, paleta = **linha 1** das 4 CLUTs do `ETC/STMAIN0U.TIM`
    -> 121 dos 134 item_id casam, usando 107 dos 120 .webp de `hires/item/`.
    Sanidade: as outras 3 linhas de CLUT dao **0** acertos (nao ha falso positivo).
  * placas 112x72: `ETC/ITEMG.PIX`, cada slot de 10240 B com a CLUT dele
    -> 86 dos 134 casam, usando 73 dos 108 .webp de `hires/info/`.

O que o hash conserta em relacao ao content-matching anterior (`port/dev/hd_casar.gd`):
  * o casamento por erro de cor com limiar 0.12 e SEM margem aceitava par errado. Ex.: o
    item 0x81 (Fita de tinta) levava o .webp do 0x17 (Cartuchos de escopeta) -- era o bug
    relatado pelo dono, o icone da grade mostrando caixa de municao de escopeta.
  * a atribuicao global era INJETIVA (um .webp por item), e isso e falso no dado: varios
    item_id compartilham o MESMO bitmap de icone (os 4 lanca-granadas 0x06..0x09, o par
    arma/arma-melhorada, os 8 ids que usam o icone da SIGPRO). Forcar 1:1 obrigava a dar
    arquivo errado aos duplicados, e o erro se propagava em cascata.

Uso:
    python hd_match.py hash              # auditoria (mostra o que muda, nao escreve)
    python hd_match.py hash --apply      # reescreve data/hd_status_map.json + copia webp
    python hd_match.py bgd               # dry-run dos backgrounds
    python hd_match.py bgd --apply

=============================================================================
METODO 2 -- backgrounds por NCC
=============================================================================
Para cada camera PS1 sem HD (assets/STAGE{n}/R###_#.png sem .webp), acha o .webp de
hires/bgd que casa por imagem — NCC em thumbnail cinza. Match verdadeiro NCC~0.99 vs
falso <0.5 (gap enorme, calibrado). Se NCC >= NCC_MIN, copia o webp e remove o png.
"""
import os
import re
import sys
import glob
import json
import shutil
import struct
import zlib
import numpy as np
from PIL import Image
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py
import status_assets as SA

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = paths.assets()
HIRES = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
BGD = os.path.join(HIRES, "bgd")
THUMB = (64, 48)     # cinza p/ NCC (4:3, igual ao PS1 e HD)
NCC_MIN = 0.92       # margem enorme (verdadeiros ~0.99, falsos <0.5)

# ── constantes do hash (todas MEDIDAS, ver o cabecalho) ──
CLUT_ICONE = 1          # linha 1 das 4 CLUTs do STMAIN0U; as outras 3 dao 0 acertos
PASSO_ITEMG = 10240     # tamanho fixo do slot de placa no ITEMG.PIX
LIMIAR_CONTEUDO = 0.12  # so para o RESIDUO (o que o hash nao resolve)
MARGEM_MIN = 0.15       # 2o colocado tem de ser >=15% pior, senao o par fica declarado fraco


def norm_thumb(path):
    im = Image.open(path).convert("L").resize(THUMB)
    a = np.asarray(im, dtype=np.float32).ravel()
    a -= a.mean()
    n = np.linalg.norm(a)
    return a / n if n > 0 else a


def cmd_bgd(apply):
    hd_files = sorted(glob.glob(os.path.join(BGD, "*.webp")))
    H, hp = [], []
    for p in hd_files:
        try:
            H.append(norm_thumb(p))
            hp.append(p)
        except Exception:
            pass
    H = np.vstack(H)
    print("HD indexados:", len(hp))

    todo = [png for png in glob.glob(os.path.join(ASSETS, "STAGE*", "*.png"))
            if not os.path.exists(png[:-4] + ".webp")]
    print("PS1 sem HD:", len(todo))

    buckets = {">=0.99": 0, "0.92-0.99": 0, "0.5-0.92": 0, "<0.5": 0}
    matched = applied = 0
    ambiguous = []
    for png in todo:
        try:
            v = norm_thumb(png)
        except Exception:
            continue
        s = H @ v
        j = int(np.argmax(s))
        best = float(s[j])
        if best >= 0.99:
            buckets[">=0.99"] += 1
        elif best >= 0.92:
            buckets["0.92-0.99"] += 1
        elif best >= 0.5:
            buckets["0.5-0.92"] += 1
            ambiguous.append((os.path.basename(png), round(best, 3)))
        else:
            buckets["<0.5"] += 1
        if best >= NCC_MIN:
            matched += 1
            if apply:
                dst = png[:-4] + ".webp"
                shutil.copy(hp[j], dst)
                os.remove(png)
                if os.path.exists(png + ".import"):
                    os.remove(png + ".import")
                applied += 1

    print("distribuicao do melhor NCC:", buckets)
    print(("APLICADO" if apply else "DRY-RUN") +
          ": casados (NCC>=%.2f): %d/%d | sem HD real: %d" %
          (NCC_MIN, matched, len(todo), len(todo) - matched))
    if apply:
        print("aplicados (webp copiado, png removido):", applied)
    if ambiguous:
        print("zona ambigua (0.5-0.92) — conferir:", ambiguous[:15])


# =============================================================================
# METODO 1: HASH EXATO (icones do ITEMA.SLD e placas do ITEMG.PIX)
# =============================================================================
def crc_bgra(indices, paleta):
    """CRC-32 do bloco em BGRA, do jeito que o bio3hd.asi hasheia. `paleta` = lista de
    (r, g, b) ja em 8 bits. A = 0xFF (medido: o valor do alpha e' indiferente porque
    nenhuma das duas fontes usa o indice 0 nos pixels, mas 0xFF e' o que o PC escreve)."""
    buf = bytearray()
    for p in indices:
        r, g, b = paleta[p]
        buf += bytes((b, g, r, 0xFF))
    return "%08X" % (zlib.crc32(bytes(buf)) & 0xFFFFFFFF)


def paleta_de(halfwords):
    """BGR555 -> RGB888 por REPLICACAO DE BITS ALTOS. E' esta a conversao que casa o hash
    (as outras duas candidatas, `*255//31` e `<<3`, dao ZERO acertos nos 120 arquivos)."""
    out = []
    for v in halfwords:
        r, g, b = v & 31, (v >> 5) & 31, (v >> 10) & 31
        out.append((((r << 3) | (r >> 2)), ((g << 3) | (g >> 2)), ((b << 3) | (b >> 2))))
    return out


def clut_do_tim(buf, linha=0):
    """Devolve a lista de halfwords da CLUT `linha` de um TIM, e o offset da imagem."""
    clut_len, _cx, _cy, cw, _ch = struct.unpack_from("<I4H", buf, 8)
    base = 20 + linha * cw * 2
    hw = [struct.unpack_from("<H", buf, base + i * 2)[0] for i in range(cw)]
    return hw, 8 + clut_len


def hashes_icones():
    """item_id -> hash do icone 40x30 do `ETC/ITEMA.SLD` (134 entradas)."""
    e = SA.Exe(SA.EXE)
    sld = open(os.path.join(SA.ETC, "ITEMA.SLD"), "rb").read()
    tim = open(os.path.join(SA.ETC, "STMAIN0U.TIM"), "rb").read()
    hw, _ = clut_do_tim(tim, CLUT_ICONE)
    pal = paleta_de(hw)
    out = {}
    n = SA.ICONE_W * SA.ICONE_H
    for i in range(SA.N_ITENS):
        off = e.u32(SA.SLD_OFFSETS + i * 4)
        try:
            bruto = SA.descomprimir(sld[off:], n)
        except Exception:                                    # noqa: BLE001
            continue
        if len(bruto) < n:
            continue
        out[i] = crc_bgra(bruto[:n], pal)
    return out


def hashes_placas():
    """item_id -> hash da placa 112x72 do `ETC/ITEMG.PIX` (array de TIM, passo 10240)."""
    d = open(os.path.join(SA.ETC, "ITEMG.PIX"), "rb").read()
    out = {}
    for i in range(len(d) // PASSO_ITEMG):
        b = d[i * PASSO_ITEMG:(i + 1) * PASSO_ITEMG]
        if struct.unpack_from("<I", b, 0)[0] != 0x10:
            continue
        hw, o = clut_do_tim(b, 0)
        _img_len, _ix, _iy, iw, ih = struct.unpack_from("<I4H", b, o)
        px = b[o + 12:o + 12 + iw * 2 * ih]
        out[i] = crc_bgra(px, paleta_de(hw))
    return out


def _sd_reduzido(rel, tam):
    im = Image.open(os.path.join(ASSETS, rel)).convert("RGBA")
    if im.size != tam:
        im = im.resize(tam, Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def _hd_reduzido(caminho, tam):
    im = Image.open(caminho).convert("RGBA").resize(tam, Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def _erro(sd, hd):
    """Erro absoluto medio de cor, so onde o SD e' opaco (a mesma metrica do hd_casar.gd)."""
    m = sd[:, :, 3] >= 0.5
    if not m.any():
        return 1e9
    return float(np.abs(sd[:, :, :3][m] - hd[:, :, :3][m]).mean())


def casar_residuo(pendentes, sobrando, cat, dir_sd, tam):
    """Content-matching APENAS do residuo: os item_id que o hash nao resolveu contra os
    .webp que o hash nao consumiu. Atribuicao global (melhor par primeiro) + MARGEM: o
    2o colocado tem de ser pelo menos MARGEM_MIN pior, senao o par sai marcado fraco."""
    if not pendentes or not sobrando:
        return {}
    sds = {}
    for i in pendentes:
        rel = "%s/%03d.png" % (dir_sd, i)
        if os.path.exists(os.path.join(ASSETS, rel)):
            sds[i] = _sd_reduzido(rel, tam)
    hds = {}
    for k in sobrando:
        p = os.path.join(HIRES, cat, k + ".webp")
        if os.path.exists(p):
            hds[k] = _hd_reduzido(p, tam)
    erros = {(i, k): _erro(sds[i], hds[k]) for i in sds for k in hds}
    pares = sorted((e, ik[0], ik[1]) for ik, e in erros.items())
    mapa, usados = {}, set()
    for err, i, k in pares:
        if err > LIMIAR_CONTEUDO or i in mapa or k in usados:
            continue
        usados.add(k)
        ## MARGEM medida contra o pool AINDA LIVRE no momento da fixacao (foi o que faltava
        ## no casamento antigo: sem margem, um par ruim entrava so por estar sob o limiar).
        outros = sorted(erros[(i, k2)] for k2 in hds if k2 not in usados)
        segundo = outros[0] if outros else 1e9
        margem = (segundo - err) / max(err, 1e-6)
        mapa[i] = {"webp": "%s/%s" % (cat, k), "erro": round(err, 4),
                   "metodo": "conteudo", "margem": round(margem, 3),
                   "confianca": "alta" if margem >= MARGEM_MIN else "baixa"}
    return mapa


def _copiar(de, rel_destino):
    dst = os.path.join(ASSETS, rel_destino)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy(de, dst)


def cmd_hash(apply):
    saida = {}
    total_troca = 0
    for chave, cat, dir_sd, sub, tam, calc in (
            ("itema", "item", "MENU/status/itema", "itema", (40, 30), hashes_icones),
            ("placa", "info", "ETC/items", "plate", (112, 72), hashes_placas)):
        crc = calc()
        ## O nome de um asset HD e' EXATAMENTE 8 digitos hex (o CRC-32). O pack traz dois
        ## intrusos que nao sao hash (`5F5D30DF  .webp` com espacos e `chris jill.webp`) —
        ## o de espacos era o que estava no mapa antigo na entrada 014, duplicando o 003.
        pool = {os.path.splitext(os.path.basename(p))[0].upper()
                for p in glob.glob(os.path.join(HIRES, cat, "*.webp"))
                if re.fullmatch(r"[0-9A-Fa-f]{8}", os.path.splitext(os.path.basename(p))[0])}
        mapa = {}
        for i in sorted(crc):
            if crc[i] in pool:
                mapa[i] = {"webp": "%s/%s" % (cat, crc[i]), "metodo": "hash",
                           "confianca": "exata"}
        usados = {v["webp"].split("/")[-1] for v in mapa.values()}
        pendentes = [i for i in sorted(crc) if i not in mapa]
        residuo = casar_residuo(pendentes, sorted(pool - usados), cat, dir_sd, tam)
        mapa.update(residuo)
        print("[%s] %d/%d por HASH (%d .webp de %d) + %d por conteudo | %d sem par" % (
            chave, len(mapa) - len(residuo), len(crc), len(usados), len(pool),
            len(residuo), len(crc) - len(mapa)))
        # comparacao com o mapa vigente, para o log de auditoria
        antigo = _mapa_vigente(chave)
        for i in sorted(set(list(mapa) + [int(k) for k in antigo])):
            de = antigo.get("%03d" % i, {}).get("webp", "").strip()
            para = mapa.get(i, {}).get("webp", "")
            if de != para:
                total_troca += 1
                print("   %3d 0x%02x  %-16s -> %-16s (%s)" % (
                    i, i, de or "(nada)", para or "(nada)",
                    mapa.get(i, {}).get("metodo", "sem par")))
        saida[chave] = {"%03d" % i: mapa[i] for i in sorted(mapa)}
        if apply:
            for i, v in mapa.items():
                _copiar(os.path.join(HIRES, v["webp"] + ".webp"),
                        "MENU/status/hd/%s/%03d.webp" % (sub, i))
            ## LIMPEZA DOS ORFAOS. Sem isto o de-para novo nao conserta nada para os itens
            ## que PERDERAM o par: o .webp errado do casamento antigo continua no disco e a
            ## tela o carrega antes do PNG do PS1 (`AssetIO.exists(rel_hd)` vem primeiro).
            dest = os.path.join(ASSETS, "MENU/status/hd", sub)
            for p in glob.glob(os.path.join(dest, "*.webp")):
                nome = os.path.splitext(os.path.basename(p))[0]
                if nome.isdigit() and int(nome) not in mapa:
                    os.remove(p)
                    for extra in (p + ".import", p + ".ctex"):
                        if os.path.exists(extra):
                            os.remove(extra)
                    print("   orfao removido: hd/%s/%s" % (sub, os.path.basename(p)))
    print(("APLICADO" if apply else "DRY-RUN") + ": %d entradas mudam" % total_troca)
    if not apply:
        return
    # preserva o que nao e' desta ferramenta (moldura e blocos de VRAM, casados a parte)
    caminho = paths.data("hd_status_map.json")
    atual = {}
    if os.path.exists(caminho):
        atual = json.load(open(caminho, encoding="utf-8"))
    atual["_meta"] = {
        "gerado_por": "tools/hd_match.py hash --apply",
        "metodo": ("itema/placa = HASH EXATO: o nome do .webp e' o zlib.crc32 do bloco SD "
                   "em BGRA (5->8 bits por replicacao de bits altos, A=0xFF). Entradas com "
                   "metodo=conteudo sao o RESIDUO, casadas por erro de cor com margem."),
        "fontes_sd": {"itema": "ETC/ITEMA.SLD (LZ 0x80010000, offsets 0x8009F678, "
                               "CLUT linha 1 do STMAIN0U.TIM)",
                      "placa": "ETC/ITEMG.PIX (array de TIM, passo 10240, CLUT do slot)"},
        "hash_hires": "bio3hd.asi: funcao em 0x10002280, tabela CRC-32 em 0x10001d60",
        "de_para": "a chave e' o item_id em decimal com 3 digitos",
    }
    atual["itema"] = saida["itema"]
    atual["placa"] = saida["placa"]
    json.dump(atual, open(caminho, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("escrito", caminho)


def _mapa_vigente(chave):
    caminho = paths.data("hd_status_map.json")
    if not os.path.exists(caminho):
        return {}
    return json.load(open(caminho, encoding="utf-8")).get(chave, {})


def main():
    apply = "--apply" in sys.argv
    modo = "hash"
    for a in sys.argv[1:]:
        if a in ("hash", "bgd"):
            modo = a
    if modo == "bgd":
        cmd_bgd(apply)
    else:
        cmd_hash(apply)


if __name__ == "__main__":
    main()
