extends Node3D
## Luchador (por ahora un cilindro). Guarda su estado de combate (energía,
## Medidor de Impacto, mano de cartas) y anima sus acciones.
## Las funciones de acción son corrutinas: usar `await`.

const Carta = preload("res://scripts/carta.gd")
const Mazo = preload("res://scripts/mazo.gd")

signal energia_cambiada(actual: int, maxima: int)
signal impacto_cambiado(impacto: float)
signal cartas_cambiadas

const TAM_MANO := 3

@export var nombre := "Búho"
@export var color := Color(0.95, 0.75, 0.2)
@export var celda_inicial := Vector2i(3, 5)

@export_group("Energía")
@export var energia_max := 30
## Energía que recibe al iniciar su turno según su Impacto: [hasta %, energía].
## El último valor aplica por encima del último límite.
@export var regen_por_impacto: Array[Vector2] = [Vector2(50, 5), Vector2(150, 3), Vector2(200, 2)]
@export var regen_minima := 1

@export_group("Impacto")
@export var impacto_max := 300.0

@export_group("Animación")
## Segundos por casilla recorrida.
@export var duracion_paso := 0.15
@export var duracion_poste := 0.45
@export var duracion_salto := 0.6
@export var altura_salto := 1.5
## Cuánto se inclina hacia adelante al avanzar (radianes; 0 lo desactiva).
@export var inclinacion_al_correr := 0.15

var celda := Vector2i.ZERO
var energia := 0
var impacto := 0.0
var en_poste := false
## Corriendo las cuerdas: va hacia la cuerda en `dir_cuerdas` y su siguiente
## tramo después del rebote mide `recorrido_cuerdas` casillas.
var en_cuerdas := false
var recorrido_cuerdas := 0.0
var dir_cuerdas := Vector2.ZERO

## Mano de cartas (puede tener huecos `null`) y carta armada en la zona de juego.
var mano: Array[Carta] = [null, null, null]
var carta_en_juego: Carta
var bloqueo_activo := false

var _material: StandardMaterial3D
var _segmento := 0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	$Cuerpo.material_override = _material
	energia = energia_max


## Energía que recupera al iniciar su turno según su Medidor de Impacto.
func energia_por_turno() -> int:
	for tramo in regen_por_impacto:
		if impacto <= tramo.x:
			return int(tramo.y)
	return regen_minima


func regenerar_turno() -> void:
	ganar_energia(energia_por_turno())


func energia_entera() -> int:
	return energia


func ganar_energia(cantidad: int) -> void:
	energia = clampi(energia + cantidad, 0, energia_max)
	energia_cambiada.emit(energia, energia_max)


func gastar_energia(cantidad: int) -> void:
	ganar_energia(-cantidad)


## Suma impacto (negativo para reducirlo). El Bloqueo reduce a la mitad el siguiente golpe.
func recibir_impacto(cantidad: float) -> void:
	if cantidad > 0.0 and bloqueo_activo:
		cantidad *= 0.5
		bloqueo_activo = false
	impacto = clampf(impacto + cantidad, 0.0, impacto_max)
	impacto_cambiado.emit(impacto)


func rellenar_mano(mazo: Mazo) -> void:
	for i in TAM_MANO:
		if mano[i] == null:
			mano[i] = mazo.robar()
	cartas_cambiadas.emit()


## Mueve la carta `i` de la mano a la zona de juego (intercambia si ya había una).
func armar_carta(i: int) -> void:
	var anterior := carta_en_juego
	carta_en_juego = mano[i]
	mano[i] = anterior
	cartas_cambiadas.emit()


## Regresa la carta de la zona de juego a la mano (al hueco `i`, o al primero libre).
func desarmar_carta(i := -1) -> void:
	if carta_en_juego == null:
		return
	if i < 0:
		i = mano.find(null)
	if i < 0:
		return
	var en_mano := mano[i]
	mano[i] = carta_en_juego
	carta_en_juego = en_mano
	cartas_cambiadas.emit()


func gastar_carta_en_juego() -> void:
	carta_en_juego = null
	cartas_cambiadas.emit()


func salir_de_cuerdas() -> void:
	en_cuerdas = false
	recorrido_cuerdas = 0.0
	dir_cuerdas = Vector2.ZERO


## Recorre una línea quebrada (en el mundo) con un solo movimiento continuo.
## `suave`: acelera al salir y frena al llegar (caminar, salir de las cuerdas);
## si no, va a velocidad constante (rebotes). Se aplasta al cruzar cada punto
## intermedio, que son las cuerdas.
func recorrer(puntos: Array[Vector3], tam_casilla: float, suave := false) -> void:
	var vertices: Array[Vector3] = [global_position]
	vertices.append_array(puntos)
	var acumulado: Array[float] = [0.0]
	for i in range(1, vertices.size()):
		acumulado.append(acumulado[-1] + vertices[i - 1].distance_to(vertices[i]))
	var total := acumulado[-1]
	if total < 0.001:
		return
	_segmento = 0
	var t := create_tween()
	t.tween_method(_avanzar_en_linea.bind(vertices, acumulado), 0.0, total,
		maxf(total / tam_casilla * duracion_paso, 0.2))
	if suave:
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	create_tween().tween_property(self, "rotation", Vector3.ZERO, 0.15)


func ser_empujado(camino: Array[Vector3]) -> void:
	en_poste = false
	salir_de_cuerdas()
	var t := create_tween()
	t.tween_property(_material, "albedo_color", Color.WHITE, 0.05)
	t.tween_property(_material, "albedo_color", color, 0.25)
	if not camino.is_empty():
		var t2 := create_tween()
		t2.tween_property(self, "global_position", camino[-1], 0.12 + 0.08 * camino.size()) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await t2.finished
	else:
		await t.finished


## Pequeña embestida hacia `dir` (en el mundo) para mostrar el golpe.
func golpear(dir: Vector3) -> void:
	var origen := global_position
	var t := create_tween()
	t.tween_property(self, "global_position", origen + dir * 0.35, 0.08).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", origen, 0.14).set_ease(Tween.EASE_IN)
	await t.finished


func subir_poste(punto: Vector3) -> void:
	await _arco_hacia(punto, 0.4, duracion_poste)
	en_poste = true


func saltar_desde_poste(destino: Vector3) -> void:
	await _arco_hacia(destino, altura_salto, duracion_salto)
	en_poste = false


func _avanzar_en_linea(d: float, vertices: Array[Vector3], acumulado: Array[float]) -> void:
	var i := 1
	while i < acumulado.size() - 1 and d > acumulado[i]:
		i += 1
	if i - 1 > _segmento:
		_segmento = i - 1
		_aplastar()
	var largo := acumulado[i] - acumulado[i - 1]
	var k := (d - acumulado[i - 1]) / largo if largo > 0.0 else 1.0
	global_position = vertices[i - 1].lerp(vertices[i], k)
	var dir := (vertices[i] - vertices[i - 1]).normalized()
	rotation = Vector3(dir.z, 0.0, -dir.x) * inclinacion_al_correr


func _aplastar() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(1.25, 0.8, 1.25), 0.06)
	t.tween_property(self, "scale", Vector3.ONE, 0.1)


func _arco_hacia(destino: Vector3, altura: float, duracion: float) -> void:
	var origen := global_position
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		global_position = origen.lerp(destino, k) + Vector3.UP * sin(k * PI) * altura,
		0.0, 1.0, duracion)
	await t.finished
