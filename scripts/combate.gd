extends Node
## Combate en tiempo real: reloj de la partida, límites del ring, separación
## entre luchadores y resolución de golpes (alcance, cubrirse, Impacto y empuje).

const Tablero = preload("res://scripts/tablero.gd")
const Personaje = preload("res://scripts/personaje.gd")
const Hud = preload("res://scripts/hud.gd")
const Golpe = preload("res://scripts/golpe.gd")

@export var tablero: Tablero
@export var jugador: Personaje
@export var npc: Personaje
@export var hud: Hud
## Golpes disponibles, en el orden de los botones (Manotazo, Puñetazo, Patada).
@export var golpes: Array[Golpe] = []

@export_group("Golpes")
## Fracción del Impacto que recibe quien está cubierto (y no sale empujado).
@export_range(0.0, 1.0) var factor_cubierto := 0.25
## Segundos sin poder actuar tras recibir un golpe.
@export var aturdimiento := 0.3
@export var aturdimiento_cubierto := 0.1

@export_group("Empuje")
## Casillas que sale empujado según su Impacto (ya con el golpe): [hasta %, casillas].
## Por encima del último límite se usa `empuje_maximo`.
@export var empuje_por_impacto: Array[Vector2] = [Vector2(50, 0), Vector2(150, 1), Vector2(200, 2)]
@export var empuje_maximo := 3

@export_group("Depuración")
## 1: +25% de Impacto al jugador, 2: al rival, 0: reinicia ambos.
@export var teclas_debug := true

var tiempo_partida := 0.0


func _ready() -> void:
	for luchador in [jugador, npc]:
		luchador.global_position = tablero.celda_a_mundo(luchador.celda_inicial)
		luchador.golpe_lanzado.connect(_on_golpe_lanzado.bind(luchador))
	hud.configurar(jugador, npc, tablero, golpes)
	hud.mostrar_tiempo(0.0)


func _process(delta: float) -> void:
	tiempo_partida += delta
	hud.mostrar_tiempo(tiempo_partida)
	_separar(jugador, npc)
	for luchador in [jugador, npc]:
		luchador.global_position = limitar_al_ring(luchador.global_position, luchador.radio)


func _unhandled_key_input(event: InputEvent) -> void:
	if not teclas_debug or not event.is_pressed():
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			jugador.cambiar_impacto(25.0)
		KEY_2:
			npc.cambiar_impacto(25.0)
		KEY_0:
			jugador.cambiar_impacto(-jugador.impacto)
			npc.cambiar_impacto(-npc.impacto)


func rival_de(luchador: Personaje) -> Personaje:
	return npc if luchador == jugador else jugador


## Casillas que sale empujado un luchador con este Impacto.
func casillas_empuje(impacto: float) -> int:
	for tramo in empuje_por_impacto:
		if impacto <= tramo.x:
			return int(tramo.y)
	return empuje_maximo


## Distancia sobre el piso entre dos luchadores.
func distancia(a: Personaje, b: Personaje) -> float:
	return _plano(b.global_position - a.global_position).length()


## Mantiene un punto dentro de la zona jugable del ring (a `margen` de la orilla).
func limitar_al_ring(p: Vector3, margen: float) -> Vector3:
	var mitad_x := tablero.columnas * tablero.tam_casilla / 2.0 - margen
	var mitad_z := tablero.filas * tablero.tam_casilla / 2.0 - margen
	return Vector3(
		clampf(p.x, tablero.centro.x - mitad_x, tablero.centro.x + mitad_x),
		tablero.centro.y,
		clampf(p.z, tablero.centro.z - mitad_z, tablero.centro.z + mitad_z))


func _on_golpe_lanzado(golpe: Golpe, atacante: Personaje) -> void:
	var rival := rival_de(atacante)
	var hacia := _plano(rival.global_position - atacante.global_position)
	var dir := hacia.normalized() if hacia.length() > 0.01 else Vector3.FORWARD
	atacante.golpear(dir)
	if hacia.length() > golpe.alcance:
		return
	var cubierto := rival.cubriendose
	var cantidad := golpe.impacto * (factor_cubierto if cubierto else 1.0)
	var casillas := 0 if cubierto else casillas_empuje(rival.impacto + cantidad)
	var destino := limitar_al_ring(rival.global_position + dir * casillas * tablero.tam_casilla, rival.radio)
	rival.recibir_golpe(cantidad, destino, aturdimiento_cubierto if cubierto else aturdimiento)


## Evita que los luchadores se encimen: los separa a partes iguales.
func _separar(a: Personaje, b: Personaje) -> void:
	var entre := _plano(b.global_position - a.global_position)
	var minima := a.radio + b.radio
	var d := entre.length()
	if d >= minima:
		return
	var dir := entre / d if d > 0.001 else Vector3.RIGHT
	var correccion := dir * (minima - d) / 2.0
	a.global_position -= correccion
	b.global_position += correccion


func _plano(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
