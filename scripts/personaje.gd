extends Node3D
## Luchador en tiempo real (por ahora un cilindro): se mueve libre, lanza golpes,
## se cubre y recibe golpes. La energía se regenera cada segundo según su
## Medidor de Impacto. Quién conecta y cuánto empuja lo resuelve Combate.

const Golpe = preload("res://scripts/golpe.gd")

signal energia_cambiada(actual: int, maxima: int)
signal impacto_cambiado(impacto: float)
## Se emite al lanzar un golpe (ya pagado); Combate decide si conecta.
signal golpe_lanzado(golpe: Golpe)

@export var nombre := "Búho"
@export var color := Color(0.95, 0.75, 0.2)
@export var celda_inicial := Vector2i(3, 5)

@export_group("Energía")
@export var energia_max := 30
## Energía por segundo según su Impacto: [hasta %, energía/s].
## Por encima del último límite se usa `regen_minima`.
@export var regen_por_impacto: Array[Vector2] = [Vector2(50, 2.5), Vector2(150, 1.5), Vector2(200, 1.0)]
@export var regen_minima := 0.5
@export var costo_cubrirse_por_segundo := 2.0

@export_group("Movimiento")
## Metros por segundo.
@export var velocidad := 3.0
## Multiplicador de velocidad mientras se cubre.
@export var factor_velocidad_cubierto := 0.35
## Radio del cuerpo (para límites del ring y separación).
@export var radio := 0.3
## Cuánto se inclina hacia adelante al avanzar (radianes; 0 lo desactiva).
@export var inclinacion_al_correr := 0.15

@export_group("Impacto")
@export var impacto_max := 300.0

var energia := 0.0
var impacto := 0.0
var cubriendose := false

var _aturdido := 0.0
var _recarga := 0.0
var _recarga_total := 1.0
var _empujado := false
var _energia_mostrada := -1
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	$Cuerpo.material_override = _material
	energia = energia_max


func _process(delta: float) -> void:
	_aturdido = maxf(_aturdido - delta, 0.0)
	_recarga = maxf(_recarga - delta, 0.0)
	if cubriendose:
		energia -= costo_cubrirse_por_segundo * delta
		if energia <= 0.0:
			energia = 0.0
			cubrirse(false)
	else:
		energia = minf(energia + energia_por_segundo() * delta, energia_max)
	_avisar_energia()


## Energía que recupera por segundo según su Medidor de Impacto.
func energia_por_segundo() -> float:
	for tramo in regen_por_impacto:
		if impacto <= tramo.x:
			return tramo.y
	return regen_minima


func energia_entera() -> int:
	return floori(energia)


func puede_actuar() -> bool:
	return _aturdido <= 0.0 and not _empujado


## Fracción de la recarga que falta (1 = recién golpeó, 0 = listo).
func fraccion_recarga() -> float:
	return _recarga / _recarga_total if _recarga_total > 0.0 else 0.0


## Mueve en la dirección `dir` (en el mundo, sobre el piso; largo <= 1).
## Los límites del ring los aplica Combate.
func mover(dir: Vector3, delta: float) -> void:
	if not puede_actuar() or dir.length() < 0.01:
		rotation = rotation.lerp(Vector3.ZERO, minf(delta * 10.0, 1.0))
		return
	var v := velocidad * (factor_velocidad_cubierto if cubriendose else 1.0)
	global_position += dir.limit_length(1.0) * v * delta
	var inclinacion := Vector3(dir.z, 0.0, -dir.x).normalized() * inclinacion_al_correr * minf(dir.length(), 1.0)
	rotation = rotation.lerp(inclinacion, minf(delta * 10.0, 1.0))


## Paga y lanza un golpe si puede. Devuelve false si no tenía energía, estaba
## en recarga, cubierto o aturdido.
func intentar_golpe(golpe: Golpe) -> bool:
	if not puede_actuar() or cubriendose or _recarga > 0.0 or energia < golpe.costo:
		return false
	energia -= golpe.costo
	_recarga = golpe.recarga
	_recarga_total = golpe.recarga
	_avisar_energia()
	golpe_lanzado.emit(golpe)
	return true


func cubrirse(activo: bool) -> void:
	if activo and (energia <= 0.0 or not puede_actuar()):
		activo = false
	if activo == cubriendose:
		return
	cubriendose = activo
	var t := create_tween().set_parallel()
	t.tween_property(self, "scale", Vector3(1.1, 0.8, 1.1) if activo else Vector3.ONE, 0.1)
	t.tween_property(_material, "albedo_color", color.lightened(0.45) if activo else color, 0.1)


## Recibe un golpe ya calculado por Combate: suma `cantidad` de Impacto, queda
## aturdido `aturdimiento` segundos y se desliza hasta `destino`.
func recibir_golpe(cantidad: float, destino: Vector3, aturdimiento: float) -> void:
	cambiar_impacto(cantidad)
	_aturdido = maxf(_aturdido, aturdimiento)
	var base := color.lightened(0.45) if cubriendose else color
	var destello := create_tween()
	destello.tween_property(_material, "albedo_color", Color.WHITE, 0.04)
	destello.tween_property(_material, "albedo_color", base, 0.2)
	if destino.distance_to(global_position) > 0.01:
		_empujado = true
		var t := create_tween()
		t.tween_property(self, "global_position", destino, 0.12 + 0.1 * destino.distance_to(global_position)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await t.finished
		_empujado = false


## Suma (o resta) Impacto directamente.
func cambiar_impacto(cantidad: float) -> void:
	impacto = clampf(impacto + cantidad, 0.0, impacto_max)
	impacto_cambiado.emit(impacto)


## Pequeña embestida del cuerpo hacia `dir` (en el mundo) para mostrar el golpe.
func golpear(dir: Vector3) -> void:
	var cuerpo: Node3D = $Cuerpo
	var reposo := Vector3(0, 0.6, 0)
	var t := create_tween()
	t.tween_property(cuerpo, "position", reposo + dir * 0.3, 0.07).set_ease(Tween.EASE_OUT)
	t.tween_property(cuerpo, "position", reposo, 0.12).set_ease(Tween.EASE_IN)
	await t.finished


func _avisar_energia() -> void:
	var entera := energia_entera()
	if entera != _energia_mostrada:
		_energia_mostrada = entera
		energia_cambiada.emit(entera, energia_max)
