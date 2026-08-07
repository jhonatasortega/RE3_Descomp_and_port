#!/usr/bin/env python3
"""CLI única de build de assets do port (item P0-02 do plano).

Monta `<out>/assets` e `<out>/data` a partir das SUAS fontes (imagem do disco PS1 +
instalação de PC/GOG com o Seamless HD Project). Substitui o "rodar 40 scripts na
ordem certa e lembrar de cada flag": cada etapa aqui declara comando, dependências,
fonte necessária e o que produz.

    python tools/build_assets.py --list                    # etapas, deps e estado
    python tools/build_assets.py --out port                # tudo o que for automático
    python tools/build_assets.py --out port --only rooms,scd
    python tools/build_assets.py --out port --dry-run      # só mostra o que rodaria
    python tools/build_assets.py --out port --manifest     # grava asset_manifest.json
    python tools/build_assets.py --out port --verify       # confere contra o manifesto

O destino chega nos scripts pela variável NOSTALGIA_OUT (ver tools/paths.py), então
nenhum caminho fica fixo no código das ferramentas.

HONESTIDADE: etapas marcadas `manual=True` NÃO rodam sozinhas (dependem de ferramenta
externa ou de decisão humana) e aparecem no relatório como PENDENTE-MANUAL — nunca são
silenciosamente puladas. Ver docs/port/PROGRESSO.md (P0-02, P0-03).
"""
import glob
import json
import os
import subprocess
import sys
import time

import paths

# O console do Windows é cp1252: uma linha de saída de ferramenta com caractere fora
# dessa tabela derrubava o build inteiro no print. errors='replace' troca o caractere
# em vez de estourar (o build não pode morrer por causa de um acento).
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(errors="replace")
    except Exception:
        pass

ROOT = paths.ROOT
PY = sys.executable
GOG_DEFAULT = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3"


def gog_root():
    return os.environ.get("NOSTALGIA_GOG") or GOG_DEFAULT


def hires_root():
    return os.environ.get("NOSTALGIA_HIRES") or os.path.join(gog_root(), "hires")


# ---------------------------------------------------------------- fontes de entrada
def src_iso():
    return os.path.isdir(paths.cd_data())


def src_hires():
    return os.path.isdir(os.path.join(hires_root(), "bgd"))


def src_rofs():
    return os.path.isfile(os.path.join(gog_root(), "Rofs9.dat"))


def src_ptbr():
    return os.path.isdir(os.path.join(gog_root(), "mod_BH3_Portuguese", "xml"))


def src_legacy():
    return os.path.isdir(os.path.join(ROOT, "godot", "data"))


SOURCES = {
    "iso":   ("imagem do disco PS1 já extraída em extracted/ntsc-u/CD_DATA", src_iso),
    "hires": ("instalação de PC com o Seamless HD Project (hires/bgd)", src_hires),
    "rofs":  ("Rofs*.dat da instalação de PC (modelos de inimigo, vozes EN)", src_rofs),
    "ptbr":  ("pacote PT-BR aplicado (mod_BH3_Portuguese/xml)", src_ptbr),
    "legacy": ("godot/data do protótipo antigo (sementes ainda não regeneráveis)", src_legacy),
}

# P0-11 FECHADO para 5 dos 6: physics/anim_map/ai_overlays/sce_items/re3_items agora são
# GERADOS da fonte (ver etapas physics, anim_map, ai_overlays, scd_items, text). Sobra UM
# resíduo honesto: hd_ui_map.json NÃO é reproduzível estaticamente (o hash é o sub-retângulo
# BLITADO pelo engine — precisa das coords de blit; os .webp HD vêm de um PC russo e são
# REDESENHADOS, não upscale — downscale não recupera o buffer SD). Produzi-lo exige o dump
# do plugin bio3hd rodando o jogo. Fica como seed mínimo, DECLARADO (não é dívida oculta).
SEEDS = [
    ("hd_ui_map.json", "de-para HD de UI/itens/memos — RESÍDUO: não reproduzível estaticamente "
                       "(hash = sub-retângulo blitado do engine; HD de PC russo redesenhado). "
                       "Requer o dump do plugin bio3hd. Ver docs/port/PROGRESSO.md (P0-11)."),
]

