# CJ and Gary

Downloaded on 2026-11-06 through Sketchfab's Download 3D Model controls.

- [Carl Johnson (CJ)](https://sketchfab.com/3d-models/carl-johnson-cj-647f5417720344cb8c2079edd48704ac) by [Tsaphnat Tsaphnat Mbuyi (Spider-Mbuyi)](https://sketchfab.com/tsaphnattsaphnatmbuyispidermb). The listing specifies [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Changes: normalized transforms, bone names adapted to the player animation controller, material roughness adjusted.
- [Gary the Snail](https://sketchfab.com/3d-models/gary-the-snail-67e039b5470243089c18e919366366df) by [yugengen](https://sketchfab.com/yugengen). The listing specifies [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Changes: reduced dense geometry, rescaled and reoriented, stems shortened to match the riding reference, eye pivots and hand/seat anchors added, material roughness adjusted.

CJ is a character from Rockstar Games' Grand Theft Auto: San Andreas. Gary is a character from Nickelodeon's SpongeBob SquarePants. Source files and prepared assets remain local under the ignored `Assets/Characters/` directory.

To prepare the assets, save the GLB downloads as `Assets/Characters/CJ/source/original.glb` and `Assets/Characters/Gary/source/original.glb`, then run `tools/prepare_cj_gary.py` with Blender 4.2 Python (`bpy`). The output files are `CJ/cj.glb` and `Gary/gary.glb`. Godot imports them on the next project scan. Without these optional local assets, the original player and car selection remain available.
