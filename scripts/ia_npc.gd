extends Node
## IA sencilla del NPC: arma cartas (ataque si puede llegar junto al jugador,
## curativas si las necesita) y mezcla perseguir con movimientos aleatorios.

const Tablero = preload("res://scripts/tablero.gd")
const Personaje = preload("res://scripts/personaje.gd")
const Carta = preload("res://scripts/carta.gd")

## Segundos que "piensa" antes de actuar.
@export var pausa_pensar := 0.6
## Máximo de casillas que camina por turno cuando no va a atacar.
@export var pasos_max := 3

@export_group("Cartas")
## Probabilidad de ir a atacar cuando tiene una carta de ataque que puede pagar.
@export_range(0.0, 1.0) var prob_atacar := 0.75
## Usa Recuperación si su energía baja de este valor.
@export var energia_baja := 6
## Usa Reducción si su Impacto supera este valor.
@export var impacto_alto := 150.0
## Con Plancha en la mano (y sin otros ataques), probabilidad de ir a un poste.
@export_range(0.0, 1.0) var prob_ir_al_poste := 0.6

@export_group("Movimiento")
@export var peso_perseguir := 0.45
@export var peso_aleatorio := 0.25
@export var peso_cuerda := 0.2
@export var peso_poste := 0.1
## Al correr las cuerdas: probabilidad de seguir en lugar de salir hacia el jugador.
@export_range(0.0, 1.0) var prob_seguir_cuerdas := 0.5


## Devuelve un diccionario con lo que hará el NPC:
## `carta` (índice de la mano a armar, opcional) y `celda` + `tipo` (movimiento, opcional).
## Vacío = terminar el turno sin hacer nada.
## `gestor` es el GestorPartida (sin tipo para evitar una dependencia circular).
func elegir(npc: Personaje, jugador: Personaje, gestor) -> Dictionary:
	var tablero: Tablero = gestor.tablero
	var costo_mov := func(celda: Vector2i, tipo: Tablero.Tipo) -> int:
		var costo: int = gestor.costo_accion(npc, celda, tipo)
		return costo if costo >= 0 and costo <= npc.energia else -1

	# Arriba del poste: Plancha sobre el jugador si puede, si no salta cerca de él.
	if npc.en_poste:
		var salto: int = costo_mov.call(jugador.celda, Tablero.Tipo.INTERIOR)
		var plancha := _mejor_carta(npc, func(c: Carta) -> bool: return c.requiere_poste, npc.energia - salto)
		if salto >= 0 and plancha >= 0:
			return { "carta": plancha, "celda": jugador.celda, "tipo": Tablero.Tipo.INTERIOR }
		var mejor := {}
		var mejor_d := 999
		for celda in _interiores(tablero):
			var d: int = gestor.distancia(celda, jugador.celda)
			if costo_mov.call(celda, Tablero.Tipo.INTERIOR) >= 0 and d < mejor_d:
				mejor = { "celda": celda, "tipo": Tablero.Tipo.INTERIOR }
				mejor_d = d
		return mejor

	if npc.en_cuerdas:
		var cuerda: Vector2i = gestor.celda_cuerda_enfrente(npc)
		var ida: int = costo_mov.call(cuerda, Tablero.Tipo.CUERDA)
		if ida < 0:
			return {}
		if randf() < prob_seguir_cuerdas:
			return { "celda": cuerda, "tipo": Tablero.Tipo.CUERDA }
		var eleccion := { "celda": jugador.celda, "tipo": Tablero.Tipo.INTERIOR }
		var ataque := _mejor_carta(npc, _es_ataque_normal, npc.energia - ida)
		if ataque >= 0:
			eleccion.carta = ataque
		return eleccion

	# Cartas curativas cuando las necesita (se resuelven aunque no se mueva).
	var curativa := -1
	if npc.energia < energia_baja:
		curativa = _mejor_carta(npc, func(c: Carta) -> bool: return c.energia_extra > 0, npc.energia)
	if curativa < 0 and npc.impacto > impacto_alto:
		curativa = _mejor_carta(npc, func(c: Carta) -> bool: return c.reduce_impacto > 0.0, npc.energia)

	# Ataque: ir junto al jugador y armar el golpe más fuerte que alcance a pagar.
	if curativa < 0 and randf() < prob_atacar:
		var junto := _celda_junto_a(npc, jugador, tablero, gestor, costo_mov)
		if not junto.is_empty():
			var ataque := _mejor_carta(npc, _es_ataque_normal, npc.energia - junto.costo)
			if ataque >= 0:
				if junto.costo == 0:
					return { "carta": ataque }
				return { "carta": ataque, "celda": junto.celda, "tipo": Tablero.Tipo.INTERIOR }

	# Si no va a atacar, aprovecha cualquier carta de apoyo que le sirva ahora
	# (así no se le llena la mano de cartas sin usar).
	if curativa < 0:
		var cerca: bool = gestor.distancia(npc.celda, jugador.celda) <= 3
		curativa = _mejor_carta(npc, func(c: Carta) -> bool:
			return (c.energia_extra > 0 and npc.energia + c.energia_extra <= npc.energia_max + 2) \
				or (c.reduce_impacto > 0.0 and npc.impacto >= c.reduce_impacto / 2.0) \
				or (c.bloqueo and cerca), npc.energia)
	# Sin ataques normales en la mano: si tiene Plancha intenta subir a un poste;
	# si no, juega la carta más barata para renovar la mano.
	if curativa < 0 and _mejor_carta(npc, _es_ataque_normal, 999) < 0:
		var tiene_plancha := _mejor_carta(npc, func(c: Carta) -> bool: return c.requiere_poste, 999) >= 0
		if tiene_plancha and randf() < prob_ir_al_poste:
			var poste := _poste_libre(npc, jugador, tablero, gestor, costo_mov)
			if not poste.is_empty():
				return poste
		curativa = _mas_barata(npc, npc.energia)

	var movimiento := _movimiento(npc, jugador, tablero, gestor, costo_mov)
	if curativa >= 0:
		movimiento.carta = curativa
	return movimiento


