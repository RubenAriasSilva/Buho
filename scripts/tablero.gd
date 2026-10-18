extends Node3D
## Cuadrícula lógica del ring: convierte celdas <-> mundo y detecta toques
## sobre las casillas (interior + capa exterior). Las casillas son invisibles.
## El nodo debe quedar en el origen del mundo; `centro` está en coordenadas globales.

enum Tipo { FUERA, INTERIOR, CUERDA, POSTE }

signal casilla_presionada(celda: Vector2i, tipo: Tipo)

@export_group("Cuadrícula")
@export var columnas := 7
@export var filas := 7
@export var tam_casilla := 6.0 / 7.0
## Centro de la superficie del cuadrilátero (y = altura del piso).
@export var centro := Vector3(0.3116, 0.9127, 0.1796)
## Agrega una fila/columna alrededor para cuerdas (lados) y postes (esquinas).
@export var capa_exterior := true
## Detecta toques sobre las casillas (emite `casilla_presionada`). Apagado en
## el modo de tiempo real, donde se usa el joystick.
@export var entrada_toque := false

@export_group("Cuerdas y postes")
## Distancia del centro a las cuerdas (donde rebota el personaje).
@export var dist_cuerdas := 3.3
## Distancia del centro a los postes (en X y en Z).
@export var dist_postes := 3.51
## Altura sobre el piso donde se para el personaje en el poste.
@export var altura_poste := 1.25

@export_group("Depuración")
## Dibuja las casillas presionables para calibrar la cuadrícula.
@export var depurar_casillas := false


func _ready() -> void:
	if depurar_casillas:
		_dibujar_casillas()


func _unhandled_input(event: InputEvent) -> void:
	if not entrada_toque:
		return
	# En móvil el toque llega emulado como clic (emulate_mouse_from_touch),
	# así que con escuchar el ratón cubrimos PC y celular sin duplicar eventos.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var celda := celda_en_pantalla(event.position)
		var tipo := tipo_de(celda)
		if tipo != Tipo.FUERA:
			get_viewport().set_input_as_handled()
			casilla_presionada.emit(celda, tipo)


func celda_en_pantalla(pos_pantalla: Vector2) -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i(-99, -99)
	var plano := Plane(Vector3.UP, centro.y)
	var punto = plano.intersects_ray(cam.project_ray_origin(pos_pantalla), cam.project_ray_normal(pos_pantalla))
	if punto == null:
		return Vector2i(-99, -99)
	return mundo_a_celda(punto)


func tipo_de(celda: Vector2i) -> Tipo:
	if es_interior(celda):
		return Tipo.INTERIOR
	if not capa_exterior:
		return Tipo.FUERA
	if celda.x < -1 or celda.x > columnas or celda.y < -1 or celda.y > filas:
		return Tipo.FUERA
	var borde_x := celda.x == -1 or celda.x == columnas
	var borde_y := celda.y == -1 or celda.y == filas
	return Tipo.POSTE if borde_x and borde_y else Tipo.CUERDA


func es_interior(celda: Vector2i) -> bool:
	return celda.x >= 0 and celda.x < columnas and celda.y >= 0 and celda.y < filas


## Celda interior más cercana a una celda exterior (la orilla junto a la cuerda/poste).
func orilla_de(celda: Vector2i) -> Vector2i:
	return Vector2i(clampi(celda.x, 0, columnas - 1), clampi(celda.y, 0, filas - 1))


## Normal (hacia afuera, en la rejilla) de la cuerda de una celda exterior de lado.
func normal_cuerda(celda: Vector2i) -> Vector2:
	if celda.x < 0:
		return Vector2.LEFT
	if celda.x >= columnas:
		return Vector2.RIGHT
	return Vector2.UP if celda.y < 0 else Vector2.DOWN


## Coordenada de rejilla (x para cuerdas laterales, y para frente/fondo) donde está la cuerda.
func cuerda_en_rejilla(normal: Vector2) -> float:
	var mitad := (columnas - 1) / 2.0 if normal.x != 0 else (filas - 1) / 2.0
	var signo := normal.x + normal.y
	return mitad + signo * dist_cuerdas / tam_casilla


## Punto en el mundo para coordenadas de rejilla fraccionarias.
func punto_en_rejilla(cx: float, cy: float) -> Vector3:
	return centro + Vector3(
		(cx - (columnas - 1) / 2.0) * tam_casilla,
		0.0,
		(cy - (filas - 1) / 2.0) * tam_casilla)


func celda_a_mundo(celda: Vector2i) -> Vector3:
	return punto_en_rejilla(celda.x, celda.y)


func mundo_a_celda(p: Vector3) -> Vector2i:
	return Vector2i(
		floori((p.x - centro.x) / tam_casilla + columnas / 2.0),
		floori((p.z - centro.z) / tam_casilla + filas / 2.0))


## Punto sobre el poste de una celda exterior de esquina.
func punto_poste(celda: Vector2i) -> Vector3:
	var sx := -1.0 if celda.x < 0 else 1.0
	var sz := -1.0 if celda.y < 0 else 1.0
	return centro + Vector3(sx * dist_postes, altura_poste, sz * dist_postes)


func _dibujar_casillas() -> void:
	var malla := PlaneMesh.new()
	malla.size = Vector2.ONE * tam_casilla * 0.9
	var ext := 1 if capa_exterior else 0
	for y in range(-ext, filas + ext):
		for x in range(-ext, columnas + ext):
			var celda := Vector2i(x, y)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.2, 1, 0.4, 0.3) if es_interior(celda) else Color(0.2, 0.7, 1, 0.3)
			var casilla := MeshInstance3D.new()
			casilla.mesh = malla
			casilla.material_override = mat
			casilla.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			casilla.position = celda_a_mundo(celda) + Vector3.UP * 0.01
			add_child(casilla)
