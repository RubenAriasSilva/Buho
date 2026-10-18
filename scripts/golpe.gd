extends Resource
## Un golpe en tiempo real: cuesta energía, suma Impacto si el rival está dentro
## del alcance y deja al atacante en recarga unos instantes.

@export var nombre := "Golpe"
@export var costo := 2
## Impacto (%) que suma al rival si conecta.
@export var impacto := 10.0
## Distancia máxima (metros) entre los luchadores para conectar.
@export var alcance := 1.0
## Segundos antes de poder volver a golpear.
@export var recarga := 0.4
@export var color := Color(1, 0.6, 0.3)
