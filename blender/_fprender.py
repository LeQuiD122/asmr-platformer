import bpy, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import gen_footprint as gen
gen.clear_scene()
a = gen.build(); a.location = (-0.8, 0, 0)
b = gen.build(); b.location = (0.9, 0.4, 0); b.rotation_euler = (0,0,math.radians(8))
cam_data = bpy.data.cameras.new("Cam"); cam_data.lens = 50
cam = bpy.data.objects.new("Cam", cam_data)
cam.location = (0.0, -3.4, 2.6); cam.rotation_euler = (math.radians(52), 0, 0)
bpy.context.collection.objects.link(cam); bpy.context.scene.camera = cam
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"; sc.render.resolution_x = 900; sc.render.resolution_y = 700
sc.render.filepath = os.path.join(HERE, "footprint_preview.png")
sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "SINGLE"; sh.single_color = (0.85, 0.62, 0.24)
sh.show_shadows = True; sh.show_cavity = True; sh.cavity_type = "BOTH"
bpy.ops.render.render(write_still=True)
print("wrote", sc.render.filepath)
