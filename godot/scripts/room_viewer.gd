extends Node2D
## Visualizador de sala no estilo RE clássico:
## background pré-renderizado 2D + câmera fixa.
## É o protótipo base; depois evolui para a v2 3D (câmera livre).

## Textura de background da sala (um dos PNGs extraídos).
@export var background: Texture2D

func _ready() -> void:
	if background != null:
		$Background.texture = background
	# 320x240 = resolução nativa do PS1
	$Background.centered = false
