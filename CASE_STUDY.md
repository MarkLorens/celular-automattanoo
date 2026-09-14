# Celular Automattanoo — a study case

A predator-and-prey petri dish, built in Godot 4 / GDScript. You drop nutrients, drag a temperature gauge, and occasionally summon a species — everything else is five kinds of cell reacting to each other and to the water they're in. The round ends the moment the dish stops being an ecosystem: one side eaten out, or the other starved off.

## The Problem

The design brief was really one question: how do you get an ecosystem to feel alive without hand-scripting what each animal does to every other animal?

A petri dish needs several species that read as genuinely different — a boid-like shoal, a lurking ambush predator, a cursor-chasing hazard, a colony that rings the glass, one that orbits its own centre — while still sharing enough machinery that adding a sixth species is an afternoon, not a rewrite. On top of that, the player needed one lever, not a control panel: a single temperature dial that every species would answer to in its own way, so that one input could ripple into completely different consequences depending on who's in the dish. And the whole thing needed a fair, legible end state — the round should stop exactly when the dish genuinely can't sustain itself anymore, not a beat before or after.

Underneath the design problem sat an engine problem specific to Godot: physics deletions (`queue_free()`) don't take effect until the end of the frame, so two predators can both "see" the same prey as alive and both try to eat it in the same tick. Any predator/prey system in Godot has to design around that lag deliberately, or it silently double-counts kills and miscounts the census that decides whether the game is over.

## How It's Built

Every cell — [`entities/cell/cell.gd`](entities/cell/cell.gd) — is a `CharacterBody2D` carrying the machinery every species needs regardless of behaviour: neighbour gathering, separation, wander, the soft leash that keeps a colony inside the dish, and the idle sprite spin. A species subclass overrides exactly one method, `_steering()`, and inherits everything else. That's the whole extensibility story:

- **[Chaser](entities/cell/chaser/chaser.gd)** — drifts until prey wanders into its sensor, then commits to a timed burst of pursuit whether or not it closes the distance, and rests before it can lock on again.
- **[Flocker](entities/cell/flocker/flocker.gd)** — a tight boid shoal that reads alarm from its neighbours as much as from what it can see itself, so fear spreads colony-mate to colony-mate and a flock can blow apart from a threat most of its members never spotted.
- **[Mouser](entities/cell/mouser/mouser.gd)** — an ambient hazard that beelines for the cursor and eats anything it happens to overlap; no targeting, no sensor, just presence.
- **[Ringer](entities/cell/ringer/ringer.gd)** — settles onto a rotating shell around its colony's centre instead of filling the middle, and can turn briefly poisonous, killing whatever eats it.
- **[Edger](entities/cell/edger/edger.gd)** — lives pressed against the glass, thrives in the cold, and dies outright past a lethal temperature.

Species never perceive each other directly — cells are bucketed into a shared `static` dictionary keyed on species script (`Cell.colonies`), so a cell only ever scans its own kind. Cross-species awareness (a flocker sensing a chaser, say) goes through narrow, explicit channels instead — a group tag (`predator` / `floater`) and a dedicated sensor — rather than every cell knowing about every other species.

The single shared lever is `Cell.dish_celsius`, a static float the level writes whenever the player moves the [temperature gauge](ui/arc_meter/arc_meter.gd). Every species reads that one number and does something different with it: chasers get a flat speed boost in the cold, edgers die above a lethal threshold but breed faster below a cold one, ringers glide along a speed curve hinged at a neutral point, mousers physically swell as it drops. One input, five unrelated interpretations — which is what makes the dial feel like it's steering an ecosystem rather than a slider.

What each colony looks like — how many spawn, how fast they drip-feed, whether they're player-summonable, where they start — lives in a data resource, [`CellColony`](entities/cell/cell_colony.gd), rather than in code. The level ([`scenes/level_01/level_01.gd`](scenes/level_01/level_01.gd)) just iterates a list of these. Adding a species to a level is dragging a new resource into an array, not writing new spawn logic.

The frame-lag problem got solved once, centrally, rather than patched per-predator: `Cell.is_edible()` checks `is_queued_for_deletion()` before treating anything as available prey, and the end-of-round census walks the same check before counting a side as alive. One predator claiming prey this frame makes it invisible to every other predator checking this same frame, and the round-ending census can't be fooled by something that's technically still in the tree for one more tick.

The [`PetriDish`](entities/dish/petri_dish.gd) node is the single source of truth for the world boundary — one radius and an aspect ratio drive the painted oval, its collision wall, and the leash radius handed to every colony, so the visual glass and the invisible one can never disagree.

## What I learned

**A shared base class earns its keep when subclasses only ever add, never subtract.** Every species here needed separation, wander and containment; none needed to turn any of them off. That's what made "override one method" a real pattern instead of a leaky abstraction fighting the framework underneath it.

**One well-chosen shared variable can carry more design depth than a dozen bespoke systems.** The temperature dial isn't a system — it's a `static float` — but because five species each interpret it on their own terms, it produces the kind of cascading, ecosystem-wide consequence that usually needs a much more elaborate simulation layer to fake.

**Godot's deferred deletion is a trap worth designing around explicitly, not patching around later.** `queue_free()` not taking effect until frame's end is exactly the kind of engine behaviour that silently corrupts a predator/prey count if you don't put the check in one obvious place (`is_edible()`) and force everything through it.

**Data-driven content beats code-driven content the moment you're balancing, not building.** Once species behaviour lived in scripts and species *placement/pacing* lived in `CellColony` resources, iterating on the ecosystem's balance — more edgers, a slower ring, a later unlock — stopped touching code at all.