# ------------------------------------------------------------------------- etapas
# cmds: lista de argv (relativos a tools/); {G}=raiz GOG, {H}=hires, {A}=assets, {D}=data
# glob_src: expande arquivos de entrada como argumentos (pipeline em lote)
STAGES = [
    # ---------- dados de sala (JSON) ----------
    dict(id="rooms", titulo="Salas .ARD -> JSON (câmeras, blocos, script)", src="iso", deps=[],
         cmds=[["ard_parse.py", "--all", "--in", paths.cd_data(), "--out", "{D}"]],
         out=["data/STAGE*/R*.json"], doc="docs/formatos/ARD.md"),
    dict(id="collision", titulo="Colisão + layout das máscaras (offset_table[6])", src="iso",
         deps=["rooms"], cmds=[["rdt_collision.py"]], out=["data/STAGE*/*_col.json"],
         doc="docs/formatos/ARD.md"),
    dict(id="scd", titulo="SCD -> gameplay por sala (portas/gatilhos/itens/entidades)", src="iso",
         deps=["rooms"], cmds=[["scd_gameplay.py"]],
         out=["data/STAGE*/*_scd.json", "data/room_graph.json"], doc="docs/formatos/scd_gameplay.md"),
    dict(id="scd_doors", titulo="Portas do SCD (opcode 0x67) + map_graph", src="iso",
         deps=["scd"], cmds=[["scd_doors.py"]], out=["data/map_graph.json"],
         doc="docs/formatos/scd_gameplay.md"),
    dict(id="scd_items", titulo="Itens no mundo (0x68) + nomes + sce_items.json", src="iso", deps=["scd"],
         cmds=[["scd_items.py"], ["scd_items.py", "--build-json"]],
         out=["data/sce_item_names.json", "data/sce_items.json"],
         doc="docs/decomp/notes/messages.md"),
    dict(id="door_dest", titulo="Destino estático das portas (sala->sala)", src="iso",
         deps=["scd"], cmds=[["scd_door_dest.py"]], out=[],
         doc="docs/decomp/notes/door_handler.md"),
    dict(id="room_graph", titulo="Grafo real de salas (453 portas, 296 arestas)", src="iso",
         deps=["door_dest"], cmds=[["room_graph_build.py"]], out=["data/room_graph.json"],
         doc="docs/decomp/notes/room_graph.md"),
    dict(id="ai_overlays", titulo="Papel dos 548 handlers de IA (overlays STAGE#/R###.BIN)", src="iso",
         deps=[], cmds=[["overlay_ai.py", "catalog", "--json", "{D}/ai_overlays.json"]],
         out=["data/ai_overlays.json"], doc="docs/decomp/notes/exe_ai.md"),
    dict(id="physics", titulo="Física do player: sin/cos do EXE + root-motion de PL00.PLD", src="iso",
         deps=[], cmds=[["exe_physics.py"]], out=["data/physics.json"], doc="docs/formatos/exe.md"),
    dict(id="anim_map", titulo="Máquina de anim do player (tabela 3x3 @0x8009cde0 + root-motion)",
         src="iso", deps=[], cmds=[["exe_anim_map.py"]], out=["data/anim_map.json"],
         doc="docs/formatos/exe.md"),
    dict(id="seed", titulo="Resíduo honesto P0-11: hd_ui_map.json (de-para HD não reproduzível estaticamente)",
         src="legacy", deps=[], cmds=["@seed"], out=["data/" + f for f, _ in SEEDS],
         doc="docs/port/PROGRESSO.md (P0-11)",
         nota="P0-11 FECHADO p/ 5 dos 6 (ai_overlays/physics/anim_map/sce_items/re3_items são "
              "GERADOS da fonte). Sobra hd_ui_map.json: resíduo genuíno — o de-para HD exige o "
              "dump do plugin bio3hd (hash = sub-retângulo blitado), não é transformação estática "
              "do disco. Copiado como seed mínimo e declarado."),
    dict(id="text", titulo="Tabelas de texto: re3_items (do EXE+mod) + mensagens EN/PT", src="iso", deps=[],
         cmds=[["re3_text.py", "--build-items"], ["re3_text.py", "--build-messages"]],
         out=["data/re3_items.json", "data/re3_messages.json"],
         doc="docs/decomp/notes/messages.md"),

    dict(id="scd_bytecode", titulo="Bytecode CRU do SCD + tabela de 144 opcodes (VM da F2)",
         src="iso", deps=[], cmds=[["scd_export.py"]],
         out=["data/STAGE*/R*.scd", "data/scd_opcodes.json", "data/scd_hist.json"],
         doc="docs/decomp/notes/scd_opcodes.md",
         nota="A VM do port executa os BYTES, não o resumo em JSON. O histograma por sala é o "
              "lado Python do diff do gate P2-10."),
    dict(id="sincos", titulo="Tabela sin/cos do EXE (ângulo de 12 bits)", src="iso", deps=[],
         cmds=[["exe_sincos.py"]], out=["data/ps1_sincos.json"], doc="docs/formatos/exe.md"),

    # ---------- imagem: backgrounds e UI ----------
    dict(id="bg_ps1", titulo="Backgrounds .BSS -> PNG 320x240 (2109)", src="iso", deps=[],
         cmds=[["bss2png.py", "--out", "{A}"]], glob_src=[paths.cd_data("STAGE*", "*.BSS")],
         out=["assets/STAGE*/*.png"], doc="docs/formatos/BSS.md"),
    dict(id="tim_etc", titulo="Telas/retratos .TIM de ETC -> PNG", src="iso", deps=[],
         cmds=[["tim2png.py", "{A}/ETC"]], glob_src=[paths.cd_data("ETC", "*.TIM")],
         out=["assets/ETC/*.png"], doc="docs/formatos/PLD.md"),
    dict(id="hd_map", titulo="Mapa autoritativo sala->assets HD (cache do REbirth)", src="hires",
         deps=[], cmds=[["hd_map_build.py"]], out=["data/hd_map.json"],
         doc="docs/formatos/hd_mapping.md"),
    dict(id="hd_bg", titulo="Backgrounds HD 1280x960 por câmera (substitui o PS1)", src="hires",
         deps=["hd_map", "bg_ps1"], cmds=[["hd_copy.py"]], out=["assets/STAGE*/*.webp"],
         doc="docs/formatos/hd_seamless.md"),
    dict(id="hd_masks", titulo="Máscaras de oclusão HD 2048² por câmera", src="hires",
         deps=["hd_map"], cmds=[["hd_masks.py"]], out=["assets/MASK/**/*.webp"],
         doc="docs/decomp/notes/occlusion.md"),
    dict(id="hd_fill", titulo="Completar cobertura HD por content-match (Método A)", src="hires",
         deps=["hd_bg"], cmds=[["hd_match.py", "--apply"]], out=[], slow=True,
         doc="docs/formatos/hd_seamless.md"),
    dict(id="ui_hd", titulo="De-para HD de UI/itens/memos", src="hires", deps=["tim_etc"],
         cmds=[["etc_hd_match.py", "--apply"]], out=["assets/UI/**/*"], doc="docs/formatos/hd_ui.md"),
    dict(id="menus", titulo="Gráficos das 13 telas de menu (catálogo por tela + HD)", src="iso",
         deps=["tim_etc"], cmds=[["menu_extract.py", "menu", "{A}/MENU"],
                                 ["menu_extract.py", "hdmatch", "{A}/MENU"]],
         out=["assets/MENU/**/*.png", "assets/MENU/**/*.webp"], doc="docs/decomp/notes/menus.md",
         nota="'menu_extract.py all' varre os overlays BIN e acha 0 TIM (o gráfico não está lá): "
              "as telas vêm dos atlas *_OBU/_BGU de ETC via cmd_menu + cmd_hdmatch."),
    dict(id="maps", titulo="Telas de mapa (MAP_U) + de-para HD", src="hires", deps=[],
         cmds=[["map_hd_match.py", "--emit"], ["map_clut_match.py", "--emit"],
               ["map_hd_locate.py", "--emit"]],
         out=["assets/MAP/*"], doc="docs/formatos/map.md"),

    # ---------- modelos ----------
    dict(id="pld", titulo="Personagens/armas PLD+PLW -> glb (110)", src="iso", deps=[],
         cmds=[["pld2gltf.py", "--all", "--plw"], ["pld2gltf.py", "--weapons-all"]],
         out=["assets/PLD/*.glb"], doc="docs/formatos/PLD.md",
         nota="--all sozinho converte só os .PLD (25). --plw inclui os 84 .PLW e --weapons-all "
              "extrai a malha separável da arma (*_WPN.glb)."),
    dict(id="pld_hd", titulo="Texturas HD nos modelos PLD", src="hires", deps=["pld"],
         cmds=[["pld_hd_textures.py", "--all", "--apply"]], out=[], doc="docs/formatos/PLD.md"),
    dict(id="doors3d", titulo="Modelos de porta .DO1-.DO7 -> glb (21)", src="iso", deps=[],
         cmds=[["do2gltf.py", "--all"], ["do2gltf.py", "--anim-all", "3"]],
         out=["assets/DOOR/*.glb"], doc="docs/decomp/notes/doors_model.md",
         nota="--all = folha estática; --anim-all = com a animação de abertura (*_ANIM.glb)."),
    dict(id="omodel", titulo="Objetos 3D de cenário do RDT -> glb (712 em 169 salas)", src="iso",
         deps=[], cmds=[["omodel2gltf.py", "--all", "--out", "{A}/OMODEL"]],
         out=["assets/OMODEL/*/*.glb"], doc="docs/formatos/ARD.md",
         nota="São os objetos que o opcode 0x7f instala — inclui a MALHA REAL do item no chão "
              "(o campo `om` do AOT de item indexa este mesmo diretório, offset_table[10])."),
    dict(id="rofs_emd", titulo="Extrair EMD de inimigo do Rofs9 (69 EMD + 69 TIM)", src="rofs",
         deps=[], cmds=[["rofs_extract.py", "{G}/Rofs9.dat", os.path.join(ROOT, "extracted", "pc", "rofs9")]],
         out=[], doc="docs/formatos/enemy_bin.md"),
    dict(id="enemies", titulo="Modelos de inimigo EMD -> glb (69)", src="rofs", deps=["rofs_emd"],
         cmds=[["emd2gltf.py", "batch", os.path.join(ROOT, "extracted", "pc", "rofs9"), "{A}/ENEMY"]],
         out=["assets/ENEMY/*.glb"], doc="docs/decomp/notes/enemy_mesh.md"),
    dict(id="enemy_catalog", titulo="Catálogo sala->mesh de inimigo (R###.BIN)", src="iso",
         deps=[], cmds=[["bin2gltf.py", "catalog", "{A}/ENEMY"]], out=["assets/ENEMY/catalog.json"],
         doc="docs/formatos/enemy_bin.md"),
    dict(id="scd_enemies", titulo="Spawns/espécie por sala (sce_em_set 0x7d)", src="iso",
         deps=["scd", "enemy_catalog"], cmds=[["scd_enemies.py"]], out=["data/sce_enemies.json"],
         doc="docs/decomp/notes/sce_em_set.md"),

    # ---------- áudio ----------
    dict(id="sfx", titulo="SFX dos bancos VAB (267) + mapa semântico", src="iso", deps=[],
         cmds=[["re3_sfx.py", "--all"], ["re3_sfx.py", "--map"]],
         out=["assets/SOUND/SFX/**/*.wav"], doc="docs/decomp/notes/sfx.md"),
    dict(id="bgm", titulo="Trilha: SoundFont do VAB real (re3.sf2)", src="iso", deps=[],
         cmds=[["re3_sound.py", "build"]], out=["assets/SOUND/BGM/re3.sf2"],
         doc="docs/formatos/audio_video.md"),

    # ---------- etapas que exigem ferramenta externa / decisão humana ----------
    dict(id="bgm_gog", titulo="Trilha do PC -> Ogg (125 faixas)", src="ptbr", deps=[],
         cmds=[["audio_gog.py", "--bgm"]], out=["assets/SOUND/BGM/gog/*.ogg"],
         doc="docs/formatos/localizacao_ptbr.md",
         nota="Fonte DATA_A/SOUND (PCM 22 kHz) -> Ogg Vorbis. É a trilha que o bgm_map.json "
              "referencia. Substitui a etapa manual de render por fluidsynth."),
    dict(id="xa_stage_audio", titulo="Ambiente/áudio XA por stage (16 por stage)", src="iso",
         deps=[], cmds=[], out=["assets/SOUND/STAGE*/*"], manual=True,
         nota="Sai do jPSXdec (setores Mode 2 Form 2); o extrator Python não lê streaming.",
         doc="docs/formatos/audio_video.md"),
    dict(id="ui_curated", titulo="UI curada (45 ícones HD + frame + texto)", src="hires", deps=["ui_hd"],
         cmds=[], out=["assets/UI/**/*.png"], manual=True,
         nota="Os 45 ícones e as peças de frame/texto foram identificados por render e recortados "
              "à mão (dívida do mesmo tipo do P0-11).",
         doc="docs/formatos/hd_ui.md"),
    dict(id="voices_en", titulo="Vozes EN dos Rofs*.dat", src="rofs", deps=[], cmds=[],
         out=["assets/VOICE/en/*"], manual=True,
         nota="Qual Rofs traz as vozes EN ainda não está fixado no pipeline; ver docs/formatos/rofs.md.",
         doc="docs/formatos/rofs.md"),
    dict(id="voices_ptbr", titulo="Vozes PT-BR dubladas (441 WAV -> Ogg)", src="ptbr", deps=[],
         cmds=[["audio_gog.py", "--voice"]], out=["assets/VOICE/ptbr/*.ogg"],
         doc="docs/formatos/localizacao_ptbr.md",
         nota="DATA_A/VOICE: 441 WAV sem recompressão -> Ogg (310 MB viram uma fração)."),
    dict(id="fmv", titulo="FMV HD (14 mp4 1280x960) -> Ogg Theora", src="ptbr", deps=[], cmds=[],
         out=["assets/ZMOVIE/*.ogv"], manual=True,
         nota="Reencode com tools/ffmpeg; bitrate a definir (P6-05). Os mp4 são dublados PT-BR.",
         doc="docs/formatos/audio_video.md"),
    dict(id="ptbr_text", titulo="Tabelas de texto PT-BR do mod (17 xml + 129 por sala)", src="ptbr",
         deps=[], cmds=[], out=["data/ptbr_text.json"], manual=True,
         nota="Fonte identificada e medida; conversor ainda não escrito (P6-11).",
         doc="docs/formatos/localizacao_ptbr.md"),
]

