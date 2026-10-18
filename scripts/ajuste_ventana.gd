extends Node
## Autoload: en PC ajusta la ventana a la pantalla manteniendo la proporción 9:16
## (la base es 720x1280 y el contenido se escala con stretch "canvas_items").
## En celular no hace nada: el juego ocupa la pantalla completa.
## Si el juego corre incrustado en la pestaña «Juego» del editor, el tamaño lo
## controla el editor (window_width/height_override en project.godot).

## Fracción de la altura útil de la pantalla que ocupa la ventana.
const ALTURA_PANTALLA := 0.92


func _ready() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	_ajustar.call_deferred()


func _ajustar() -> void:
	var base := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var pantalla := DisplayServer.window_get_current_screen()
	var util := DisplayServer.screen_get_usable_rect(pantalla)
	var escala := minf(util.size.y * ALTURA_PANTALLA / base.y, util.size.x * ALTURA_PANTALLA / base.x)
	var tam := Vector2i(base * minf(escala, 1.0))
	DisplayServer.window_set_size(tam)
	DisplayServer.window_set_position(util.position + (util.size - tam) / 2)
