"""첫 전투 방(src/zones/combat_room/combat_room.tscn)을 만드는 스크립트.

    python3 tools/gen_combat_room.py

탈로스-II 개척 기지의 마당 같은 그레이박스 전투장이다. 좌표를 정확히 맞추려고 씬 파일을 코드로 만든다.
다시 실행하면 씬 파일을 덮어쓰므로, 에디터에서 직접 고쳤다면 이 스크립트에도 같이 반영해야 한다.
"""
import math
import os

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "zones", "combat_room", "combat_room.tscn")

# 넓이: 바닥 한 변(m)과 울타리 높이
SIZE = 44.0
WALL_HEIGHT = 3.2

mats = {
    "floor": ("Color(0.36, 0.37, 0.38, 1)", None, 0.9),
    "plate": ("Color(0.3, 0.31, 0.33, 1)", None, 0.8),
    "wall": ("Color(0.8, 0.8, 0.76, 1)", None, 0.7),
    "trim": ("Color(0.95, 0.76, 0.12, 1)", "Color(0.95, 0.76, 0.12, 1)", 0.6),
    "pillar": ("Color(0.24, 0.25, 0.28, 1)", None, 0.6),
    "crate": ("Color(0.55, 0.5, 0.42, 1)", None, 0.85),
    "stripe": ("Color(0.95, 0.8, 0.15, 1)", None, 0.7),
    "crystal": ("Color(1, 0.55, 0.12, 1)", "Color(1, 0.5, 0.1, 1)", 0.3),
}

sub = []
for name, (albedo, emission, roughness) in mats.items():
    lines = ['[sub_resource type="StandardMaterial3D" id="mat_%s"]' % name, "albedo_color = %s" % albedo,
             "roughness = %s" % roughness]
    if emission:
        lines += ["emission_enabled = true", "emission = %s" % emission,
                  "emission_energy_multiplier = %s" % ("2.5" if name == "crystal" else "0.6")]
    sub.append("\n".join(lines))

sub.append("""[sub_resource type="ProceduralSkyMaterial" id="sky_material"]
sky_top_color = Color(0.18, 0.36, 0.6, 1)
sky_horizon_color = Color(0.62, 0.66, 0.68, 1)
sky_energy_multiplier = 0.8
ground_bottom_color = Color(0.2, 0.19, 0.18, 1)
ground_horizon_color = Color(0.7, 0.66, 0.58, 1)
sun_angle_max = 20.0""")
sub.append("""[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_material")""")
sub.append("""[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 3
ambient_light_energy = 0.9
tonemap_mode = 3
glow_enabled = true
glow_bloom = 0.08
fog_enabled = true
fog_light_color = Color(0.6, 0.64, 0.68, 1)
fog_density = 0.0025""")
# 적의 길찾기 지도. "navigation_geometry" 그룹의 충돌 지형으로 실행할 때 굽는다(src/zones/zone.gd).
sub.append("""[sub_resource type="NavigationMesh" id="navmesh"]
geometry_parsed_geometry_type = 1
geometry_collision_mask = 1
geometry_source_geometry_mode = 1
geometry_source_group_name = &"navigation_geometry"
agent_height = 2.0
agent_radius = 0.6
agent_max_climb = 0.25
agent_max_slope = 30.0""")
sub.append("""[sub_resource type="PrismMesh" id="crystal_mesh"]
material = SubResource("mat_crystal")
size = Vector3(0.6, 1.6, 0.6)""")
sub.append("""[sub_resource type="SceneReplicationConfig" id="room_sync"]
properties/0/path = NodePath(".:phase")
properties/0/spawn = true
properties/0/replication_mode = 2
properties/1/path = NodePath(".:wave")
properties/1/spawn = true
properties/1/replication_mode = 2
properties/2/path = NodePath(".:enemies_left")
properties/2/spawn = true
properties/2/replication_mode = 2""")

nodes = []


def tf(pos, rot_x_deg=0.0, rot_y_deg=0.0, rot_z_deg=0.0):
    ax, ay, az = math.radians(rot_x_deg), math.radians(rot_y_deg), math.radians(rot_z_deg)
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
    m = mul(ry, mul(rx, rz))
    f = lambda v: "%.6g" % v
    # tscn의 Transform3D 기저는 행 우선으로 적는다(행렬의 첫 행, 둘째 행, 셋째 행 순서).
    basis = ", ".join(f(m[r][c]) for r in range(3) for c in range(3))
    return "Transform3D(%s, %s, %s, %s)" % (basis, f(pos[0]), f(pos[1]), f(pos[2]))


def box(name, parent, pos, size, mat, collide=True, rot_y=0.0):
    lines = ['[node name="%s" type="CSGBox3D" parent="%s"]' % (name, parent)]
    lines.append("transform = %s" % tf(pos, 0.0, rot_y))
    if collide:
        lines.append("use_collision = true")
    lines.append("size = Vector3(%s, %s, %s)" % tuple(size))
    lines.append('material = SubResource("mat_%s")' % mat)
    nodes.append("\n".join(lines))


def group(name, parent=".", groups=None):
    attr = (" groups=[" + ", ".join('"%s"' % g for g in groups) + "]") if groups else ""
    nodes.append('[node name="%s" type="Node3D" parent="%s"%s]' % (name, parent, attr))