BY_ID = {s["id"]: s for s in STAGES}


def expand(tok, out):
    return (tok.replace("{A}", os.path.join(ROOT, out, "assets"))
               .replace("{D}", os.path.join(ROOT, out, "data"))
               .replace("{G}", gog_root())
               .replace("{H}", hires_root()))


def count_out(stage, out):
    n = 0
    for pat in stage.get("out", []):
        n += len(glob.glob(os.path.join(ROOT, out, pat), recursive=True))
    return n


def resolve(only, no_deps):
    """Ordena topologicamente e inclui dependências (a menos que --no-deps)."""
    want = [s["id"] for s in STAGES] if not only else list(only)
    for i in want:
        if i not in BY_ID:
            sys.exit(f"etapa desconhecida: {i}\netapas: {', '.join(BY_ID)}")
    if not no_deps:
        seen = set()

        def add(i):
            if i in seen:
                return
            seen.add(i)
            for d in BY_ID[i]["deps"]:
                add(d)
        for i in want:
            add(i)
        want = [s["id"] for s in STAGES if s["id"] in seen]     # ordem canônica
    return [BY_ID[i] for i in want]


def cmd_list(out):
    print(f"destino: {os.path.join(ROOT, out)}\n")
    print("fontes de entrada:")
    for k, (desc, fn) in SOURCES.items():
        print(f"  [{'ok' if fn() else '--'}] {k:6} {desc}")
    print(f"\n{'etapa':14} {'fonte':6} {'deps':28} {'arq.':>6}  título")
    for s in STAGES:
        ok = SOURCES[s["src"]][1]()
        tag = "MANUAL" if s.get("manual") else ("" if ok else "s/fonte")
        print(f"  {s['id']:14} {s['src']:6} {','.join(s['deps'])[:28]:28} "
              f"{count_out(s, out):6}  {s['titulo']}" + (f"   <{tag}>" if tag else ""))
    print("\n<MANUAL> = não roda sozinha (ferramenta externa/decisão humana), ver nota em --list -v")
    if "-v" in sys.argv:
        for s in STAGES:
            if s.get("nota"):
                print(f"  {s['id']}: {s['nota']}")


