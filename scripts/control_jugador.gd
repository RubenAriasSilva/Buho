extends Node
## Traduce la entrada del jugador a acciones del luchador: joystick y botones del
## HUD (celular) o teclado en PC: WASD/flechas para moverse, J/K/L para
## Manotazo/Puñetazo/Patada y Espacio para cubrirse.

const Personaje = preload("res://scripts/personaje.gd")
const Hud = preload("res://scripts/hud.gd")
const Combate = preload("res://scripts/combate.gd")

@export var personaje: Personaje
@export var hud: Hud
@export var combate: Combate

const TECLAS_GOLPE := [KEY_J, KEY_K, KEY_L]


func _ready() -> void:
	hud.golpe_presionado.connect(_golpear)


func _process(delta: float) -> void:
	var entrada: Vector2 = hud.vector_joystick()
	if entrada == Vector2.ZERO:
		entrada = _teclado()
	personaje.mover(_a_mundo(entrada), delta)
	personaje.cubrirse(hud.cubrirse_presionado() or Input.is_physical_key_pressed(KEY_SPACE))


func _unhandled_key_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla.pressed and not tecla.echo and tecla.physical_keycode in TECLAS_GOLPE:
		_golpear(TECLAS_GOLPE.find(tecla.physical_keycode))


func _golpear(indice: int) -> void:
	if indice < combate.golpes.size():
		personaje.intentar_golpe(combate.golpes[indice])


func _teclado() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	return v.limit_length(1.0)


## Convierte la dirección de pantalla (arriba = y negativo) a una dirección sobre
## el piso relativa a la cámara: arriba = alejarse de la cámara.
func _a_mundo(v: Vector2) -> Vector3:
	if v == Vector2.ZERO:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var derecha := cam.global_basis.x
	var adelante := -cam.global_basis.z
	derecha = Vector3(derecha.x, 0.0, derecha.z).normalized()
	adelante = Vector3(adelante.x, 0.0, adelante.z).normalized()
	return derecha * v.x - adelante * v.y
