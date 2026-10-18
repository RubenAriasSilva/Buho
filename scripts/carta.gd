extends Resource
## Una carta jugable. Se arma en la zona de juego y se resuelve al final del
## movimiento del turno (los ataques solo si el rival queda dentro del alcance).

enum Categoria { BASICA, CURATIVA, ESPECIAL, DEFENSA }

@export var nombre := "Carta"
@export var categoria := Categoria.BASICA
@export_multiline var descripcion := ""
## Energía que cuesta activarla.
@export var costo := 1

@export_group("Ataque")
## Impacto (%) total que suma al rival; se reparte entre `golpes`.
@export var impacto := 0.0
@export var golpes := 1
## Distancia (tipo rey) máxima al rival para conectar.
@export var alcance := 1
## Solo funciona si el turno empezó arriba del poste (p. ej. Plancha).
@export var requiere_poste := false

@export_group("Efectos propios")
@export var energia_extra := 0
## Impacto (%) que se quita a sí mismo.
@export var reduce_impacto := 0.0
## Reduce a la mitad el siguiente impacto recibido (hasta su próximo turno).
@export var bloqueo := false


func es_ataque() -> bool:
	return impacto > 0.0


## Texto corto del efecto para mostrar en la carta.
func efecto_corto() -> String:
	if es_ataque():
		return "+%d%%" % roundi(impacto) if golpes == 1 else "%d×%d%%" % [golpes, roundi(impacto / golpes)]
	if energia_extra > 0:
		return "+%d energía" % energia_extra
	if reduce_impacto > 0.0:
		return "-%d%%" % roundi(reduce_impacto)
	if bloqueo:
		return "½ impacto"
	return ""