def manifest_path(out):
    return os.path.join(ROOT, out, "data", "asset_manifest.json")


def cmd_manifest(out):
    """P0-03: manifesto do que existe (caminho relativo + tamanho + mtime-agnóstico)."""
    base = os.path.join(ROOT, out)
    entries, total = {}, 0
    for sub in ("assets", "data"):
        d = os.path.join(base, sub)
        for r, _dd, fs in os.walk(d):
            for f in fs:
                if f.endswith((".import", ".uid")) or f == "asset_manifest.json":
                    continue
                p = os.path.join(r, f)
                rel = os.path.relpath(p, base).replace("\\", "/")
                entries[rel] = os.path.getsize(p)
                total += entries[rel]
    per_stage = {s["id"]: count_out(s, out) for s in STAGES}
    man = {"_meta": {"out": out, "n_files": len(entries), "bytes": total,
                     "gerado_por": "tools/build_assets.py --manifest",
                     "nota": ("inventário do que o pipeline produziu; NÃO contém asset nenhum. "
                              "Serve para o verificador (--verify) e para a política 'traga sua "
                              "própria cópia' (P7-06).")},
           "por_etapa": per_stage, "arquivos": entries}
    os.makedirs(os.path.dirname(manifest_path(out)), exist_ok=True)
    json.dump(man, open(manifest_path(out), "w", encoding="utf-8"), indent=1)
    print(f"manifesto: {len(entries)} arquivos, {total/1e6:.1f} MB -> {manifest_path(out)}")
    return 0


