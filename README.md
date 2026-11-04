# GTA67 — 2.0.1

Godot 4.7 city sandbox based on POLYGON City and the Truck Town vehicle controller.

Open `project.godot` and press F5 to launch the vehicle selector. Nine vehicle choices have individually fitted wheels, suspension and cabin cameras. Leave the car to walk, run, jump and use a pistol in first or third person.

The city has 40 civilian cars, 64 pedestrians, parked cars, seven signal-controlled junctions and 24 crossings. Routes follow the actual road and sidewalk geometry. Traffic keeps right, brakes for obstructions and waits for signals; pedestrians use a protected crossing phase. Civilian traffic uses fixed phases without lane changes. Cars steer through rounded corners with a speed-dependent bicycle model, brake before turns and maintain gaps based on vehicle length. Seven civilian model types spawn in shuffled batches with varied paint tints, acceleration, cruising speed and following distance; each session randomizes routing. Model-sized colliders and three obstacle rays cover the car body, while dead-end lane branches are removed from the driving network. Signal and crossing behavior is based on [Florida 316.075](https://www.flsenate.gov/Laws/Statutes/2026/0316.075) and [316.130](https://www.flsenate.gov/Laws/Statutes/2026/0316.130).

A full day lasts 30 minutes: warm sunlight, long shadows, distant haze, street lamps, neon and nighttime reflections change with the clock. Nearby lights and pedestrian animation updates use distance budgets. The HUD shows the local street map, GPS route, objective, patrol positions, cash, wanted stars, clock, speed, vehicle condition and ammunition.

Open the city menu with Tab or Escape to take a delivery or a timed street circuit. Deliveries pay from $180 plus distance; the fixed circuit pays from $320 plus distance. Both award another $100 for avoiding damage. Drive to the circuit start and press F while stopped; the timer starts there, so personal best times compare the same route. GPS follows connected road lanes and reroutes when you leave the route.

Gunfire and serious collisions caused by the player attract one to three police cars. Break line of sight and stay hidden to lose wanted stars; nearby patrols can arrest a stopped player after four seconds. Repair the car, recover health and refill ammunition at the cyan S service marker using earned cash. Severe damage reduces engine power; a wreck requires recovery. Arrest costs up to $200, medical help up to $100 and vehicle recovery up to $75, capped by the current balance so the player cannot become stuck without funds.

Cash, completed jobs, circuit record, ammunition, health and each selected car's condition save automatically in `user://gta67_progress.json`. Progress is saved after transactions, every 20 seconds and on exit; active jobs and police pursuits are session-only. Pausing freezes city traffic and mission timers. Selecting a different car cancels an active job and is unavailable during a pursuit.

The city menu includes Economy, Balanced and Quality graphics presets, saved locally in `user://gta67_graphics.cfg`. Balanced is the default: 60 FPS, native 3D resolution, 2× MSAA, two sun-shadow cascades and bounded nearby lighting. Economy targets 30 FPS with 80% 3D resolution and smaller light budgets; Quality retains 4× MSAA and four sun-shadow cascades at 60 FPS. The UI stays at full resolution. Paused/selector windows are capped at 30 FPS and unfocused windows at 15 FPS; losing focus pauses gameplay.

Resources load in background threads with a progress overlay and are reused when changing cars. Small static props are distance-culled; buildings, roads and collision bodies remain. Traffic searches spatial buckets instead of scanning every car. Obstacle sensing runs at 20 Hz for cars and 12 Hz for pedestrians, while collisions and driving physics remain at 120 Hz. Offscreen animation, HUD, light and reflection updates have separate budgets. Audio buffers and police routes are shared; silent sirens stop playback. Unchanged progress no longer causes repeated disk writes.

On the development Mac (M1 Pro, 1280×720, stationary day/night views, equal 60 FPS cap), physics processing fell from about 4.4 ms to 3.4–3.5 ms and daytime draw calls from about 2,562 to 1,776. These short scene measurements are not a thermal endurance test; performance varies with camera, resolution and hardware.

Purchased assets are excluded from Git. Keep the supplied Godot-converted pack at `Assets/Synty/PolygonCity/` inside this project. The map is `Scenes/Demo.tscn`; cars are in `Prefabs/Vehicles/`.

This version is on branch `2.0.1`. Purchased models, textures and map files are never included in commits.

## Controls

- <kbd>WASD</kbd>: Drive or move on foot.
- <kbd>Shift</kbd>: Vehicle boost / run.
- <kbd>Space</kbd>: Brake / jump.
- <kbd>E</kbd>: Leave a stopped vehicle or enter your car when nearby.
- <kbd>C</kbd>: Exterior / cabin / top-down camera in a car; third / first person on foot.
- Arrow keys: Look around on foot and in exterior/cabin car views. Mouse also looks on foot; hold right mouse to look around in a car.
- <kbd>Q</kbd>: Draw or holster the pistol. Right mouse aims; left mouse fires.
- <kbd>R</kbd>: Reload on foot / recover while driving. <kbd>F5</kbd>: Recover the car (up to $75, cancels the current job, unavailable during pursuit).
- <kbd>F</kbd>: Pick up / deliver a parcel, start the circuit or use the nearby service.
- <kbd>Tab</kbd> or <kbd>Escape</kbd>: Pause and open the city jobs menu. Escape resumes. Choose a different car from this menu.
- <kbd>M</kbd>: Advance to sunrise, day, sunset or night.
- <kbd>J</kbd>: Toggle UAZ-469 hover mode: all four wheels folding, cyan neon and road underglow. WASD steers/drives; Space brakes. Press J again to land. Leaving the car or wrecking it disables hover.
- <kbd>H</kbd>: Horn. <kbd>L</kbd>: Headlights (also switch automatically at dusk).
- <kbd>F1</kbd>: Controls. Escape from the vehicle selector exits the game.

Desktop keyboard and mouse are the primary controls. The inherited controller support covers driving; the new on-foot actions require keyboard and mouse.

Language: GDScript

Renderer: Forward+

Check out this demo on the Asset Store: https://store.godotengine.org/asset/godot-foundation/truck-town-demo/

## How does it work?

The player car uses `VehicleBody3D` with model-specific wheel centers and suspension. Citizens and traffic use `CharacterBody3D`; their routes are derived from the imported map at runtime. Character poses are procedural because the supplied character clips contain only static keys. All material, light and rig changes are applied at runtime without editing the purchased source files.

## Credits

### Ambient sounds

- [Sunrise](https://freesound.org/people/nyoz/sounds/614202/) by nyoz
- [Day](https://freesound.org/people/pawsound/sounds/154880/) by pawsound
- [Sunset](https://freesound.org/people/roisin.gleeson/sounds/699131/) by roisin.gleeson
- [Night](https://freesound.org/people/DidntGoToFilmSchool/sounds/248103/) by DidntGoToFilmSchool

## Models

- [tree low-poly](https://sketchfab.com/3d-models/tree-low-poly-4cd243eb74c74b3ea2190ebcec0439fb) by Ricardo Sanchez (https://sketchfab.com/380660711785)
- [Lowpoly lamp](https://sketchfab.com/3d-models/lowpoly-lamp-c020f6af78f7482f8cf2ac84d05c08a5) by RitiWox (https://sketchfab.com/RitiWox)

## Russian vehicles

Version 2.0.1 retains UAZ-469 as the only Russian vehicle in the selector and civilian traffic. It uses four-wheel drive, authored cabin and materials, shared wheel resources and automatically generated mesh LODs. The VAZ variants and Bukhanka have been removed from the project.

Purchased POLYGON City models remain local. The UAZ geometry is original; historical source attribution is retained in `vehicles/russian/LICENSE.txt`.

The UAZ-469 soft-top has a separate Blender source in `vehicles/russian/source/uaz469.blend` (excluded from Godot importing by `.gdignore`). Its body was rebuilt around the early 469 silhouette: 2.38 m wheelbase, 1.785 m front-wing width, approximately 4.026 m overall length and 2.058 m height including cloth seams. Mirrors extend beyond the nominal body width. The rounded bonnet and wings, twin horizontal mesh grille openings, split windscreen with top-mounted wipers, external hinges, dual filler caps, canvas fasteners, spare tire and period cabin are geometry. The finish is matte protective olive with restrained localized corrosion; it is not a factory paint color calibration.

Rebuild only this model with `python tools/build_uaz469.py` in a Python environment with Blender's `bpy` 4.2 (or use `blender --background --factory-startup --python tools/build_uaz469.py`), then run `Godot --headless --path . --script res://tools/import_uaz469.gd`. The intermediate GLB is written to `/tmp/gta67_uaz469.glb`. The importer saves native resources, shared wheels, LODs and camera/lamp mounting metadata. Other cars are unaffected.

Shape references: [1972 UAZ-469B photographs](https://auta5p.eu/srazy/roztoky_2003/roztoky_277.php), [windscreen and bonnet close-up](https://commons.wikimedia.org/wiki/File:UAZ-469_(front).jpg), [UAZ factory family dimension drawings](https://www.uaz.ru/uploads/content/2018.4/preview_2_2014224_2-17.re_31512.pdf). Photographs are references only and are not bundled. Modeling workflow: [Blender Modeling skill](https://github.com/RobLe3/cc-blender-skill/blob/main/plugin/skills/blender-modeling/SKILL.md).
