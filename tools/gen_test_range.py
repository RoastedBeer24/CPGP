"""그레이박스 시험장(src/zones/test_range/test_range.tscn)을 만드는 스크립트.

    python3 tools/gen_test_range.py

좌표를 정확히 맞추려고 씬 파일을 코드로 만든다. 다시 실행하면 씬 파일을 덮어쓰므로,
에디터에서 시험장을 직접 고쳤다면 이 스크립트에도 같이 반영해야 한다.
"""
import math
import os

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "zones", "test_range", "test_range.tscn")

mats = {
    "floor":  ("Color(0.26, 0.27, 0.32, 1)", None),
    "wall":   ("Color(0.32, 0.34, 0.4, 1)", None),
    "ledge":  ("Color(0.85, 0.5, 0.15, 1)", None),      # 오를 수 있는 곳: 주황
    "roof":   ("Color(0.25, 0.3, 0.45, 1)", None),
    "cover":  ("Color(0.4, 0.4, 0.42, 1)", None),
    "neon_pink": ("Color(1, 0.2, 0.7, 1)", "Color(1, 0.2, 0.7, 1)"),
    "neon_cyan": ("Color(0.1, 0.9, 1, 1)", "Color(0.1, 0.9, 1, 1)"),
}
sub = []
for name, (albedo, emission) in mats.items():
    lines = [f'[sub_resource type="StandardMaterial3D" id="mat_{name}"]', f"albedo_color = {albedo}"]
    if emission:
        lines += ["emission_enabled = true", f"emission = {emission}", "emission_energy_multiplier = 4.0"]
    else:
        lines += ["roughness = 0.85"]
    sub.append("\n".join(lines))

sub.append("""[sub_resource type="Environment" id="env"]
background_mode = 1
background_color = Color(0.03, 0.02, 0.07, 1)
ambient_light_source = 2
ambient_light_color = Color(0.35, 0.35, 0.5, 1)
ambient_light_energy = 0.6
tonemap_mode = 3
glow_enabled = true
glow_bloom = 0.15
fog_enabled = true
fog_light_color = Color(0.12, 0.08, 0.22, 1)
fog_density = 0.015""")
# 적의 길찾기 지도. "navigation_geometry" 그룹의 충돌 지형으로 실행할 때 굽는다(src/zones/zone.gd).
sub.append("""[sub_resource type="NavigationMesh" id="navmesh"]
geometry_parsed_geometry_type = 1
geometry_source_geometry_mode = 1
geometry_source_group_name = &"navigation_geometry"
agent_height = 2.0
agent_radius = 0.5
agent_max_climb = 0.25
agent_max_slope = 30.0""")
sub.append("""[sub_resource type="StandardMaterial3D" id="mat_container"]
albedo_color = Color(0.15, 0.35, 0.3, 1)
roughness = 0.85""")
sub.append("""[sub_resource type="BoxShape3D" id="stair_ramp_shape"]
size = Vector3(3, 0.2, %.4f)""" % (math.hypot(6.0, 3.0) + 1.2))

nodes = []
def tf(pos, rot_x_deg=0.0, rot_y_deg=0.0):
    ax = math.radians(rot_x_deg); ay = math.radians(rot_y_deg)
    # R = Ry * Rx
    cx, sx, cy, sy = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay)
    m = [[cy, sy*sx, sy*cx], [0, cx, -sx], [-sy, cy*sx, cy*cx]]
    f = lambda v: f"{v:.6g}"
    basis = ", ".join(f(m[r][c]) for r in range(3) for c in range(3))  # tscn은 행 우선
    return f"Transform3D({basis}, {f(pos[0])}, {f(pos[1])}, {f(pos[2])})"

def box(name, parent, pos, size, mat, collide=True, rot_x=0.0, rot_y=0.0):
    lines = [f'[node name="{name}" type="CSGBox3D" parent="{parent}"]']
    if pos != (0, 0, 0) or rot_x or rot_y:
        lines.append(f"transform = {tf(pos, rot_x, rot_y)}")
    if collide:
        lines.append("use_collision = true")
    lines.append(f"size = Vector3({size[0]}, {size[1]}, {size[2]})")
    lines.append(f'material = SubResource("mat_{mat}")')
    nodes.append("\n".join(lines))

