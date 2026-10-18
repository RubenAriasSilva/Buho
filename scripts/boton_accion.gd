extends Control
## Botón circular de acción (golpe o cubrirse). Usa toques reales (con índice de
## dedo) para funcionar junto con el joystick; en PC también responde al mouse.

signal presionado
signal soltado

@export var texto := "Golpe"
@export var subtitulo := ""
@export var color := Color(1, 0.6, 0.3)
@export var radio := 52.0
@export var tam_fuente := 17

## false: se ve atenuado (sin energía).
var disponible := true:
	set(valor):
		if valor != disponible:
			disponible = valor
			queue_redraw()
## Fracción de recarga pendiente (0..1); se dibuja como un anillo.
var recarga := 0.0:
	set(valor):
		if not is_equal_approx(valor, recarga):
			recarga = valor
			queue_redraw()
var pulsado := false

const MOUSE := -2
const LIBRE := -1
var _dedo := LIBRE


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * radio * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _has_point(punto: Vector2) -> bool:
	return punto.distance_to(size / 2.0) <= radio


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _dedo == LIBRE:
			_presionar(event.index)
		elif not event.pressed and event.index == _dedo:
			_soltar()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed and _dedo == LIBRE:
			_presionar(MOUSE)
		elif not event.pressed and _dedo == MOUSE:
			_soltar()
	else:
		return
	accept_event()


func _presionar(dedo: int) -> void:
	_dedo = dedo
	pulsado = true
	queue_redraw()
	presionado.emit()


func _soltar() -> void:
	_dedo = LIBRE
	pulsado = false
	queue_redraw()
	soltado.emit()


func _draw() -> void:
	var c := size / 2.0
	var alfa := 1.0 if disponible else 0.4
	draw_circle(c, radio, Color(color, (0.45 if pulsado else 0.2) * alfa))
	draw_arc(c, radio - 1.0, 0.0, TAU, 64, Color(color, 0.8 * alfa), 2.0, true)
	if recarga > 0.0:
		draw_arc(c, radio - 5.0, -PI / 2.0, -PI / 2.0 + TAU * recarga, 48, Color(1, 1, 1, 0.6), 4.0, true)
	var fuente := get_theme_font("font", &"Titulo")
	var ancho := radio * 2.0
	var y := c.y + (0.0 if subtitulo.is_empty() else -4.0) + tam_fuente * 0.35
	draw_string(fuente, Vector2(0.0, y), texto, HORIZONTAL_ALIGNMENT_CENTER, ancho, tam_fuente, Color(1, 1, 1, alfa))
	if not subtitulo.is_empty():
		draw_string(get_theme_font("font", &"Label"), Vector2(0.0, y + tam_fuente * 0.95), subtitulo,
			HORIZONTAL_ALIGNMENT_CENTER, ancho, int(tam_fuente * 0.7), Color(1, 0.85, 0.35, 0.85 * alfa))
