Blender (5.x, bpy) scripts used to build game assets. Not run by the game or tests.

slim_soldier.py  <soldier.glb> <out_dir> <triangle budget> <texture px>
    The Sketchfab soldier -> assets/soldier/: stray parts removed, meshes joined
    and decimated, idle pose baked in as rest pose, facing -Z, textures resized,
    grey (friendly) / subdued olive (enemy) texture variants.
    (assets/soldier used: budget 9500, 512 px; helmet insignia painted out after.)

extract_gait.py  <out.json> walk=<fbx> run=<fbx> injured=<fbx>
    One averaged looping cycle per mocap clip (foot paths, pitch, hip motion,
    in leg lengths) -> converted to scripts/gait_mocap.gd.
