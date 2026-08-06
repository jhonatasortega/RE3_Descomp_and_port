class_name Clock
extends Node
## Relógio de gameplay: 30 Hz FIXO, desacoplado do render (P0-04).
##
## O RE3 do PS1 mostra 60 Hz de vídeo mas processa **gameplay a 30 fps** — confirmado pela
## frame-list do EDD (cada registro tem `nframes` = frames de JOGO; o andar `anim00` são 34
## frames = 34 poses = 1,133 s). Fonte: data/physics.json (`fps`), docs/formatos/exe.md.
##
## Consequência prática: TODA constante que a decomp mediu (velocidade por frame, giro por
## frame, frames de recuo, timing de tiro) é por-frame de 30. Se o passo variar com o FPS de
## render, nada disso fecha e o port deixa de ser 1:1.
##
## Implementação: **acumulador de tempo com passo fixo** em `_process`.
##
## A primeira versão usava `_physics_process` com `max_physics_steps_per_frame = 1`. **Medi e
## estava errado:** em 180 quadros renderizados (~5,5 s a 33 fps) o gameplay avançou só **39
## ticks** em vez de ~165 — ou seja, rodava a ~7 Hz e a personagem parecia travada. O limite
## de 1 passo por quadro também ACOPLA o gameplay ao render, exatamente o que este relógio
## existe para evitar.
##
## O acumulador resolve as duas coisas: cada passo continua sendo exatamente 1/30 (portanto
## determinístico e compatível com as constantes por-frame da decomp), e quantos passos rodam
## por quadro depende do tempo real decorrido. `MAX_CATCHUP` limita a recuperação depois de um
## engasgo, para não processar um segundo inteiro de golpe.
##
## Determinismo: nada de `delta` na lógica — quem precisa de tempo conta TICKS.
## `step()` é público para o harness headless rodar N ticks sem depender do render (P0-09).

signal ticked(frame: int)

const HZ := 30
const DT := 1.0 / float(HZ)

var frame: int = 0          ## nº de ticks de gameplay desde o início
var paused: bool = false


## Máximo de passos por quadro na recuperação (evita "engasgo" virar avanço gigante).
const MAX_CATCHUP := 8

var _acumulador := 0.0
var passos_no_quadro := 0        ## diagnóstico: quantos ticks rodaram no último quadro
var chamadas := 0                ## diagnóstico: quantas vezes _process foi chamado
var soma_delta := 0.0            ## diagnóstico: tempo total visto pelo relógio


func _process(delta: float) -> void:
	if paused:
		return
	chamadas += 1
	soma_delta += delta
	_acumulador += delta
	passos_no_quadro = 0
	while _acumulador >= DT and passos_no_quadro < MAX_CATCHUP:
		step()
		_acumulador -= DT
		passos_no_quadro += 1
	if _acumulador > DT * float(MAX_CATCHUP):
		_acumulador = 0.0        ## ficou muito atrás (pausa/carregamento): não acumula dívida


func step() -> void:
	## Avança exatamente 1 tick de gameplay (30 Hz). Chamável pelo harness de teste.
	frame += 1
	ticked.emit(frame)


func step_n(n: int) -> void:
	for _i in n:
		step()


func seconds() -> float:
	## Tempo de jogo decorrido, derivado do nº de ticks (nunca do relógio de parede).
	return float(frame) * DT


func frames_for(seconds_f: float) -> int:
	## Converte segundos em ticks de gameplay (para tempos vindos de vídeo/medição).
	return int(round(seconds_f * float(HZ)))


func reset() -> void:
	frame = 0
	_acumulador = 0.0
