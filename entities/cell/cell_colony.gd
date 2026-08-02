class_name CellColony
extends Resource

## A batch of one species for a level to spawn. Adding the third species is a
## new entry in the level's colony list, not new spawning code.

@export var scene: PackedScene
## How many to place at level start.
@export var count: int = 20
## Seconds between drip-fed extra cells. 0 for a fixed population.
@export var spawn_interval: float = 30.0
## Picked at random per cell. Leave empty to keep whatever the scene ships with.
@export var textures: Array[Texture2D] = []

@export_group("Placement")
@export var spawn_center: Vector2 = Vector2.ZERO
@export var spawn_radius: float = 700.0
## Leash radius handed to every cell, measured from spawn_center. 0 keeps the
## scene's own value.
@export var roam_radius: float = 0.0