def label(name, parent, pos, text, size=110):
    nodes.append(f'[node name="{name}" type="Label3D" parent="{parent}"]\n'
                 f"transform = {tf(pos)}\nbillboard = 1\nfont_size = {size}\noutline_size = 8\ntext = \"{text}\"")

def groups_attr(groups):
    return (" groups=[" + ", ".join('"%s"' % g for g in groups) + "]") if groups else ""

def group(name, parent=".", groups=None):
    nodes.append(f'[node name="{name}" type="Node3D" parent="{parent}"{groups_attr(groups)}]')

def marker(name, parent, pos, groups=None):
    nodes.append(f'[node name="{name}" type="Marker3D" parent="{parent}"{groups_attr(groups)}]\ntransform = {tf(pos)}')

nodes.append('[node name="TestRange" type="Node3D"]\nscript = ExtResource("zone")')
nodes.append('[node name="Navigation" type="NavigationRegion3D" parent="."]\nnavigation_mesh = SubResource("navmesh")')
nodes.append('[node name="Environment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")')
nodes.append(f'[node name="Moon" type="DirectionalLight3D" parent="."]\ntransform = {tf((0, 20, 0), -55, 30)}\nlight_color = Color(0.6, 0.65, 1, 1)\nlight_energy = 0.5\nshadow_enabled = true')

group("SpawnPoints")
for i, x in enumerate([0, 2, -2]):
    nodes.append(f'[node name="Spawn{i + 1}" type="Marker3D" parent="SpawnPoints"]\ntransform = {tf((x, 0.05, 10))}')

group("Geometry", groups=["navigation_geometry"])
box("Floor", "Geometry", (0, -0.5, 0), (60, 1, 60), "floor")

# 1) 턱 오르기 연습: 높이별 턱 (앞쪽 -Z)
group("Ledges", "Geometry")
for i, h in enumerate([0.5, 1.0, 1.5, 2.0, 2.5]):
    x = -8 + i * 4
    box(f"Ledge{i + 1}", "Geometry/Ledges", (x, h / 2, -6), (3, h, 3), "ledge")
    label(f"LedgeLabel{i + 1}", "Geometry/Ledges", (x, h + 0.6, -4.4), f"{h}m")

# 2) 경사로와 옥상 (+X 쪽)
group("Rooftops", "Geometry")
roof_h = 3.0
def slope(name, parent, x, z_low, z_high, height, width, mat=None):
    """z_low에서 높이 0, z_high에서 height가 되는 경사면. 두께 0.2, 양끝을 0.6m씩 늘려 턱이 생기지 않게 한다."""
    run = abs(z_low - z_high)
    length = math.hypot(run, height) + 1.2
    angle = math.degrees(math.atan2(height, run))
    normal_drop = 0.1 / math.cos(math.radians(angle))
    center = (x, height / 2 - normal_drop, (z_low + z_high) / 2)
    if mat:
        box(name, parent, center, (width, 0.2, length), mat, rot_x=angle)
    else:
        nodes.append(f'[node name="{name}" type="StaticBody3D" parent="{parent}"]\n'
                     f"transform = {tf(center, angle)}")
        nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="{parent}/{name}"]\n'
                     f'shape = SubResource("stair_ramp_shape")')
    return length

# 경사 25도, 옥상 앞면(z=0)에서 높이가 정확히 3m가 되도록
slope("Ramp", "Geometry/Rooftops", 14, roof_h / math.tan(math.radians(25)), 0.0, roof_h, 3, "roof")
box("RoofA", "Geometry/Rooftops", (14, roof_h / 2, -4 - 0.0), (6, roof_h, 8), "roof")
# 옥상 사이 틈 3.5m: 달리기 점프로 건널 수 있는 거리
box("RoofB", "Geometry/Rooftops", (14, roof_h / 2, -15.5), (6, roof_h, 8), "roof")
label("GapLabel", "Geometry/Rooftops", (14, roof_h + 1.0, -9.75), "3.5m 틈")