def cmd_verify(out):
    mp = manifest_path(out)
    if not os.path.isfile(mp):
        print(f"sem manifesto em {mp} — rode --manifest primeiro")
        return 1
    man = json.load(open(mp, encoding="utf-8"))
    base = os.path.join(ROOT, out)
    falt, difer = [], []
    for rel, size in man["arquivos"].items():
        p = os.path.join(base, rel.replace("/", os.sep))
        if not os.path.isfile(p):
            falt.append(rel)
        elif os.path.getsize(p) != size:
            difer.append(rel)
    print(f"verificação de {len(man['arquivos'])} arquivos: "
          f"{len(falt)} faltando, {len(difer)} com tamanho diferente")
    for r in falt[:10]:
        print("  FALTA  ", r)
    for r in difer[:10]:
        print("  DIFERE ", r)
    return 0 if not (falt or difer) else 1


def do_seed(out, dry):
    """Copia o resíduo honesto (hd_ui_map.json) — NÃO reproduzível estaticamente. Os outros
    5 JSON antes-sementes agora são GERADOS (etapas ai_overlays/physics/anim_map/scd_items/text)."""
    import shutil
    src_dir = os.path.join(ROOT, "godot", "data")
    dst_dir = os.path.join(ROOT, out, "data")
    os.makedirs(dst_dir, exist_ok=True)
    falt = []
    for f, porque in SEEDS:
        s, d = os.path.join(src_dir, f), os.path.join(dst_dir, f)
        if not os.path.isfile(s):
            falt.append(f)
            continue
        print(f"    SEED {f:20} {porque}")
        if not dry:
            shutil.copy2(s, d)
    if falt:
        print(f"[FALHA] seed: ausentes em godot/data: {falt}")
        return "falha"
    print(f"[seed] {len(SEEDS)} resíduo(s) copiado(s) — P0-11: hd_ui_map.json não é reproduzível "
          f"estaticamente (requer dump do plugin bio3hd). Os outros 5 JSON são GERADOS.")
    return "ok"


