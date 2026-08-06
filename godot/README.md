# Projeto Godot — Nostalgia (RE3)

Protótipo/remake do Resident Evil 3 no Godot 4.

## Regra de estrutura (rastreabilidade)

As pastas de assets **espelham o disco** (`CD_DATA`), para casar cada asset com sua origem:

```
godot/
├─ project.godot
├─ scenes/room_viewer.tscn   # cena principal (background + câmera fixa)
├─ scripts/room_viewer.gd
├─ assets/                    # convertidos p/ formatos abertos (GITIGNORED — copyright)
│  ├─ ETC/      *.png         # logos, telas, retratos (de .TIM)
│  ├─ STAGE1..7/ *.png        # backgrounds de sala (de .BSS)
│  ├─ PLD/      *.glb         # modelos (de .PLD/.PLW)
│  ├─ SOUND/    *.wav/.ogg    # música/SFX
│  ├─ VOICE/    *.wav/.ogg    # vozes
│  └─ ZMOVIE/   *.avi/.ogv    # FMVs
└─ data/                      # dados de sala (de .ARD -> JSON) (GITIGNORED)
   └─ STAGE1..7/ *.json
```

## Como abrir

1. Abrir o Godot 4 (versão Steam serve).
2. **Import** → selecionar `godot/project.godot`.
3. Rodar a cena `room_viewer.tscn` (F5). Deve mostrar o background do beco de Raccoon City.

> Os assets são gerados pelos scripts em `../tools/` a partir da sua cópia do jogo.
> Sem eles, a cena abre sem imagem (o `.png` referenciado precisa existir).

## Próximos passos

- Trocar o background por uma sala real (`assets/STAGE1/...`) quando o decoder de `.BSS` sair.
- Adicionar máscara de profundidade (personagem passa atrás de objetos do cenário).
- Personagem + colisão a partir dos dados de `data/STAGE*/*.json`.
- Evoluir para câmera livre 3D (v2).