# 3) 계단: 보이는 계단은 충돌 없음, 아래에 보이지 않는 경사 충돌면
group("Stairs", "Geometry")
steps, step_h, step_d = 12, 0.25, 0.5
for i in range(steps):
    h = step_h * (i + 1)
    box(f"Step{i + 1}", "Geometry/Stairs", (-14, h / 2, 6 - i * step_d - step_d / 2), (3, h, step_d), "wall", collide=False)
box("StairTop", "Geometry/Stairs", (-14, roof_h / 2, -3), (3, roof_h, 6), "roof")
slope("StairRamp", "Geometry/Stairs", -14, 6.0, 6.0 - steps * step_d, steps * step_h, 3)

# 4) 낮은 터널: 웅크리기·슬라이딩 연습 (천장 1.3m)
group("Tunnel", "Geometry")
box("TunnelLeft", "Geometry/Tunnel", (-23.6, 0.65, -16), (0.4, 1.3, 8), "wall")
box("TunnelRight", "Geometry/Tunnel", (-20.4, 0.65, -16), (0.4, 1.3, 8), "wall")
box("TunnelRoof", "Geometry/Tunnel", (-22, 1.5, -16), (3.6, 0.4, 8), "wall")
label("TunnelLabel", "Geometry/Tunnel", (-22, 2.3, -11.5), "높이 1.3m")

# 5) 엄폐물
group("Cover", "Geometry")
for i, (x, z, w, h) in enumerate([(-6, 2, 2, 1.1), (-3, 3, 1, 1.8), (4, 2, 2.5, 1.1), (7, 3.5, 1, 2.2)]):
    box(f"Cover{i + 1}", "Geometry/Cover", (x, h / 2, z), (w, h, 1), "cover")

# 6) 바깥 벽과 네온
group("Walls", "Geometry")
# 서쪽 벽은 가운데(z -2..2)를 비워 잠입 구역으로 이어지게 한다.
for name, pos, size in [("North", (0, 3, -30), (60, 6, 1)), ("South", (0, 3, 30), (60, 6, 1)),
                        ("East", (30, 3, 0), (1, 6, 60)),
                        ("WestNorth", (-30, 3, -16.25), (1, 6, 28.5)), ("WestSouth", (-30, 3, 16.25), (1, 6, 28.5))]:
    box(name, "Geometry/Walls", pos, size, "wall")
group("Neon")
for i, (pos, size, mat) in enumerate([((0, 4.5, -29.4), (20, 0.15, 0.1), "neon_pink"),
                                      ((29.4, 4.0, 0), (0.1, 0.15, 20), "neon_cyan"),
                                      ((-29.4, 4.0, 0), (0.1, 0.15, 20), "neon_pink"),
                                      ((14, 3.05, -8.05), (6, 0.1, 0.1), "neon_cyan")]):
    box(f"Strip{i + 1}", "Neon", pos, size, mat, collide=False)
for i, (pos, color) in enumerate([((0, 4, -27), "Color(1, 0.2, 0.7, 1)"), ((27, 4, 0), "Color(0.1, 0.9, 1, 1)"),
                                  ((-27, 4, 0), "Color(1, 0.2, 0.7, 1)"), ((14, 5, -9.75), "Color(0.1, 0.9, 1, 1)")]):
    nodes.append(f'[node name="NeonLight{i + 1}" type="OmniLight3D" parent="Neon"]\ntransform = {tf(pos)}\n'
                 f"light_color = {color}\nlight_energy = 3.0\nomni_range = 14.0")

ext = ['[ext_resource type="PackedScene" path="res://src/enemies/training_dummy.tscn" id="dummy"]',
       '[ext_resource type="PackedScene" path="res://src/enemies/enemy.tscn" id="enemy"]',
       '[ext_resource type="Script" path="res://src/zones/zone.gd" id="zone"]',
       '[ext_resource type="Script" path="res://src/zones/hide_spot.gd" id="hide_spot"]',
       '[ext_resource type="Resource" path="res://data/enemies/guard.tres" id="guard"]',
       '[ext_resource type="Resource" path="res://data/enemies/heavy.tres" id="heavy"]',
       '[ext_resource type="Resource" path="res://data/enemies/guard_arena.tres" id="guard_arena"]']
