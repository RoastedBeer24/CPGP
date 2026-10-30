"""로비(src/zones/lobby/lobby.tscn)를 만드는 스크립트.

    python3 tools/gen_lobby.py

작전을 나가기 전에 모이는 개척 기지 격납고다. 가운데 전시대에서 캐릭터를 보고, 북쪽 출발 게이트로 나간다.
다시 실행하면 씬 파일을 덮어쓴다.
"""
import math
import os

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "zones", "lobby", "lobby.tscn")

WIDTH = 26.0
DEPTH = 22.0
HEIGHT = 6.0

mats = {
    "floor": ("Color(0.42, 0.43, 0.45, 1)", None, 0.8),
    "wall": ("Color(0.86, 0.86, 0.83, 1)", None, 0.7),
    "trim": ("Color(0.95, 0.76, 0.12, 1)", "Color(0.95, 0.76, 0.12, 1)", 0.5),
    "dark": ("Color(0.17, 0.18, 0.2, 1)", None, 0.6),
    "podium": ("Color(0.22, 0.23, 0.26, 1)", None, 0.4),
    "glow": ("Color(0.55, 0.85, 1, 1)", "Color(0.55, 0.85, 1, 1)", 0.3),
    "gate": ("Color(1, 0.8, 0.25, 1)", "Color(1, 0.75, 0.2, 1)", 0.3),
    "crate": ("Color(0.55, 0.5, 0.42, 1)", None, 0.85),
}
sub = []
for name, (albedo, emission, roughness) in mats.items():
    lines = ['[sub_resource type="StandardMaterial3D" id="mat_%s"]' % name, "albedo_color = %s" % albedo,
             "roughness = %s" % roughness]
    if emission:
        lines += ["emission_enabled = true", "emission = %s" % emission,
                  "emission_energy_multiplier = %s" % ("3.0" if name in ("glow", "gate") else "0.6")]
    sub.append("\n".join(lines))
sub.append("""[sub_resource type="ProceduralSkyMaterial" id="sky_material"]
sky_top_color = Color(0.18, 0.36, 0.6, 1)
sky_horizon_color = Color(0.62, 0.66, 0.68, 1)
sky_energy_multiplier = 0.8""")
sub.append("""[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_material")""")
sub.append("""[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 3
ambient_light_energy = 1.2
tonemap_mode = 3
glow_enabled = true
glow_bloom = 0.1""")
sub.append("""[sub_resource type="CylinderMesh" id="podium_mesh"]
material = SubResource("mat_podium")
top_radius = 2.2
bottom_radius = 2.4
height = 0.3""")
sub.append("""[sub_resource type="TorusMesh" id="ring_mesh"]
material = SubResource("mat_glow")
inner_radius = 2.15
outer_radius = 2.25""")
sub.append("""[sub_resource type="CylinderShape3D" id="podium_shape"]
radius = 2.4
height = 0.3""")

nodes = []


def tf(pos, rot_y_deg=0.0):
    ay = math.radians(rot_y_deg)
    cy, sy = math.cos(ay), math.sin(ay)
    m = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    f = lambda v: "%.6g" % v
    # tscn의 Transform3D 기저는 행 우선으로 적는다.
    basis = ", ".join(f(m[r][c]) for r in range(3) for c in range(3))
    return "Transform3D(%s, %s, %s, %s)" % (basis, f(pos[0]), f(pos[1]), f(pos[2]))


def box(name, parent, pos, size, mat, collide=True, rot_y=0.0):
    lines = ['[node name="%s" type="CSGBox3D" parent="%s"]' % (name, parent), "transform = %s" % tf(pos, rot_y)]
    if collide:
        lines.append("use_collision = true")
    lines.append("size = Vector3(%s, %s, %s)" % tuple(size))
    lines.append('material = SubResource("mat_%s")' % mat)
    nodes.append("\n".join(lines))


def label(name, parent, pos, text, size, color="Color(1, 1, 1, 1)", rot_y=0.0):
    nodes.append('[node name="%s" type="Label3D" parent="%s"]\ntransform = %s\nmodulate = %s\nfont_size = %d\noutline_size = 12\ntext = "%s"'
                 % (name, parent, tf(pos, rot_y), color, size, text))


def light(name, pos, color, energy, size):
    nodes.append('[node name="%s" type="OmniLight3D" parent="Lights"]\ntransform = %s\nlight_color = %s\nlight_energy = %s\nomni_range = %s'
                 % (name, tf(pos), color, energy, size))


