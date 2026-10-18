extends Node
## Flujo de la partida por turnos alternados (jugador -> NPC).
## En cada turno: un movimiento (1 de energía por casilla) y, al terminar, se
## resuelve la carta armada en la zona de juego. Los empujes dependen del
## Medidor de Impacto del que los recibe. El reloj de la partida corre siempre.

const Tablero = preload("res://scripts/tablero.gd")
const Personaje = preload("res://scripts/personaje.gd")
const Hud = preload("res://scripts/hud.gd")
const IaNpc = preload("res://scripts/ia_npc.gd")
const Carta = preload("res://scripts/carta.gd")
const Mazo = preload("res://scripts/mazo.gd")

enum Estado { ESPERANDO_JUGADOR, TURNO_NPC, ANIMANDO }

@export var tablero: Tablero
@export var jugador: Personaje
@export var npc: Personaje
@export var hud: Hud
@export var ia: IaNpc
@export var mazo: Mazo

@export_group("Turnos")
@export var pausa_entre_turnos := 0.35

@export_group("Costos")
## true: se cuenta como el rey del ajedrez (diagonales cuestan 1). false: Manhattan.
@export var diagonal := true
## Energía extra (además del recorrido) por subirse al poste.
@export var costo_subir_poste := 2
## Distancia máxima (desde la esquina del poste) a la que se puede saltar.
@export var alcance_salto := 4

@export_group("Rebote")
## Fracción del recorrido que conserva un rebote que llega en ángulo.
@export_range(0.0, 1.0) var vuelo_en_angulo := 0.9
## Casillas que gana cada rebote recto al correr las cuerdas.
@export var extra_por_rebote := 1.0

@export_group("Empuje")
## Casillas que sale empujado según su Impacto: [hasta %, casillas].
## Por encima del último límite se usa `empuje_maximo`.
@export var empuje_por_impacto: Array[Vector2] = [Vector2(50, 0), Vector2(150, 1), Vector2(200, 2)]
@export var empuje_maximo := 3

@export_group("Depuración")
## D: +25% de Impacto al jugador, F: al rival, R: reinicia ambos.
@export var teclas_debug := true

var tiempo_partida := 0.0
var turno := 0
var actual: Personaje
var estado := Estado.ANIMANDO
## Dirección del choque del movimiento en curso (ZERO si no hubo).
var _choque := Vector2i.ZERO


func _ready() -> void:
	tablero.casilla_presionada.connect(_on_casilla_presionada)
	hud.terminar_presionado.connect(_on_terminar_presionado)
	hud.carta_armada.connect(_on_carta_armada)
	hud.carta_devuelta.connect(_on_carta_devuelta)
	for luchador in [jugador, npc]:
		luchador.celda = luchador.celda_inicial
		luchador.global_position = tablero.celda_a_mundo(luchador.celda)
	hud.configurar(jugador, npc, tablero)
	hud.mostrar_tiempo(0.0)
	jugador.cartas_cambiadas.connect(_actualizar_boton_carta)
	jugador.energia_cambiada.connect(func(_a: int, _m: int) -> void: _actualizar_boton_carta())
	_iniciar_turno.call_deferred(jugador)


func _process(delta: float) -> void:
	tiempo_partida += delta
	hud.mostrar_tiempo(tiempo_partida)


func _unhandled_key_input(event: InputEvent) -> void:
	if not teclas_debug or not event.is_pressed():
		return
	match (event as InputEventKey).keycode:
		KEY_D:
			jugador.recibir_impacto(25.0)
		KEY_F:
			npc.recibir_impacto(25.0)
		KEY_R:
			jugador.recibir_impacto(-jugador.impacto)
			npc.recibir_impacto(-npc.impacto)


func rival_de(luchador: Personaje) -> Personaje:
	return npc if luchador == jugador else jugador


func distancia(a: Vector2i, b: Vector2i) -> int:
	var d := (b - a).abs()
	return maxi(d.x, d.y) if diagonal else d.x + d.y


## Casillas que sale empujado un luchador con este Impacto.
func casillas_empuje(impacto: float) -> int:
	for tramo in empuje_por_impacto:
		if impacto <= tramo.x:
			return int(tramo.y)
	return empuje_maximo


