extends CanvasLayer
## HUD de la partida: paneles del NPC (izquierda) y del jugador (derecha),
## cronómetro y turno (centro), barra de cartas y botón «Terminar» (abajo)
## y etiquetas de coordenadas del tablero.

const Tablero = preload("res://scripts/tablero.gd")
const Personaje = preload("res://scripts/personaje.gd")

enum LadoLetras { FRENTE, ATRAS }
enum LadoNumeros { IZQUIERDA, DERECHA }

signal terminar_presionado
signal carta_armada(indice_mano: int)
signal carta_devuelta(indice_mano: int)

@export_group("Coordenadas")
@export var mostrar_coordenadas := true
## Una letra por columna, de izquierda a derecha.
@export var letras := "ABCDEFG"
@export var letras_en := LadoLetras.FRENTE
@export var numeros_en := LadoNumeros.DERECHA
## Por defecto el 1 es la fila más cercana a la cámara; activa para invertir.
@export var invertir_numeros := false
## Qué tan afuera de la orilla del ring van las etiquetas (en casillas).
@export var separacion_letras := 0.75
@export var separacion_numeros := 1.1
@export var desplazamiento_letras_px := Vector2.ZERO
@export var desplazamiento_numeros_px := Vector2.ZERO
@export var tam_fuente_coordenadas := 22
@export var color_coordenadas := Color(1, 1, 1, 0.9)

var _tablero: Tablero
var _jugador: Personaje
var _npc: Personaje
var _etiquetas_letras: Array[Label] = []
var _etiquetas_numeros: Array[Label] = []
var _estilo_boton: StyleBox
var _estilo_boton_presionado: StyleBox

@onready var _coordenadas: Control = $Raiz/Coordenadas
@onready var _tiempo: Label = $Raiz/Tiempo
@onready var _turno: Label = $Raiz/Turno
@onready var _ayuda: Label = $Raiz/Ayuda
@onready var _mensaje: Label = $Raiz/Mensaje
@onready var _panel_jugador = $Raiz/PanelJugador
@onready var _panel_npc = $Raiz/PanelNpc
@onready var _barra_cartas = $Raiz/BarraCartas
@onready var _boton_terminar: Button = $Raiz/Terminar


func _ready() -> void:
	_mensaje.modulate.a = 0.0
	_ayuda.text = ""
	_estilo_boton = _boton_terminar.get_theme_stylebox("normal")
	_estilo_boton_presionado = _boton_terminar.get_theme_stylebox("pressed")
	_boton_terminar.pressed.connect(terminar_presionado.emit)
	_barra_cartas.carta_armada.connect(carta_armada.emit)
	_barra_cartas.carta_devuelta.connect(carta_devuelta.emit)


func configurar(jugador: Personaje, npc: Personaje, tablero: Tablero) -> void:
	_tablero = tablero
	_jugador = jugador
	_npc = npc
	_panel_jugador.configurar(jugador)
	_panel_npc.configurar(npc)
	_barra_cartas.configurar(jugador)
	_crear_coordenadas()


func mostrar_tiempo(segundos: float) -> void:
	var s := floori(segundos)
	_tiempo.text = "%02d:%02d" % [s / 60, s % 60]


func mostrar_turno(es_jugador: bool) -> void:
	_turno.text = "Tu turno" if es_jugador else "Turno rival"
	_turno.add_theme_color_override("font_color", (_jugador if es_jugador else _npc).color)
	_panel_jugador.set_activo(es_jugador)
	_panel_npc.set_activo(not es_jugador)
	_boton_terminar.disabled = not es_jugador
	_barra_cartas.set_habilitada(es_jugador)


## Destaca el botón como «Usar carta» cuando la carta armada puede activarse
## sin moverse (al terminar el turno).
func set_carta_lista(lista: bool) -> void:
	_boton_terminar.text = "Usar carta" if lista else "Terminar turno"
	if lista:
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(1, 0.8, 0.3)
		estilo.set_corner_radius_all(10)
		for estado in ["normal", "hover", "pressed"]:
			_boton_terminar.add_theme_stylebox_override(estado, estilo)
		_boton_terminar.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
		_boton_terminar.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.1))
		_boton_terminar.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.1))
	else:
		_boton_terminar.remove_theme_color_override("font_hover_color")
		_boton_terminar.remove_theme_color_override("font_pressed_color")
		_boton_terminar.add_theme_stylebox_override("normal", _estilo_boton)
		_boton_terminar.add_theme_stylebox_override("hover", _estilo_boton)
		_boton_terminar.add_theme_stylebox_override("pressed", _estilo_boton_presionado)
		_boton_terminar.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))


## Texto persistente bajo el turno (p. ej. instrucciones al correr las cuerdas).
func mostrar_ayuda(texto: String) -> void:
	_ayuda.text = texto


func mostrar_mensaje(texto: String) -> void:
	_mensaje.text = texto
	_mensaje.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_mensaje, "modulate:a", 0.0, 0.4)


func _process(_delta: float) -> void:
	if _tablero == null:
		return
	_coordenadas.visible = mostrar_coordenadas
	if not mostrar_coordenadas:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var y_letras := -0.5 - separacion_letras if letras_en == LadoLetras.ATRAS \
		else _tablero.filas - 0.5 + separacion_letras
	for i in _etiquetas_letras.size():
		_colocar(_etiquetas_letras[i], cam, _tablero.punto_en_rejilla(i, y_letras), desplazamiento_letras_px)
	var x_numeros := -0.5 - separacion_numeros if numeros_en == LadoNumeros.IZQUIERDA \
		else _tablero.columnas - 0.5 + separacion_numeros
	for j in _etiquetas_numeros.size():
		_colocar(_etiquetas_numeros[j], cam, _tablero.punto_en_rejilla(x_numeros, j), desplazamiento_numeros_px)


func _colocar(etiqueta: Label, cam: Camera3D, punto: Vector3, desplazamiento: Vector2) -> void:
	etiqueta.visible = not cam.is_position_behind(punto)
	etiqueta.position = cam.unproject_position(punto) - etiqueta.size / 2.0 + desplazamiento


func _crear_coordenadas() -> void:
	for hijo in _coordenadas.get_children():
		hijo.queue_free()
	_etiquetas_letras.clear()
	_etiquetas_numeros.clear()
	for i in _tablero.columnas:
		var texto := letras[i] if i < letras.length() else str(i + 1)
		_etiquetas_letras.append(_nueva_etiqueta(texto))
	for j in _tablero.filas:
		var numero := j + 1 if invertir_numeros else _tablero.filas - j
		_etiquetas_numeros.append(_nueva_etiqueta(str(numero)))


func _nueva_etiqueta(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	etiqueta.theme_type_variation = &"Titulo"
	etiqueta.add_theme_font_size_override("font_size", tam_fuente_coordenadas)
	etiqueta.add_theme_color_override("font_color", color_coordenadas)
	etiqueta.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	etiqueta.add_theme_constant_override("outline_size", 6)
	_coordenadas.add_child(etiqueta)
	return etiqueta
