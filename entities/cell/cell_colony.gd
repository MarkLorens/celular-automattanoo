class_name CellColony
extends Resource

## A batch of one species for a level to spawn. Adding the third species is a
## new entry in the level's colony list, not new spawning code.

@export var scene: PackedScene
## How many to place at level start.
@export var count: int = 20
## Seconds between drip-fed extra cells. 0 for a fixed population.
@export var spawn_interval: float = 0.0
## Seconds before the first drip-fed cell arrives, which is how a species gets
## introduced partway into a run rather than ticking from the off. Negative
## means "however long spawn_interval is", the usual case -- keeping the two
## apart only matters when a colony appears on one schedule and repeats on
## another.
@export var first_spawn_delay: float = -1.0
## Drip-feeding stops once the dish reaches this temperature. Only the automatic
## spawn is affected -- a species that breeds by some other route, as flockers do
## off nutrients, keeps doing so in the heat. Left above the gauge's ceiling the
## colony never stops, which is every colony that has not asked to care.
@export var halts_at_celsius: float = 1000.0
## Ceiling on how many of this colony may be alive at once. 0 for no ceiling.
## The drip feed keeps running underneath it, so a species capped at one is a
## single specimen that comes back an interval after something kills it, rather
## than a one-off that is gone for good.
@export var max_population: int = 0
## Picked at random per cell. Leave empty to keep whatever the scene ships with.
@export var textures: Array[Texture2D] = []

@export_group("Summoning")
## Input action that drops one of these at the cursor on demand, the same way the
## nutrient works. Empty means this colony cannot be summoned -- it only ever
## arrives on its own drip-feed clock. Naming an action is all it takes to make a
## species player-summonable; the level wires the rest.
@export var summon_action: StringName = &""
## Seconds of play before the summon unlocks. 0 makes it available from the off.
@export var summon_unlock_at: float = 0.0
## Seconds between summons once unlocked.
@export var summon_cooldown: float = 0.0

@export_group("Placement")
## Drop this colony's cells in the band just inside the glass rather than out in
## the medium -- where a species that lives on the rim ought to arrive. Beats
## spawn_anywhere and the patch alike when it is on.
@export var spawn_at_rim: bool = false
## How deep that band runs, as a fraction of the way in from the leash. 0 puts
## every cell exactly on it; 0.15 scatters them through the outer sixth.
@export_range(0.0, 1.0, 0.01) var spawn_rim_depth: float = 0.15
## Scatter this colony across the whole dish rather than the patch below. On by
## default: a colony is a species, not a territory, so prey and predator alike
## start life anywhere in the glass.
@export var spawn_anywhere: bool = true
## Where the colony starts when spawn_anywhere is off. Also the centre of its
## territory whenever roam_radius asks for one.
@export var spawn_center: Vector2 = Vector2.ZERO
@export var spawn_radius: float = 700.0
## Optional territory: confine this colony to its own patch of this radius
## around spawn_center. 0 lets its cells roam the entire dish, which is usually
## what you want -- spawning somewhere should not mean living there.
@export var roam_radius: float = 0.0