## Celda exterior de la cuerda que tiene enfrente un luchador que corre las cuerdas.
func celda_cuerda_enfrente(luchador: Personaje) -> Vector2i:
	var c := luchador.celda
	var dir := luchador.dir_cuerdas
	if dir.x != 0:
		return Vector2i(-1 if dir.x < 0 else tablero.columnas, c.y)
	return Vector2i(c.x, -1 if dir.y < 0 else tablero.filas)


## Costo del movimiento al tocar `celda`, o -1 si no se permite.
func costo_accion(actor: Personaje, celda: Vector2i, tipo: Tablero.Tipo) -> int:
	if actor.en_poste:
		if tipo != Tablero.Tipo.INTERIOR:
			return -1
		var d := distancia(tablero.orilla_de(actor.celda), celda)
		return maxi(d, 1) if d <= alcance_salto else -1
	if actor.en_cuerdas:
		if tipo == Tablero.Tipo.POSTE:
			return -1
		# Seguir o salir: solo se paga la ida a la cuerda de enfrente.
		return distancia(actor.celda, celda_cuerda_enfrente(actor))
	match tipo:
		Tablero.Tipo.INTERIOR:
			var d := distancia(actor.celda, celda)
			return d if d > 0 else -1
		Tablero.Tipo.CUERDA:
			# Solo se paga la ida; el rebote es impulso gratis.
			return distancia(actor.celda, celda)
		Tablero.Tipo.POSTE:
			return distancia(actor.celda, tablero.orilla_de(celda)) + costo_subir_poste
	return -1


## Rebote por reflexión: entra a la cuerda en línea recta y sale con el mismo
## ángulo hacia el otro lado. Recto regresa el recorrido + `extra_por_rebote` y deja
## al luchador corriendo las cuerdas; en ángulo conserva `vuelo_en_angulo` y aterriza.
func calcular_rebote(desde: Vector2i, celda_cuerda: Vector2i) -> Dictionary:
	var n := tablero.normal_cuerda(celda_cuerda)
	var linea := tablero.cuerda_en_rejilla(n)
	var s := Vector2(desde)
	var direccion := Vector2(celda_cuerda) - s
	var eje := 0 if n.x != 0 else 1
	var contacto := s + direccion * ((linea - s[eje]) / direccion[eje])
	var entrada := contacto - s
	var recto := absf(entrada[1 - eje]) <= 0.01
	if recto:
		var tramo := _tramo_cuerdas(contacto, -n, entrada.length() + extra_por_rebote)
		return { "contacto": contacto, "recto": true, "tramo": tramo }
	var punto := contacto + entrada.bounce(n) * vuelo_en_angulo
	var aterrizaje := tablero.orilla_de(Vector2i(roundi(punto.x), roundi(punto.y)))
	return { "contacto": contacto, "recto": false, "aterrizaje": aterrizaje }


## Recorre `largo` casillas desde una cuerda en la dirección `dir` (eje x o y).
## Si alcanza la cuerda opuesta rebota ahí también (+`extra_por_rebote`).
## Devuelve los puntos (cuerdas intermedias + aterrizaje), la dirección final
## de viaje y el largo del último tramo.
func _tramo_cuerdas(contacto: Vector2, dir: Vector2, largo: float) -> Dictionary:
	var puntos: Array[Vector2] = []
	var pos := contacto
	var restante := largo
	while true:
		var eje := 0 if dir.x != 0 else 1
		var hasta_cuerda := absf(tablero.cuerda_en_rejilla(dir) - pos[eje])
		if restante < hasta_cuerda:
			break
		pos += dir * hasta_cuerda
		puntos.append(pos)
		restante = restante - hasta_cuerda + extra_por_rebote
		dir = -dir
	var fin := pos + dir * restante
	var celda := tablero.orilla_de(Vector2i(roundi(fin.x), roundi(fin.y)))
	puntos.append(Vector2(celda))
	return { "puntos": puntos, "dir": dir, "largo": restante }


