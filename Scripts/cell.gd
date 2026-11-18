extends Area2D

@onready var sprite_2d: Sprite2D = $Sprite2D

var random_color: Color

func _ready() -> void:
	add_to_group("food")
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	random_color = Color.from_hsv(rng.randf(), 0.85, 0.95)
	modulate = random_color

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		if "cell_count" in body:
			body.cell_count += 1
		if body.has_method("change_size"):
			body.change_size(0.04)
		queue_free()
