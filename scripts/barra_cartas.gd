extends HBoxContainer
## Barra inferior de cartas: [zona de juego] [mano 0] [mano 1] [mano 2].
## Muestra la mano del jugador y avisa cuando arma o devuelve una carta.

const Personaje = preload("res://scripts/personaje.gd")
const Ranura = preload("res://scripts/ranura_carta.gd")

signal carta_armada(indice_mano: int)
signal carta_devuelta(indice_mano: int)

var _personaje: Personaje
var _ranuras: Array[Ranura] = []


func _ready() -> void:
	for i in range(Ranura.ZONA_JUEGO, Personaje.TAM_MANO):
		var ranura := Ranura.new(i)
		ranura.soltada.connect(_on_soltada)
		add_child(ranura)
		_ranuras.append(ranura)


func configurar(personaje: Personaje) -> void:
	_personaje = personaje
	personaje.cartas_cambiadas.connect(_refrescar)
	personaje.energia_cambiada.connect(func(_a: int, _m: int) -> void: _refrescar())
	_refrescar()


func set_habilitada(habilitada: bool) -> void:
	for ranura in _ranuras:
		ranura.habilitada = habilitada
	modulate = Color.WHITE if habilitada else Color(1, 1, 1, 0.7)


func _refrescar() -> void:
	var energia := _personaje.energia
	var en_juego := _personaje.carta_en_juego
	_ranuras[0].mostrar(en_juego, en_juego == null or en_juego.costo <= energia)
	for i in Personaje.TAM_MANO:
		var c := _personaje.mano[i]
		_ranuras[i + 1].mostrar(c, c == null or c.costo <= energia)


func _on_soltada(origen: int, destino: int) -> void:
	if destino == Ranura.ZONA_JUEGO:
		carta_armada.emit(origen)
	elif origen == Ranura.ZONA_JUEGO:
		carta_devuelta.emit(destino)
