extends Resource
## Conjunto de cartas del que se roba al azar para rellenar la mano.

const Carta = preload("res://scripts/carta.gd")

@export var cartas: Array[Carta] = []


func robar() -> Carta:
	return cartas.pick_random() if not cartas.is_empty() else null