func _on_casilla_presionada(celda: Vector2i, tipo: Tablero.Tipo) -> void:
	if estado != Estado.ESPERANDO_JUGADOR:
		return
	var costo := costo_accion(jugador, celda, tipo)
	if costo < 0:
		if jugador.en_poste:
			hud.mostrar_mensaje("Desde el poste solo puedes saltar (alcance %d)" % alcance_salto)
		elif jugador.en_cuerdas:
			hud.mostrar_mensaje("Toca una cuerda para seguir o una casilla para salir")
		return
	if costo > jugador.energia:
		hud.mostrar_mensaje("Energía insuficiente (%d)" % costo)
		return
	ejecutar(jugador, celda, tipo)


## true si la carta armada se activaría al terminar el turno sin moverse.
func carta_lista(actor: Personaje) -> bool:
	var carta := actor.carta_en_juego
	if carta == null or carta.costo > actor.energia:
		return false
	if not carta.es_ataque():
		return true
	if carta.requiere_poste and not actor.en_poste:
		return false
	return distancia(actor.celda, rival_de(actor).celda) <= carta.alcance


func _actualizar_boton_carta() -> void:
	hud.set_carta_lista(estado == Estado.ESPERANDO_JUGADOR and carta_lista(jugador))


func _on_terminar_presionado() -> void:
	if estado == Estado.ESPERANDO_JUGADOR:
		terminar_turno(jugador)


func _on_carta_armada(indice_mano: int) -> void:
	if estado == Estado.ESPERANDO_JUGADOR:
		jugador.armar_carta(indice_mano)


func _on_carta_devuelta(indice_mano: int) -> void:
	if estado == Estado.ESPERANDO_JUGADOR:
		jugador.desarmar_carta(indice_mano)


func _iniciar_turno(luchador: Personaje) -> void:
	turno += 1
	actual = luchador
	luchador.bloqueo_activo = false
	luchador.regenerar_turno()
	luchador.rellenar_mano(mazo)
	hud.mostrar_turno(luchador == jugador)
	if luchador == jugador:
		estado = Estado.ESPERANDO_JUGADOR
		if jugador.en_cuerdas:
			hud.mostrar_ayuda("En cuerdas: toca una cuerda para seguir o una casilla para salir")
		elif jugador.en_poste:
			hud.mostrar_ayuda("En el poste: toca una casilla para saltar")
		else:
			hud.mostrar_ayuda("")
		_actualizar_boton_carta()
		return
	estado = Estado.TURNO_NPC
	_actualizar_boton_carta()
	hud.mostrar_ayuda("")
	await get_tree().create_timer(ia.pausa_pensar).timeout
	var eleccion := ia.elegir(npc, jugador, self)
	if eleccion.has("carta"):
		npc.armar_carta(eleccion.carta)
	if eleccion.has("celda"):
		ejecutar(npc, eleccion.celda, eleccion.tipo)
	else:
		terminar_turno(npc)


func _siguiente_turno() -> void:
	await get_tree().create_timer(pausa_entre_turnos).timeout
	_iniciar_turno(rival_de(actual))


## Termina el turno sin moverse; la carta armada igual se resuelve.
func terminar_turno(actor: Personaje) -> void:
	estado = Estado.ANIMANDO
	_actualizar_boton_carta()
	hud.mostrar_ayuda("")
	actor.salir_de_cuerdas()
	_choque = Vector2i.ZERO
	await _resolver_carta_y_choque(actor, rival_de(actor), actor.en_poste)
	_siguiente_turno()


func ejecutar(actor: Personaje, celda: Vector2i, tipo: Tablero.Tipo) -> void:
	estado = Estado.ANIMANDO
	_actualizar_boton_carta()
	hud.mostrar_ayuda("")
	_choque = Vector2i.ZERO
	var empezo_en_poste := actor.en_poste
	actor.gastar_energia(costo_accion(actor, celda, tipo))
	var rival := rival_de(actor)

	if actor.en_poste:
		await _saltar(actor, rival, celda)
	elif actor.en_cuerdas:
		await _accion_en_cuerdas(actor, rival, celda, tipo)
	else:
		match tipo:
			Tablero.Tipo.INTERIOR:
				await _caminar(actor, rival, celda)
			Tablero.Tipo.CUERDA:
				await _rebotar(actor, rival, celda)
			Tablero.Tipo.POSTE:
				if await _caminar(actor, rival, tablero.orilla_de(celda)):
					await actor.subir_poste(tablero.punto_poste(celda))

	await _resolver_carta_y_choque(actor, rival, empezo_en_poste)
	_siguiente_turno()