nodes.append('[node name="Lobby" type="Node3D"]\nscript = ExtResource("lobby")')
nodes.append('[node name="Environment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")')
# 해: 거의 머리 위에서(70도) 비춰 벽 그림자가 바닥을 덮지 않게 한다.
pitch, yaw = math.radians(-70), math.radians(25)
cp, sp, cy, sy = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw)
rx = [[1, 0, 0], [0, cp, -sp], [0, sp, cp]]
ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
sun = [[sum(ry[r][k] * rx[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
sun_basis = ", ".join("%.6g" % sun[r][c] for r in range(3) for c in range(3))
nodes.append('[node name="Sun" type="DirectionalLight3D" parent="."]\ntransform = Transform3D(%s, 0, 12, 0)\n'
             'light_color = Color(1, 0.95, 0.88, 1)\nlight_energy = 1.2\nshadow_enabled = true' % sun_basis)

nodes.append('[node name="SpawnPoints" type="Node3D" parent="."]')
for i, x in enumerate([0.0, 2.2, -2.2]):
    nodes.append('[node name="Spawn%d" type="Marker3D" parent="SpawnPoints"]\ntransform = %s' % (i + 1, tf((x, 0.05, 6.0), 180)))

nodes.append('[node name="Geometry" type="Node3D" parent="."]')
box("Floor", "Geometry", (0, -0.5, 0), (WIDTH, 1, DEPTH), "floor")
box("WallW", "Geometry", (-WIDTH / 2, HEIGHT / 2, 0), (0.6, HEIGHT, DEPTH), "wall")
box("WallE", "Geometry", (WIDTH / 2, HEIGHT / 2, 0), (0.6, HEIGHT, DEPTH), "wall")
box("WallS", "Geometry", (0, HEIGHT / 2, DEPTH / 2), (WIDTH, HEIGHT, 0.6), "wall")
# 북쪽 벽은 가운데에 출발 게이트를 남기고 양쪽만 막는다.
box("WallNW", "Geometry", (-8.5, HEIGHT / 2, -DEPTH / 2), (9, HEIGHT, 0.6), "wall")
box("WallNE", "Geometry", (8.5, HEIGHT / 2, -DEPTH / 2), (9, HEIGHT, 0.6), "wall")
box("Lintel", "Geometry", (0, HEIGHT - 0.6, -DEPTH / 2), (8, 1.2, 0.6), "wall")
for name, x in [("TrimW", -WIDTH / 2 + 0.31), ("TrimE", WIDTH / 2 - 0.31)]:
    box(name, "Geometry", (x, 1.2, 0), (0.04, 0.2, DEPTH), "trim", collide=False)
box("TrimS", "Geometry", (0, 1.2, DEPTH / 2 - 0.31), (WIDTH, 0.2, 0.04), "trim", collide=False)
# 출발 게이트: 빛나는 문틀과 바닥 띠. 게이트 너머는 막아 둔다.
box("GateLeft", "Geometry", (-4.1, 2.5, -DEPTH / 2), (0.4, 5, 0.8), "gate", collide=False)
box("GateRight", "Geometry", (4.1, 2.5, -DEPTH / 2), (0.4, 5, 0.8), "gate", collide=False)
box("GateTop", "Geometry", (0, 5.0, -DEPTH / 2), (8.6, 0.4, 0.8), "gate", collide=False)
box("GateBarrier", "Geometry", (0, 2.5, -DEPTH / 2 - 0.4), (8, 5, 0.2), "dark")
box("GateStrip", "Geometry", (0, 0.01, -DEPTH / 2 + 1.5), (8, 0.02, 0.3), "gate", collide=False)
label("GateSign", "Geometry", (0, 5.9, -DEPTH / 2 + 0.5), "출발 게이트", 160, "Color(1, 0.85, 0.3, 1)")
label("BaseSign", "Geometry", (0, 4.2, DEPTH / 2 - 0.4), "크로스필드 개척 전초기지", 140, "Color(1, 1, 1, 1)", 180)
# 가운데 전시대: 캐릭터를 보는 자리
nodes.append('[node name="Podium" type="MeshInstance3D" parent="Geometry"]\ntransform = %s\nmesh = SubResource("podium_mesh")' % tf((0, 0.15, -1.0)))
nodes.append('[node name="PodiumRing" type="MeshInstance3D" parent="Geometry"]\ntransform = %s\nmesh = SubResource("ring_mesh")' % tf((0, 0.31, -1.0)))
nodes.append('[node name="PodiumBody" type="StaticBody3D" parent="Geometry"]\ntransform = %s' % tf((0, 0.15, -1.0)))
nodes.append('[node name="Shape" type="CollisionShape3D" parent="Geometry/PodiumBody"]\nshape = SubResource("podium_shape")')
# 꾸밈: 상자와 기계
for i, (x, z, rot) in enumerate([(-10, -6, 10), (-10.5, -3.5, -5), (10, 4, 20), (9.5, -7, 0), (-9.5, 7, 15)]):
    box("Crate%d" % (i + 1), "Geometry", (x, 0.7, z), (1.6, 1.4, 1.6), "crate", rot_y=rot)
box("Console", "Geometry", (6, 0.6, -6), (2.4, 1.2, 1.0), "dark", rot_y=-20)
box("ConsoleScreen", "Geometry", (6, 1.25, -5.55), (2.0, 0.1, 0.6), "glow", collide=False, rot_y=-20)

nodes.append('[node name="Lights" type="Node3D" parent="."]')
light("PodiumLight", (0, 4.5, -1), "Color(1, 0.95, 0.85, 1)", 3.0, 9.0)
light("GateLight", (0, 3.0, -DEPTH / 2 + 1.5), "Color(1, 0.8, 0.4, 1)", 2.0, 8.0)
light("HallLightW", (-7, 4.5, 3), "Color(0.9, 0.95, 1, 1)", 2.0, 12.0)
light("HallLightE", (7, 4.5, 3), "Color(0.9, 0.95, 1, 1)", 2.0, 12.0)
light("HallLightS", (0, 4.5, 8), "Color(0.9, 0.95, 1, 1)", 2.0, 12.0)

header = '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://src/zones/lobby/lobby.gd" id="lobby"]\n'
text = header + "\n" + "\n\n".join(sub) + "\n\n" + "\n\n".join(nodes) + "\n"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)
print(os.path.normpath(out))