def run(stage, out, dry, keep_going):
    if stage.get("manual"):
        print(f"[MANUAL] {stage['id']}: {stage['titulo']}")
        if stage.get("nota"):
            print(f"          {stage['nota']}")
        return "manual"
    if not SOURCES[stage["src"]][1]():
        print(f"[SEM FONTE] {stage['id']}: precisa de '{stage['src']}' "
              f"({SOURCES[stage['src']][0]})")
        return "sem_fonte"
    # PYTHONIOENCODING: a saída das ferramentas chega em UTF-8 limpo (sem U+FFFD)
    env = dict(os.environ, NOSTALGIA_OUT=out, PYTHONIOENCODING="utf-8")
    t0 = time.time()
    if stage["cmds"] == ["@seed"]:               # etapa interna, não é subprocesso
        return do_seed(out, dry)
    for argv in stage["cmds"]:
        cmd = [PY, os.path.join(ROOT, "tools", argv[0])] + [expand(a, out) for a in argv[1:]]
        for pat in stage.get("glob_src", []):
            got = sorted(glob.glob(pat))
            if not got:
                print(f"[FALHA] {stage['id']}: nenhum arquivo em {pat}")
                return "falha"
            cmd += got
        shown = " ".join(os.path.basename(c) if i == 1 else c for i, c in enumerate(cmd[:6]))
        print(f"[{stage['id']}] {shown}{' ...' if len(cmd) > 6 else ''}")
        if dry:
            continue
        p = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        if p.returncode != 0:
            print(f"[FALHA] {stage['id']} (exit {p.returncode}) — últimas linhas:")
            for l in (p.stdout or "").splitlines()[-8:]:
                print("   ", l)
            for l in (p.stderr or "").splitlines()[-8:]:
                print("  !", l)
            if not keep_going:
                return "falha"
            return "falha"
        tail = [l for l in (p.stdout or "").splitlines() if l.strip()][-2:]
        for l in tail:
            print("   ", l[:150])
    print(f"[{stage['id']}] OK em {time.time()-t0:.1f}s  ({count_out(stage, out)} arquivos)")
    return "ok"


