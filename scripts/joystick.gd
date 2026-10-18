extends Control
## Joystick virtual. Usa toques reales (con índice de dedo) para funcionar junto
## con los botones de acción al mismo tiempo; en PC también responde al mouse.
## `vector` va de (-1, -1) a (1, 1); arriba es y negativo.

@export var radio := 110.0
@export var radio_perilla := 44.0
## Fracción del radio en la que el joystick no responde.
@export_range(0.0, 0.9) var zona_muerta := 0.15
@export var color := Color(1, 1, 1)

var vector := Vector2.ZERO

const MOUSE := -2
const LIBRE := -1
var _dedo := LIBRE
var _perilla := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * radio * 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _dedo == LIBRE:
			_dedo = event.index
			_actualizar(event.position)
		elif not event.pressed and event.index == _dedo:
			_soltar()
	elif event is InputEventScreenDrag:
		if event.index == _dedo:
			_actualizar(event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed and _dedo == LIBRE:
			_dedo = MOUSE
			_actualizar(event.position)
		elif not event.pressed and _dedo == MOUSE:
			_soltar()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _dedo == MOUSE:
			_actualizar(event.position)
	else:
		return
	accept_event()


func _actualizar(pos: Vector2) -> void:
	_perilla = (pos - size / 2.0).limit_length(radio)
	var v := _perilla / radio
	vector = v if v.length() > zona_muerta else Vector2.ZERO
	queue_redraw()


func _soltar() -> void:
	_dedo = LIBRE
	_perilla = Vector2.ZERO
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, radio, Color(color, 0.07))
	draw_arc(c, radio, 0.0, TAU, 64, Color(color, 0.25), 2.0, true)
	draw_circle(c + _perilla, radio_perilla, Color(color, 0.4 if _dedo != LIBRE else 0.22))
