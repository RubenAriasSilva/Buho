extends Node
## IA del rival en tiempo real: se acerca con algo de desvío lateral, golpea
## cuando está en alcance, a veces se cubre si el jugador está cerca y con
## Impacto alto a veces retrocede.

const Personaje = preload("res://scripts/personaje.gd")
const Combate = preload("res://scripts/combate.gd")
const Golpe = preload("res://scripts/golpe.gd")

@export var npc: Personaje
@export var jugador: Personaje
@export var combate: Combate

## Segundos entre decisiones (mínimo, máximo).
@export var intervalo := Vector2(0.25, 0.5)
## Probabilidad de golpear cuando está en alcance y puede.
@export_range(0.0, 1.0) var prob_golpear := 0.7
## Probabilidad de cubrirse en cada decisión con el jugador cerca.
@export_range(0.0, 1.0) var prob_cubrirse := 0.25
@export var duracion_cubrirse := 0.5
## Distancia a la que considera que el jugador está "cerca".
@export var distancia_cerca := 1.6
## Con Impacto mayor a este, a veces retrocede.
@export var impacto_retroceder := 150.0
@export_range(0.0, 1.0) var prob_retroceder := 0.3
## Desvío lateral máximo al acercarse (0 = directo).
@export var desvio_lateral := 0.5

var _tiempo := 0.0
var _proxima_decision := 0.0
var _cubrir_hasta := 0.0
var _dir := Vector3.ZERO


func _process(delta: float) -> void:
	_tiempo += delta
	if _tiempo >= _proxima_decision:
		_decidir()
		_proxima_decision = _tiempo + randf_range(intervalo.x, intervalo.y)
	npc.cubrirse(_tiempo < _cubrir_hasta)
	npc.mover(_dir, delta)


func _decidir() -> void:
	var hacia := jugador.global_position - npc.global_position
	hacia.y = 0.0
	var d := hacia.length()
	var frente := hacia / d if d > 0.001 else Vector3.FORWARD

	if d < distancia_cerca and _tiempo >= _cubrir_hasta and randf() < prob_cubrirse:
		_cubrir_hasta = _tiempo + duracion_cubrirse
		_dir = Vector3.ZERO
		return

	var golpe := _golpe_en_alcance(d)
	if golpe != null and randf() < prob_golpear:
		npc.intentar_golpe(golpe)
		_dir = Vector3.ZERO
		return

	if npc.impacto > impacto_retroceder and randf() < prob_retroceder:
		_dir = -frente
		return

	if d > 0.9:
		var lado := Vector3(-frente.z, 0.0, frente.x) * randf_range(-desvio_lateral, desvio_lateral)
		_dir = (frente + lado).normalized()
	else:
		_dir = Vector3.ZERO


## Un golpe al azar que alcance desde la distancia `d` y que pueda pagar ya.
func _golpe_en_alcance(d: float) -> Golpe:
	if npc.fraccion_recarga() > 0.0:
		return null
	var opciones: Array[Golpe] = []
	for golpe in combate.golpes:
		if d <= golpe.alcance and npc.energia >= golpe.costo:
			opciones.append(golpe)
	return opciones.pick_random() if not opciones.is_empty() else null