def main(argv):
    a = argv[1:]
    out = a[a.index("--out") + 1] if "--out" in a else paths.name()
    only = None
    if "--only" in a:
        only = [x.strip() for x in a[a.index("--only") + 1].split(",") if x.strip()]
    dry = "--dry-run" in a
    keep = "--continue-on-error" in a
    no_deps = "--no-deps" in a

    if "--list" in a:
        cmd_list(out)
        return 0
    if "--manifest" in a:
        return cmd_manifest(out)
    if "--verify" in a:
        return cmd_verify(out)

    stages = resolve(only, no_deps)
    print(f"destino: {os.path.join(ROOT, out)}   etapas: {len(stages)}"
          f"{'  (DRY-RUN)' if dry else ''}\n")
    res = {}
    for s in stages:
        res[s["id"]] = run(s, out, dry, keep)
        if res[s["id"]] == "falha" and not keep:
            print("\ninterrompido (use --continue-on-error para seguir)")
            break
    print("\n== resumo ==")
    for k, v in res.items():
        print(f"  {v:10} {k}")
    ok = sum(1 for v in res.values() if v == "ok")
    print(f"{ok}/{len(res)} etapas ok · "
          f"{sum(1 for v in res.values() if v == 'manual')} manuais · "
          f"{sum(1 for v in res.values() if v == 'sem_fonte')} sem fonte · "
          f"{sum(1 for v in res.values() if v == 'falha')} falhas")
    return 1 if any(v == "falha" for v in res.values()) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