## Al final del movimiento: resuelve la carta armada; si no hubo ataque y hubo
## choque, el rival sale empujado según su Impacto actual.
func _resolver_carta_y_choque(actor: Personaje, rival: Personaje, empezo_en_poste: bool) -> void:
	var ataco := false
	if actor.carta_en_juego != null:
		ataco = await _resolver_carta(actor, rival, empezo_en_poste)
	if not ataco and _choque != Vector2i.ZERO:
		await _empujar(actor, rival, _choque)


## Aplica la carta armada. Devuelve true si fue un ataque que conectó.
## Si no puede activarse, se queda en la zona de juego sin cobrarse.
func _resolver_carta(actor: Personaje, rival: Personaje, empezo_en_poste: bool) -> bool:
	var carta := actor.carta_en_juego
	var es_jugador := actor == jugador
	if carta.costo > actor.energia:
		if es_jugador:
			hud.mostrar_mensaje("Sin energía para %s" % carta.nombre)
		return false
	if carta.es_ataque():
		if carta.requiere_poste and not empezo_en_poste:
			if es_jugador:
				hud.mostrar_mensaje("%s: empieza el turno en el poste" % carta.nombre)
			return false
		if distancia(actor.celda, rival.celda) > carta.alcance:
			if es_jugador:
				hud.mostrar_mensaje("%s: acércate al rival" % carta.nombre)
			return false
		actor.gastar_energia(carta.costo)
		actor.gastar_carta_en_juego()
		var dir := (rival.celda - actor.celda).sign()
		var dir_mundo := (tablero.celda_a_mundo(rival.celda) - tablero.celda_a_mundo(actor.celda)).normalized()
		for golpe in carta.golpes:
			await actor.golpear(dir_mundo)
			rival.recibir_impacto(carta.impacto / carta.golpes)
		await _empujar(actor, rival, dir)
		return true

	actor.gastar_energia(carta.costo)
	actor.gastar_carta_en_juego()
	if carta.energia_extra > 0:
		actor.ganar_energia(carta.energia_extra)
	if carta.reduce_impacto > 0.0:
		actor.recibir_impacto(-carta.reduce_impacto)
	if carta.bloqueo:
		actor.bloqueo_activo = true
	return false


## Camina en línea recta (aunque sea en ángulo). Devuelve false si chocó con el rival.
func _caminar(actor: Personaje, rival: Personaje, destino: Vector2i) -> bool:
	return await _recorrer(actor, rival, [Vector2(destino)], true)


func _rebotar(actor: Personaje, rival: Personaje, celda_cuerda: Vector2i) -> void:
	var rebote := calcular_rebote(actor.celda, celda_cuerda)
	var puntos: Array[Vector2] = [rebote.contacto]
	if rebote.recto:
		puntos.append_array(rebote.tramo.puntos)
	else:
		puntos.append(Vector2(rebote.aterrizaje))
	if await _recorrer(actor, rival, puntos) and rebote.recto:
		actor.en_cuerdas = true
		actor.recorrido_cuerdas = rebote.tramo.largo
		actor.dir_cuerdas = rebote.tramo.dir


func _accion_en_cuerdas(actor: Personaje, rival: Personaje, celda: Vector2i, tipo: Tablero.Tipo) -> void:
	var dir := actor.dir_cuerdas
	var eje := 0 if dir.x != 0 else 1
	var contacto := Vector2(actor.celda)
	contacto[eje] = tablero.cuerda_en_rejilla(dir)
	var alcance := actor.recorrido_cuerdas + extra_por_rebote
	var puntos: Array[Vector2] = [contacto]

	if tipo == Tablero.Tipo.CUERDA:
		var tramo := _tramo_cuerdas(contacto, -dir, alcance)
		puntos.append_array(tramo.puntos)
		if await _recorrer(actor, rival, puntos):
			actor.recorrido_cuerdas = tramo.largo
			actor.dir_cuerdas = tramo.dir
		return

	# Salir: tras el rebote corre en línea recta hacia la casilla, hasta su alcance.
	var hacia := Vector2(celda) - contacto
	var fin := contacto + hacia.limit_length(alcance)
	puntos.append(Vector2(tablero.orilla_de(Vector2i(roundi(fin.x), roundi(fin.y)))))
	actor.salir_de_cuerdas()
	await _recorrer(actor, rival, puntos, true)


