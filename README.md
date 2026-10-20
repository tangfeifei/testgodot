# Wildlands - Ancient Grove

A small Godot 4 third-person fantasy exploration prototype. The world is
generated from GDScript, with the player using KayKit's rigged Knight model.
The model's CC0 license is included in `assets/kaykit/LICENSE.txt`.

## Run

Open this folder in Godot 4.2 or later, then press **F6** or **F5** to run the
main scene. The project uses the Compatibility renderer.

Generated terrain chunks are saved to `user://generated_terrain.scn` when the
game exits and loaded on the next launch. Remove that file from the Godot user
data folder to regenerate the terrain cache.

## Controls

- **WASD** — move
- **Shift** — sprint
- **Space** — jump
- **Hold E** — grab and climb a nearby tree; use **W/S** to climb up or down
- **Mouse** — orbit the camera
- **Escape** — release or recapture the mouse

Explore the hilly forest, find the glowing ancient beacon, and collect all five
spirit crystals.
