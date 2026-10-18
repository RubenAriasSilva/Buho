extends PanelContainer
## Panel compacto de un luchador: nombre, energía (23/30) e Impacto (85%) con
## barras delgadas que cambian de color según qué tan llenas están.

const Personaje = preload("res://scripts/personaje.gd")

## Porcentaje de Impacto con el que la barra se ve llena (y totalmente roja).
@export var impacto_max_barra := 300.0
## Color según qué tan llena está la barra: 0 = vacía, 1 = llena.
@export var gradiente_energia: Gradient = _gradiente(Color(0.94, 0.33, 0.31), Color(0.98, 0.78, 0.3), Color(0.36, 0.86, 0.55))
@export var gradiente_impacto: Gradient = _gradiente(Color(0.36, 0.86, 0.55), Color(0.98, 0.78, 0.3), Color(0.94, 0.33, 0.31))

@onready var _punto: ColorRect = $Margen/Filas/Cabecera/Punto
@onready var _nombre: Label = $Margen/Filas/Cabecera/Nombre
@onready var _barra_energia: ProgressBar = $Margen/Filas/BarraEnergia
@onready var _texto_energia: Label = $Margen/Filas/Energia/Valor
@onready var _barra_impacto: ProgressBar = $Margen/Filas/BarraImpacto
@onready var _texto_impacto: Label = $Margen/Filas/Impacto/Valor
@onready var _linea_turno: ColorRect = $LineaTurno


static func _gradiente(bajo: Color, medio: Color, alto: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([bajo, medio, alto])
	return g


func _ready() -> void:
	# Cada barra necesita su propio estilo de relleno para cambiarle el color.
	for barra in [_barra_energia, _barra_impacto]:
		barra.add_theme_stylebox_override("fill", barra.get_theme_stylebox("fill").duplicate())


func configurar(personaje: Personaje) -> void:
	_nombre.text = personaje.nombre
	_punto.color = personaje.color
	_linea_turno.color = personaje.color
	personaje.energia_cambiada.connect(_on_energia_cambiada)
	personaje.impacto_cambiado.connect(_on_impacto_cambiado)
	_on_energia_cambiada(personaje.energia, personaje.energia_max)
	_on_impacto_cambiado(personaje.impacto)


func set_activo(activo: bool) -> void:
	_linea_turno.visible = activo
	create_tween().tween_property(self, "modulate:a", 1.0 if activo else 0.6, 0.2)


func _on_energia_cambiada(actual: int, maxima: int) -> void:
	_texto_energia.text = "%d/%d" % [actual, maxima]
	_actualizar_barra(_barra_energia, float(actual) / maxima, gradiente_energia)


func _on_impacto_cambiado(impacto: float) -> void:
	_texto_impacto.text = "%d%%" % roundi(impacto)
	_actualizar_barra(_barra_impacto, impacto / impacto_max_barra, gradiente_impacto)


func _actualizar_barra(barra: ProgressBar, fraccion: float, gradiente: Gradient) -> void:
	fraccion = clampf(fraccion, 0.0, 1.0)
	create_tween().tween_property(barra, "value", fraccion * barra.max_value, 0.25)
	(barra.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = gradiente.sample(fraccion)
