extends PanelContainer
## Una casilla de la barra de cartas: la zona de juego (`indice` = -1) o un
## hueco de la mano (0..2). Se arrastra manteniendo presionado y se suelta en
## otra ranura (mano -> zona de juego para armar, zona de juego -> mano para devolver).

const Carta = preload("res://scripts/carta.gd")
const TEMA = preload("res://ui/tema.tres")

signal soltada(origen: int, destino: int)

const ZONA_JUEGO := -1
const TAM := Vector2(156, 206)
const COLORES_CATEGORIA := {
	Carta.Categoria.BASICA: Color(0.95, 0.55, 0.3),
	Carta.Categoria.CURATIVA: Color(0.36, 0.86, 0.55),
	Carta.Categoria.ESPECIAL: Color(0.7, 0.5, 1.0),
	Carta.Categoria.DEFENSA: Color(0.4, 0.7, 1.0),
}
const NOMBRES_CATEGORIA := {
	Carta.Categoria.BASICA: "Básica",
	Carta.Categoria.CURATIVA: "Curativa",
	Carta.Categoria.ESPECIAL: "Especial",
	Carta.Categoria.DEFENSA: "Defensa",
}

var indice := 0
var carta: Carta
var habilitada := true
var pagable := true
var color_zona := Color(1, 0.8, 0.3)


func _init(p_indice := 0) -> void:
	indice = p_indice
	custom_minimum_size = TAM
	mouse_filter = Control.MOUSE_FILTER_STOP


func mostrar(p_carta: Carta, p_pagable: bool) -> void:
	carta = p_carta
	pagable = p_pagable
	for hijo in get_children():
		hijo.queue_free()
	add_theme_stylebox_override("panel", _estilo())
	if carta != null:
		add_child(crear_vista(carta))
	elif indice == ZONA_JUEGO:
		add_child(_vista_zona_vacia())
	modulate.a = 1.0 if (pagable or carta == null) else 0.45


## Vista de una carta (también se usa como imagen al arrastrar).
static func crear_vista(c: Carta) -> Control:
	var color: Color = COLORES_CATEGORIA[c.categoria]
	var caja := VBoxContainer.new()
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 6)

	var franja := ColorRect.new()
	franja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	franja.color = color
	franja.custom_minimum_size = Vector2(0, 5)
	caja.add_child(franja)

	var margen := MarginContainer.new()
	margen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for lado in ["left", "right", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 12)
	caja.add_child(margen)

	var filas := VBoxContainer.new()
	filas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filas.add_theme_constant_override("separation", 4)
	margen.add_child(filas)

	filas.add_child(_etiqueta(NOMBRES_CATEGORIA[c.categoria], 13, color))

	var nombre := _etiqueta(c.nombre, 19, Color.WHITE, true)
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	filas.add_child(nombre)

	var hueco := Control.new()
	hueco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hueco.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filas.add_child(hueco)

	var efecto := _etiqueta(c.efecto_corto(), 26, color, true)
	efecto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	filas.add_child(efecto)

	var pie := _etiqueta("Energía %d" % c.costo, 13, Color(1, 0.85, 0.35, 0.9))
	pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	filas.add_child(pie)
	return caja


static func _etiqueta(texto: String, tam: int, color: Color, negrita := false) -> Label:
	var l := Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	if negrita:
		l.theme_type_variation = &"Titulo"
	return l


func _vista_zona_vacia() -> Control:
	var caja := VBoxContainer.new()
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.alignment = BoxContainer.ALIGNMENT_CENTER
	var titulo := _etiqueta("JUGAR", 22, color_zona, true)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(titulo)
	var ayuda := _etiqueta("Arrastra una\ncarta aquí", 13, Color(1, 1, 1, 0.5))
	ayuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(ayuda)
	return caja


func _estilo() -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.set_corner_radius_all(10)
	if indice == ZONA_JUEGO and carta != null:
		e.bg_color = Color(0.09, 0.09, 0.13, 0.95)
		e.set_border_width_all(2)
		e.border_color = color_zona
	elif indice == ZONA_JUEGO:
		e.bg_color = Color(color_zona, 0.08)
		e.set_border_width_all(2)
		e.border_color = Color(color_zona, 0.8)
	elif carta != null:
		e.bg_color = Color(0.09, 0.09, 0.13, 0.92)
		e.set_border_width_all(1)
		e.border_color = Color(COLORES_CATEGORIA[carta.categoria], 0.5)
	else:
		e.bg_color = Color(1, 1, 1, 0.04)
		e.set_border_width_all(1)
		e.border_color = Color(1, 1, 1, 0.12)
	return e


func _get_drag_data(_pos: Vector2) -> Variant:
	if carta == null or not habilitada:
		return null
	var vista := PanelContainer.new()
	vista.add_theme_stylebox_override("panel", _estilo())
	vista.size = TAM
	vista.add_child(crear_vista(carta))
	vista.position = -TAM / 2.0
	vista.rotation = 0.05
	var ancla := Control.new()
	ancla.theme = TEMA  # la vista de arrastre vive fuera del HUD y no hereda su tema
	ancla.add_child(vista)
	set_drag_preview(ancla)
	modulate.a = 0.3
	return { "origen": indice }


func _can_drop_data(_pos: Vector2, datos: Variant) -> bool:
	if not habilitada or not (datos is Dictionary) or not datos.has("origen"):
		return false
	var origen: int = datos.origen
	return origen != indice and (indice == ZONA_JUEGO or origen == ZONA_JUEGO)


func _drop_data(_pos: Vector2, datos: Variant) -> void:
	soltada.emit(datos.origen, indice)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate.a = 1.0 if (pagable or carta == null) else 0.45
