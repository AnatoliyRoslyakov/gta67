# GTA67 — 2.0.0

Godot 4.7 city sandbox based on POLYGON City and the Truck Town vehicle controller.

Open `project.godot` and press F5 to launch the vehicle selector. Eight vehicles have individually fitted wheels, suspension and cabin cameras. Leave the car to walk, run, jump and use a pistol in first or third person.

The city has 40 moving cars, 64 pedestrians, parked cars, seven signal-controlled junctions and 24 crossings. Routes follow the actual road and sidewalk geometry. Traffic keeps right, brakes for obstructions and waits for signals; pedestrians use a protected crossing phase. This is a simplified game simulation with fixed phases, without lane changes or police pursuits. Signal and crossing behavior is based on [Florida 316.075](https://www.flsenate.gov/Laws/Statutes/2026/0316.075) and [316.130](https://www.flsenate.gov/Laws/Statutes/2026/0316.130).

A full day lasts 30 minutes: warm sunlight, long shadows, distant haze, street lamps, neon and nighttime reflections change with the clock. Nearby lights and pedestrian animation updates use distance budgets. The HUD shows the local street map, cash, wanted stars, clock, speed and ammunition. Cash and wanted stars are sandbox indicators; there is no mission economy yet.

Purchased assets are excluded from Git. Keep the supplied Godot-converted pack at `Assets/Synty/PolygonCity/` inside this project. The map is `Scenes/Demo.tscn`; cars are in `Prefabs/Vehicles/`.

This version is on branch `2.0.0`. Purchased models, textures and map files are never included in commits.

## Controls

- <kbd>WASD</kbd>: Drive or move on foot.
- <kbd>Shift</kbd>: Vehicle boost / run.
- <kbd>Space</kbd>: Brake / jump.
- <kbd>E</kbd>: Leave a stopped vehicle or enter your car when nearby.
- <kbd>C</kbd>: Exterior / cabin / top-down camera in a car; third / first person on foot.
- Mouse: Look on foot; hold right mouse to look around in a car.
- <kbd>Q</kbd>: Draw or holster the pistol. Right mouse aims; left mouse fires.
- <kbd>R</kbd>: Reload on foot / reset while driving. <kbd>F5</kbd> always restores the car.
- <kbd>M</kbd>: Advance to sunrise, day, sunset or night.
- <kbd>H</kbd>: Horn. <kbd>L</kbd>: Headlights (also switch automatically at dusk).
- <kbd>F1</kbd>: Controls. <kbd>Escape</kbd>: Vehicle selector; press again to exit.

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