# 7) 사격장 (시작 위치 뒤쪽, +Z): 거리별 허수아비. 시작 위치에서 뒤로 돌면 보인다.
group("ShootingRange")
box("FiringLine", "ShootingRange", (-4, 0.01, 13), (14, 0.02, 0.15), "neon_cyan", collide=False)
label("RangeLabel", "ShootingRange", (-4, 2.6, 13), "사격장")
for i, (x, z, armor) in enumerate([(-9, 18, 0), (-5, 23, 0), (-1, 28, 0), (2, 19, 100)]):
    lines = [f'[node name="Dummy{i + 1}" parent="ShootingRange" instance=ExtResource("dummy")]',
             f"transform = {tf((x, 0, z), 0, 180)}"]
    if armor:
        lines.append(f"armor = {armor}.0")
    nodes.append("\n".join(lines))
    dist = round(z - 13)
    label(f"DistLabel{i + 1}", "ShootingRange", (x, 2.9, z), f"{dist}m" + (" 장갑" if armor else ""), 80)

# 8) 경비병 구역 (남동쪽): 엄폐물 뒤의 적 두 명. 죽으면 10초 뒤 되살아난다.
group("Arena", groups=["navigation_geometry"])
label("ArenaLabel", "Arena", (17, 3.2, 12), "경비병 구역", 110)
for i, (x, z) in enumerate([(22, 22), (26, 18)]):
    nodes.append(f'[node name="Guard{i + 1}" parent="Arena" instance=ExtResource("enemy")]\n'
                 f'transform = {tf((x, 0, z), 0, 135)}\ndata = ExtResource("guard_arena")\nrespawn_delay = 10.0')
for i, (x, z, w, h) in enumerate([(19, 16, 3, 1.1), (23, 14, 1, 2.0), (16, 20, 1, 1.6)]):
    box(f"ArenaCover{i + 1}", "Arena", (x, h / 2, z), (w, h, 1), "cover")
group("ArenaCoverPoints", "Arena")
for i, (x, z) in enumerate([(19, 14.8), (23, 12.8), (14.8, 20), (19, 17.2)]):
    marker(f"Cover{i + 1}", "Arena/ArenaCoverPoints", (x, 0.05, z), ["cover_points"])

# 9) 잠입 구역 (서쪽 벽 너머, x -90..-30): 순찰하는 경비 넷, 중장갑병 하나, 보초 하나.
#    엄폐용 상자, 창고 건물, 시체를 숨길 컨테이너가 있다. 쓰러진 적은 60초 뒤 되살아난다.
group("Stealth", groups=["navigation_geometry"])
label("StealthLabel", "Stealth", (-27, 3.4, 0), "잠입 구역", 110)
label("StealthHelp", "Stealth", (-27, 2.6, 0), "웅크리면 발소리가 나지 않음 · 뒤에서 F: 제압 · F: 몸 들기 · 컨테이너 옆에서 F: 숨기기", 40)
box("StealthFloor", "Stealth", (-60, -0.5, 0), (60, 1, 60), "floor")
for name, pos, size in [("StealthNorth", (-60, 3, -30), (60, 6, 1)), ("StealthSouth", (-60, 3, 30), (60, 6, 1)),
                        ("StealthWest", (-90, 3, 0), (1, 6, 60))]:
    box(name, "Stealth", pos, size, "wall")
# 창고 건물
for i, (x, z, w, d) in enumerate([(-45, -15, 10, 8), (-45, 15, 10, 8), (-71, 0, 12, 14), (-80, -21, 8, 8)]):
    box(f"Warehouse{i + 1}", "Stealth", (x, 2, z), (w, 4, d), "wall")
