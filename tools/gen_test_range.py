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

def group(name, parent="."):
    nodes.append(f'[node name="{name}" type="Node3D" parent="{parent}"]')

nodes.append('[node name="TestRange" type="Node3D"]')
nodes.append('[node name="Environment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")')
nodes.append(f'[node name="Moon" type="DirectionalLight3D" parent="."]\ntransform = {tf((0, 20, 0), -55, 30)}\nlight_color = Color(0.6, 0.65, 1, 1)\nlight_energy = 0.5\nshadow_enabled = true')

group("SpawnPoints")
for i, x in enumerate([0, 2, -2]):
    nodes.append(f'[node name="Spawn{i + 1}" type="Marker3D" parent="SpawnPoints"]\ntransform = {tf((x, 0.05, 10))}')

group("Geometry")
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
for name, pos, size in [("North", (0, 3, -30), (60, 6, 1)), ("South", (0, 3, 30), (60, 6, 1)),
                        ("East", (30, 3, 0), (1, 6, 60)), ("West", (-30, 3, 0), (1, 6, 60))]:
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
       '[ext_resource type="PackedScene" path="res://src/enemies/grunt.tscn" id="grunt"]']
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
group("Arena")
label("ArenaLabel", "Arena", (17, 3.2, 12), "경비병 구역", 110)
for i, (x, z) in enumerate([(22, 22), (26, 18)]):
    nodes.append(f'[node name="Grunt{i + 1}" parent="Arena" instance=ExtResource("grunt")]\n'
                 f"transform = {tf((x, 0, z), 0, 135)}\nrespawn_delay = 10.0\nsight_range = 15.0")
for i, (x, z, w, h) in enumerate([(19, 16, 3, 1.1), (23, 14, 1, 2.0), (16, 20, 1, 1.6)]):
    box(f"ArenaCover{i + 1}", "Arena", (x, h / 2, z), (w, h, 1), "cover")

text = f"[gd_scene load_steps={len(sub) + len(ext) + 1} format=3]\n\n" + "\n".join(ext) + "\n\n" + "\n\n".join(sub) + "\n\n" + "\n\n".join(nodes) + "\n"
open(out, "w").write(text)
print("written", len(nodes), "nodes")