func _saltar(actor: Personaje, rival: Personaje, destino: Vector2i) -> void:
	if destino != rival.celda:
		await actor.saltar_desde_poste(tablero.celda_a_mundo(destino))
		actor.celda = destino
		return
	# Cae justo antes del rival, en la línea desde la esquina.
	var esquina := tablero.orilla_de(actor.celda)
	var celdas := _celdas_en_linea(Vector2(esquina), Vector2(destino))
	var antes := esquina if celdas.size() < 2 else celdas[-2]
	await actor.saltar_desde_poste(tablero.celda_a_mundo(antes))
	actor.celda = antes
	_choque = (destino - antes).sign()


## Recorre una línea quebrada (en rejilla) desde la celda del actor revisando
## choques casilla por casilla. Si choca se detiene antes del rival, guarda la
## dirección en `_choque` y devuelve false.
## `suave`: el movimiento acelera y frena (caminar); si no, velocidad constante.
func _recorrer(actor: Personaje, rival: Personaje, puntos: Array[Vector2], suave := false) -> bool:
	var visitados: Array[Vector2] = []
	var desde := Vector2(actor.celda)
	var ultima := actor.celda
	for p in puntos:
		var pasos := maxi(ceili(desde.distance_to(p) / 0.1), 1)
		for k in range(1, pasos + 1):
			var q := desde.lerp(p, float(k) / pasos)
			var c := tablero.orilla_de(Vector2i(roundi(q.x), roundi(q.y)))
			if c == ultima:
				continue
			if c == rival.celda:
				visitados.append(Vector2(ultima))
				await actor.recorrer(_a_mundo_rejilla(visitados), tablero.tam_casilla, suave)
				actor.celda = ultima
				actor.salir_de_cuerdas()
				_choque = (c - ultima).sign()
				return false
			ultima = c
		visitados.append(p)
		desde = p
	visitados[-1] = Vector2(ultima)
	await actor.recorrer(_a_mundo_rejilla(visitados), tablero.tam_casilla, suave)
	actor.celda = ultima
	return true


## Empuja al rival en `dir` tantas casillas como marque su Impacto (la orilla lo frena).
func _empujar(actor: Personaje, rival: Personaje, dir: Vector2i) -> void:
	var camino: Array[Vector3] = []
	var c := rival.celda
	for k in casillas_empuje(rival.impacto):
		var siguiente := c + dir
		if not tablero.es_interior(siguiente) or siguiente == actor.celda:
			break
		c = siguiente
		camino.append(tablero.celda_a_mundo(c))
	if camino.is_empty() and rival.en_poste:
		camino.append(tablero.celda_a_mundo(c))
	rival.celda = c
	await rival.ser_empujado(camino)


## Celdas (sin repetir, sin el origen) que toca una línea recta en la rejilla.
func _celdas_en_linea(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var celdas: Array[Vector2i] = []
	var ultima := Vector2i(roundi(a.x), roundi(a.y))
	var pasos := maxi(ceili(a.distance_to(b) / 0.1), 1)
	for k in range(1, pasos + 1):
		var q := a.lerp(b, float(k) / pasos)
		var c := Vector2i(roundi(q.x), roundi(q.y))
		if c != ultima:
			celdas.append(c)
			ultima = c
	return celdas


func _a_mundo_rejilla(puntos: Array[Vector2]) -> Array[Vector3]:
	var mundo: Array[Vector3] = []
	for p in puntos:
		mundo.append(tablero.punto_en_rejilla(p.x, p.y))
	return mundo
