extends CanvasLayer
## HUD del combate en tiempo real: paneles del NPC (izquierda) y del jugador
## (derecha), cronómetro (centro), joystick (abajo a la izquierda), botones de
## golpes y cubrirse (abajo a la derecha) y etiquetas de coordenadas del ring.

const Tablero = preload("res://scripts/tablero.gd")
const Personaje = preload("res://scripts/personaje.gd")
const Golpe = preload("res://scripts/golpe.gd")

enum LadoLetras { FRENTE, ATRAS }
enum LadoNumeros { IZQUIERDA, DERECHA }

## Índice del golpe (0..2) presionado en los botones.
signal golpe_presionado(indice: int)
signal cubrirse_cambiado(activo: bool)

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
var _golpes: Array[Golpe] = []
var _etiquetas_letras: Array[Label] = []
var _etiquetas_numeros: Array[Label] = []

@onready var _coordenadas: Control = $Raiz/Coordenadas
@onready var _tiempo: Label = $Raiz/Tiempo
@onready var _mensaje: Label = $Raiz/Mensaje
@onready var _panel_jugador = $Raiz/PanelJugador
@onready var _panel_npc = $Raiz/PanelNpc
@onready var _joystick = $Raiz/Joystick
@onready var _botones_golpe: Array = [$Raiz/Botones/Manotazo, $Raiz/Botones/Punetazo, $Raiz/Botones/Patada]
@onready var _boton_cubrirse = $Raiz/Botones/Cubrirse


func _ready() -> void:
	_mensaje.modulate.a = 0.0
	for i in _botones_golpe.size():
		_botones_golpe[i].presionado.connect(golpe_presionado.emit.bind(i))
	_boton_cubrirse.presionado.connect(cubrirse_cambiado.emit.bind(true))
	_boton_cubrirse.soltado.connect(cubrirse_cambiado.emit.bind(false))


func configurar(jugador: Personaje, npc: Personaje, tablero: Tablero, golpes: Array[Golpe]) -> void:
	_tablero = tablero
	_jugador = jugador
	_golpes = golpes
	_panel_jugador.configurar(jugador)
	_panel_npc.configurar(npc)
	_panel_jugador.set_activo(true)
	_panel_npc.set_activo(true)
	for i in mini(golpes.size(), _botones_golpe.size()):
		_botones_golpe[i].texto = golpes[i].nombre
		_botones_golpe[i].subtitulo = "Energía %d" % golpes[i].costo
		_botones_golpe[i].color = golpes[i].color
	_boton_cubrirse.subtitulo = "%d/s" % roundi(jugador.costo_cubrirse_por_segundo)
	_crear_coordenadas()


## Dirección del joystick (arriba = y negativo); ZERO si no se toca.
func vector_joystick() -> Vector2:
	return _joystick.vector


func cubrirse_presionado() -> bool:
	return _boton_cubrirse.pulsado


func mostrar_tiempo(segundos: float) -> void:
	var s := floori(segundos)
	_tiempo.text = "%02d:%02d" % [s / 60, s % 60]


func mostrar_mensaje(texto: String) -> void:
	_mensaje.text = texto
	_mensaje.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_mensaje, "modulate:a", 0.0, 0.4)


func _process(_delta: float) -> void:
	if _tablero == null:
		return
	var recarga: float = _jugador.fraccion_recarga()
	for i in mini(_golpes.size(), _botones_golpe.size()):
		_botones_golpe[i].disponible = _jugador.energia >= _golpes[i].costo
		_botones_golpe[i].recarga = recarga
	_boton_cubrirse.disponible = _jugador.energia > 0.0

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
