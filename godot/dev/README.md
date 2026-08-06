# godot/dev — harnesses de render/validação

Scripts `tools_*.gd` (SceneTree) usados para **renderizar/validar** modelos, animações,
câmera e composição — fora do jogo. Saídas PNG são temporárias (apagar após usar).

## ⚠️ Como rodar a Godot com EFICIÊNCIA (regra do projeto)

**NUNCA abra em modo EDITOR** para render/validação (desperdiça recurso: sobe a IDE +
reimporta o projeto inteiro). Ou seja, **não** use `godot --path godot` sozinho nem `-e`.

**Render (modo cena/script — SceneTree):**
```
"<godot>" --path godot --rendering-driver opengl3 --script res://dev/<harness>.gd
```
- `--script` executa o SceneTree direto (modo cena, sem editor).
- `--rendering-driver opengl3` é obrigatório p/ renderizar (headless = driver dummy, NÃO renderiza).
- Passe parâmetros por env (ex.: `MODEL=res://... VIEW=side ONLY=anim00 OUT=res://dev/x`).

**Validar só import/parse (sem render — o mais leve):**
```
"<godot>" --headless --path godot --quit-after 2
```
(carrega o projeto, roda 2 frames, sai; pega erros de script sem abrir janela.)

## Regra de OURO: 1 launch, muitos itens
Subir a Godot é caro (reimport). Para renderizar N modelos/animações, faça **UM harness
que itera dentro do MESMO processo** (loop no `_process`), salvando um montage/tira — e
**não** relance a Godot por item. Ex.: montage do bestiário = 1 launch p/ os 69 `.glb`.

## Binário
Steam: `/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`
(é o build "tools"; use sempre com `--script` ou `--headless`, nunca sozinho).