def marker(name, parent, pos, yaw=0.0):
    nodes.append('[node name="%s" type="Marker3D" parent="%s"]\ntransform = %s' % (name, parent, tf(pos, 0.0, yaw)))


nodes.append('[node name="CombatRoom" type="Node3D"]\nscript = ExtResource("room")')
nodes.append('[node name="Navigation" type="NavigationRegion3D" parent="."]\nnavigation_mesh = SubResource("navmesh")')
nodes.append('[node name="Environment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")')
nodes.append('[node name="Sun" type="DirectionalLight3D" parent="."]\ntransform = %s\nlight_color = Color(1, 0.94, 0.84, 1)\n'
             'light_energy = 1.1\nshadow_enabled = true\ndirectional_shadow_max_distance = 60.0' % tf((0, 20, 0), -50, 35))

# 플레이어 시작 자리: 남쪽(+Z)에서 가운데를 본다.
group("SpawnPoints")
for i, x in enumerate([0.0, 2.0, -2.0]):
    marker("Spawn%d" % (i + 1), "SpawnPoints", (x, 0.05, 13.0))

# 적이 나오는 자리: 북쪽과 양옆
group("EnemySpawns")
spawn_points = [(-12, -14), (0, -16), (12, -14), (-17, -4), (17, -4), (-16, 8), (16, 8), (-6, -10), (6, -10)]
for i, (x, z) in enumerate(spawn_points):
    marker("EnemySpawn%d" % (i + 1), "EnemySpawns", (x, 0.05, z))

group("Geometry", groups=["navigation_geometry"])
half = SIZE / 2.0
box("Floor", "Geometry", (0, -0.5, 0), (SIZE, 1, SIZE), "floor")
# 바닥 판: 가운데 원형 전투장 느낌을 내는 넓은 판(높이 차이 없음)
box("CenterPlate", "Geometry", (0, 0.005, 0), (20, 0.01, 20), "plate", collide=False, rot_y=45)
# 울타리 (흰 판 + 노란 띠)
for name, pos, size in [
    ("WallN", (0, WALL_HEIGHT / 2, -half), (SIZE, WALL_HEIGHT, 1)),
    ("WallS", (0, WALL_HEIGHT / 2, half), (SIZE, WALL_HEIGHT, 1)),
    ("WallW", (-half, WALL_HEIGHT / 2, 0), (1, WALL_HEIGHT, SIZE)),
    ("WallE", (half, WALL_HEIGHT / 2, 0), (1, WALL_HEIGHT, SIZE)),
]:
    box(name, "Geometry", pos, size, "wall")
    trim_size = (size[0] + 0.02, 0.25, size[2] + 0.02)
    box(name + "Trim", "Geometry", (pos[0], WALL_HEIGHT - 0.4, pos[2]), trim_size, "trim", collide=False)

# 기둥 네 개: 적의 공격을 피해 돌아 들어가거나, 원거리 적의 탄을 막는다.
for i, (x, z) in enumerate([(-8, -8), (8, -8), (-8, 6), (8, 6)]):
    box("Pillar%d" % (i + 1), "Geometry", (x, 2.0, z), (1.8, 4.0, 1.8), "pillar")
    box("PillarStripe%d" % (i + 1), "Geometry", (x, 1.0, z), (1.84, 0.3, 1.84), "stripe", collide=False)

# 낮은 상자: 넘어가지는 못하지만 몸을 가린다.
for i, (x, z, rot) in enumerate([(0, -12, 0), (-14, 2, 30), (14, -2, -20), (-4, 16, 0), (5, 15.5, 15)]):
    box("Crate%d" % (i + 1), "Geometry", (x, 0.6, z), (2.4, 1.2, 1.2), "crate", rot_y=rot)

# 원석 결정 무더기(꾸밈, 부딪히지 않음): 울타리 가장자리
group("Crystals")
for i, (x, z, s) in enumerate([(-19, -18, 1.4), (18, -19, 1.1), (-19.5, 14, 1.0), (19, 12, 1.3), (-2, -19.5, 0.9)]):
    for k in range(3):
        angle = k * 2.1
        px, pz = x + math.cos(angle) * 0.6 * s, z + math.sin(angle) * 0.6 * s
        nodes.append('[node name="Crystal%d_%d" type="MeshInstance3D" parent="Crystals"]\ntransform = %s\nmesh = SubResource("crystal_mesh")'
                     % (i + 1, k + 1, tf((px, 0.6 * s, pz), 12 * math.cos(angle), angle * 40, 12 * math.sin(angle))))
    nodes.append('[node name="CrystalLight%d" type="OmniLight3D" parent="Crystals"]\ntransform = %s\nlight_color = Color(1, 0.6, 0.2, 1)\n'
                 'light_energy = 1.5\nomni_range = 5.0' % (i + 1, tf((x, 1.2, z))))

nodes.append('[node name="Enemies" type="Node3D" parent="."]')
nodes.append('[node name="EnemySpawner" type="MultiplayerSpawner" parent="."]\nspawn_path = NodePath("../Enemies")')
nodes.append('[node name="RoomSync" type="MultiplayerSynchronizer" parent="."]\nreplication_config = SubResource("room_sync")')

header = '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://src/zones/combat_room/combat_room.gd" id="room"]\n'
text = header + "\n" + "\n\n".join(sub) + "\n\n" + "\n\n".join(nodes) + "\n"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)
print(os.path.normpath(out))