# 엄폐용 상자(1.2m)와 낮은 벽
crates = [(-37, -5), (-37, 5), (-55, -4), (-55, 5), (-60, -16), (-62, 19), (-78, 12), (-62, -6)]
for i, (x, z) in enumerate(crates):
    box(f"Crate{i + 1}", "Stealth", (x, 0.6, z), (2, 1.2, 2), "cover")
box("LowWall", "Stealth", (-50, 0.5, 0), (1, 1, 6), "cover")
# 시체를 숨길 컨테이너
for i, (x, z) in enumerate([(-53, -25), (-85, 22), (-36, 24)]):
    box(f"Container{i + 1}", "Stealth", (x, 1.3, z), (2.6, 2.6, 1.8), "container")
    nodes.append(f'[node name="HideSpot{i + 1}" type="Node3D" parent="Stealth"]\ntransform = {tf((x, 0, z))}\n'
                 f'script = ExtResource("hide_spot")\nradius = 2.8')
    label(f"ContainerLabel{i + 1}", "Stealth", (x, 3.0, z), "컨테이너", 50)
# 조명: 어두운 구역에 띄엄띄엄
for i, (pos, color) in enumerate([((-40, 5, 0), "Color(0.1, 0.9, 1, 1)"), ((-60, 5, -18), "Color(1, 0.2, 0.7, 1)"),
                                  ((-60, 5, 18), "Color(0.1, 0.9, 1, 1)"), ((-82, 5, 0), "Color(1, 0.2, 0.7, 1)")]):
    nodes.append(f'[node name="StealthLight{i + 1}" type="OmniLight3D" parent="Stealth"]\ntransform = {tf(pos)}\n'
                 f"light_color = {color}\nlight_energy = 2.0\nomni_range = 16.0")
# 엄폐 지점: 상자 양옆
group("StealthCoverPoints", "Stealth")
for i, (x, z) in enumerate(crates):
    marker(f"Cover{i * 2 + 1}", "Stealth/StealthCoverPoints", (x - 1.6, 0.05, z), ["cover_points"])
    marker(f"Cover{i * 2 + 2}", "Stealth/StealthCoverPoints", (x + 1.6, 0.05, z), ["cover_points"])
# 순찰 경로
group("Routes", "Stealth")
routes = {
    "Route1": [(-37, -9), (-37, -21), (-53, -21), (-53, -9)],
    "Route2": [(-37, 9), (-53, 9), (-53, 21), (-37, 21)],
    "Route3": [(-58, -11), (-58, 11)],
    "Route4": [(-64, -11), (-82, -11), (-82, 12), (-64, 12)],
}
for name, points in routes.items():
    group(name, "Stealth/Routes")
    for j, (x, z) in enumerate(points):
        marker(f"Point{j + 1}", f"Stealth/Routes/{name}", (x, 0.05, z))
group("Enemies", "Stealth")
stealth_enemies = [
    ("Patrol1", (-37, -9), 0, "guard", "Route1"),
    ("Patrol2", (-53, 21), 180, "guard", "Route2"),
    ("Patrol3", (-58, 11), 0, "guard", "Route3"),
    ("Patrol4", (-82, 12), 90, "guard", "Route4"),
    ("Heavy1", (-64, 0), -90, "heavy", None),
    ("Sentry1", (-75, -15), -135, "guard", None),
]
for name, (x, z), yaw, kind, route in stealth_enemies:
    lines = [f'[node name="{name}" parent="Stealth/Enemies" instance=ExtResource("enemy")]',
             f"transform = {tf((x, 0, z), 0, yaw)}", f'data = ExtResource("{kind}")', "respawn_delay = 60.0"]
    if route:
        lines.append(f'patrol_route = NodePath("../../Routes/{route}")')
    nodes.append("\n".join(lines))

text = f"[gd_scene load_steps={len(sub) + len(ext) + 1} format=3]\n\n" + "\n".join(ext) + "\n\n" + "\n\n".join(sub) + "\n\n" + "\n\n".join(nodes) + "\n"
# Windows에서도 UTF-8과 LF로 쓴다 (기본값이면 시스템 코드 페이지로 써져 한글이 깨진다).
open(out, "w", encoding="utf-8", newline="\n").write(text)
print("written", len(nodes), "nodes")