func _es_ataque_normal(c: Carta) -> bool:
	return c.es_ataque() and not c.requiere_poste


## Índice en la mano de la carta que cumple `filtro` y cuesta <= `presupuesto`;
## si hay varias, la de más impacto (o la primera).
func _mejor_carta(npc: Personaje, filtro: Callable, presupuesto: int) -> int:
	var mejor := -1
	for i in npc.mano.size():
		var c := npc.mano[i]
		if c == null or c.costo > presupuesto or not filtro.call(c):
			continue
		if mejor < 0 or c.impacto > npc.mano[mejor].impacto:
			mejor = i
	return mejor


## El poste más barato cuya esquina no ocupa el jugador: { celda, tipo } o {}.
func _poste_libre(npc: Personaje, jugador: Personaje, tablero: Tablero, gestor, costo_mov: Callable) -> Dictionary:
	var mejor := {}
	var mejor_costo := 999
	for celda in [Vector2i(-1, -1), Vector2i(tablero.columnas, -1), Vector2i(-1, tablero.filas), Vector2i(tablero.columnas, tablero.filas)]:
		if tablero.orilla_de(celda) == jugador.celda:
			continue
		var costo: int = costo_mov.call(celda, Tablero.Tipo.POSTE)
		if costo >= 0 and costo < mejor_costo:
			mejor = { "celda": celda, "tipo": Tablero.Tipo.POSTE }
			mejor_costo = costo
	return mejor


func _mas_barata(npc: Personaje, presupuesto: int) -> int:
	var mejor := -1
	for i in npc.mano.size():
		var c := npc.mano[i]
		if c != null and c.costo <= presupuesto and (mejor < 0 or c.costo < npc.mano[mejor].costo):
			mejor = i
	return mejor


## Casilla adyacente al jugador más barata de alcanzar: { celda, costo } o {}.
func _celda_junto_a(npc: Personaje, jugador: Personaje, tablero: Tablero, gestor, costo_mov: Callable) -> Dictionary:
	if gestor.distancia(npc.celda, jugador.celda) <= 1:
		return { "celda": npc.celda, "costo": 0 }
	var mejor := {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var celda := jugador.celda + Vector2i(dx, dy)
			if celda == jugador.celda or not tablero.es_interior(celda):
				continue
			var costo: int = costo_mov.call(celda, Tablero.Tipo.INTERIOR)
			if costo >= 0 and (mejor.is_empty() or costo < mejor.costo):
				mejor = { "celda": celda, "costo": costo }
	return mejor


func _movimiento(npc: Personaje, jugador: Personaje, tablero: Tablero, gestor, costo_mov: Callable) -> Dictionary:
	var estrategias := {
		"perseguir": func() -> Dictionary: return _perseguir(npc, jugador, costo_mov),
		"aleatorio": func() -> Dictionary: return _al_azar(_opciones(tablero, gestor, npc, jugador.celda, Tablero.Tipo.INTERIOR, pasos_max, costo_mov), Tablero.Tipo.INTERIOR),
		"cuerda": func() -> Dictionary: return _al_azar(_opciones(tablero, gestor, npc, jugador.celda, Tablero.Tipo.CUERDA, pasos_max + 1, costo_mov), Tablero.Tipo.CUERDA),
		"poste": func() -> Dictionary: return _al_azar(_opciones(tablero, gestor, npc, jugador.celda, Tablero.Tipo.POSTE, 2, costo_mov), Tablero.Tipo.POSTE),
	}
	var orden: Array[String] = [_sortear(), "perseguir", "aleatorio"]
	for nombre in orden:
		var eleccion: Dictionary = estrategias[nombre].call()
		if not eleccion.is_empty():
			return eleccion
	return {}


func _sortear() -> String:
	var pesos := {
		"perseguir": peso_perseguir,
		"aleatorio": peso_aleatorio,
		"cuerda": peso_cuerda,
		"poste": peso_poste,
	}
	var total := 0.0
	for p in pesos.values():
		total += p
	var r := randf() * total
	for nombre in pesos:
		r -= pesos[nombre]
		if r <= 0.0:
			return nombre
	return "perseguir"


## Camina hacia el jugador hasta `pasos_max`; si llega, choca con él.
func _perseguir(npc: Personaje, jugador: Personaje, costo_mov: Callable) -> Dictionary:
	var celda := npc.celda
	for k in pasos_max:
		if celda == jugador.celda:
			break
		celda += (jugador.celda - celda).sign()
	if celda != npc.celda and costo_mov.call(celda, Tablero.Tipo.INTERIOR) >= 0:
		return { "celda": celda, "tipo": Tablero.Tipo.INTERIOR }
	return {}


## Celdas de un tipo a distancia <= `alcance` que el NPC puede pagar
## (sin contar la casilla `ocupada` por el jugador).
func _opciones(tablero: Tablero, gestor, npc: Personaje, ocupada: Vector2i, tipo: Tablero.Tipo, alcance: int, costo_mov: Callable) -> Array[Vector2i]:
	var opciones: Array[Vector2i] = []
	for y in range(-1, tablero.filas + 1):
		for x in range(-1, tablero.columnas + 1):
			var celda := Vector2i(x, y)
			if tablero.tipo_de(celda) != tipo:
				continue
			var objetivo := tablero.orilla_de(celda) if tipo == Tablero.Tipo.POSTE else celda
			var d: int = gestor.distancia(npc.celda, objetivo)
			if objetivo == ocupada:
				continue
			if d > 0 and d <= alcance and costo_mov.call(celda, tipo) >= 0:
				opciones.append(celda)
	return opciones


func _al_azar(opciones: Array[Vector2i], tipo: Tablero.Tipo) -> Dictionary:
	if opciones.is_empty():
		return {}
	var celda: Vector2i = opciones.pick_random()
	return { "celda": celda, "tipo": tipo }


func _interiores(tablero: Tablero) -> Array[Vector2i]:
	var celdas: Array[Vector2i] = []
	for y in tablero.filas:
		for x in tablero.columnas:
			celdas.append(Vector2i(x, y))
	return celdas
