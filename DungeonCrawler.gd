extends Node2D

const MAP_W := 41
const MAP_H := 41

const TILE_FLOOR := 0
const TILE_WALL := 1

const ENEMY_COUNT := 10
const ITEM_COUNT := 12

var x := 1
var y := 1
var dir := 1 # 0=北 1=東 2=南 3=西

var floor_level := 1
var hp := 30
var max_hp := 30
var atk := 6
var potions := 1
var gold := 0

var map: Array = []
var enemies: Array[Dictionary] = []
var items: Array[Dictionary] = []
var stairs_pos := Vector2i(1, 1)
var message_log: Array[String] = []

var show_minimap := false
var space_was_pressed := false
var attack_was_pressed := false
var potion_was_pressed := false
var game_over := false

const LINE_COLOR := Color.WHITE
const WALL_COLOR := Color(0.35, 0.35, 0.35)
const BG_COLOR := Color.BLACK
const ENEMY_COLOR := Color(0.9, 0.15, 0.15)
const ITEM_COLOR := Color(0.2, 0.9, 0.35)
const STAIRS_COLOR := Color(0.25, 0.55, 1.0)

func _ready() -> void:
	randomize()
	start_new_floor()

func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_SPACE) and not space_was_pressed:
		show_minimap = not show_minimap
		queue_redraw()

	space_was_pressed = Input.is_key_pressed(KEY_SPACE)

	if game_over:
		if Input.is_key_pressed(KEY_ENTER):
			restart_game()
		return

	if Input.is_action_just_pressed("ui_up"):
		if move_forward():
			enemy_turn()
	elif Input.is_action_just_pressed("ui_down"):
		if move_backward():
			enemy_turn()
	elif Input.is_action_just_pressed("ui_left"):
		turn_left()
	elif Input.is_action_just_pressed("ui_right"):
		turn_right()
	elif Input.is_key_pressed(KEY_Z) and not attack_was_pressed:
		if attack_forward():
			enemy_turn()
	elif Input.is_key_pressed(KEY_X) and not potion_was_pressed:
		use_potion()

	attack_was_pressed = Input.is_key_pressed(KEY_Z)
	potion_was_pressed = Input.is_key_pressed(KEY_X)

func _draw() -> void:
	var screen_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen_size), BG_COLOR)

	draw_view()
	draw_info()
	draw_commands()
	draw_log()

	if show_minimap:
		draw_minimap()

	if game_over:
		draw_game_over()

func restart_game() -> void:
	floor_level = 1
	max_hp = 30
	hp = max_hp
	atk = 6
	potions = 1
	gold = 0
	game_over = false
	message_log.clear()
	start_new_floor()

func start_new_floor() -> void:
	generate_dungeon()
	place_stairs()
	place_enemies()
	place_items()
	add_message("B%dF: dungeon starts." % floor_level)
	queue_redraw()

func generate_dungeon() -> void:
	map.clear()

	for yy in range(MAP_H):
		var row: Array[int] = []

		for xx in range(MAP_W):
			row.append(TILE_WALL)

		map.append(row)

	var start := Vector2i(1, 1)
	carve_maze(start.x, start.y)

	x = start.x
	y = start.y
	dir = 1

func carve_maze(cx: int, cy: int) -> void:
	map[cy][cx] = TILE_FLOOR

	var directions: Array[Vector2i] = [
		Vector2i(0, -2),
		Vector2i(2, 0),
		Vector2i(0, 2),
		Vector2i(-2, 0),
	]

	directions.shuffle()

	for d in directions:
		var nx := cx + d.x
		var ny := cy + d.y

		if nx <= 0 or nx >= MAP_W - 1:
			continue
		if ny <= 0 or ny >= MAP_H - 1:
			continue
		if map[ny][nx] == TILE_FLOOR:
			continue

		var wall_x := cx + d.x / 2
		var wall_y := cy + d.y / 2

		map[wall_y][wall_x] = TILE_FLOOR
		carve_maze(nx, ny)

func place_stairs() -> void:
	var best_pos := Vector2i(1, 1)
	var best_dist := -1

	for yy in range(MAP_H):
		for xx in range(MAP_W):
			if is_wall(xx, yy):
				continue

			var dist := abs(xx - x) + abs(yy - y)
			if dist > best_dist:
				best_dist = dist
				best_pos = Vector2i(xx, yy)

	stairs_pos = best_pos

func place_enemies() -> void:
	enemies.clear()

	for i in range(ENEMY_COUNT + floor_level):
		var pos := get_random_empty_floor()
		enemies.append({
			"pos": pos,
			"hp": 8 + floor_level * 2,
			"atk": 3 + floor_level,
			"name": "Enemy"
		})

func place_items() -> void:
	items.clear()

	for i in range(ITEM_COUNT):
		var pos := get_random_empty_floor()
		var kind := "potion" if randf() < 0.45 else "gold"
		items.append({
			"pos": pos,
			"kind": kind,
			"amount": randi_range(5, 20)
		})

func get_random_empty_floor() -> Vector2i:
	for tries in range(1000):
		var px := randi_range(1, MAP_W - 2)
		var py := randi_range(1, MAP_H - 2)
		var pos := Vector2i(px, py)

		if is_wall(px, py):
			continue
		if pos == Vector2i(x, y) or pos == stairs_pos:
			continue
		if enemy_at(pos) != -1:
			continue
		if item_at(pos) != -1:
			continue

		return pos

	return Vector2i(1, 1)

func draw_view() -> void:
	var screen_size := get_viewport_rect().size

	var view_x := screen_size.x * 0.05
	var view_y := screen_size.y * 0.05
	var view_w := screen_size.x * 0.75
	var view_h := screen_size.y * 0.65

	var frames := make_view_frames(view_x, view_y, view_w, view_h)

	draw_rect(frames[0], LINE_COLOR, false, 3)

	for depth in range(1, frames.size()):
		var front := get_relative_pos(0, depth)

		var left := get_relative_pos(-1, depth - 1)
		var right := get_relative_pos(1, depth - 1)

		var next_left := get_relative_pos(-1, depth)
		var next_right := get_relative_pos(1, depth)

		var has_left_wall := is_wall(left.x, left.y)
		var has_right_wall := is_wall(right.x, right.y)

		var has_next_left_wall := is_wall(next_left.x, next_left.y)
		var has_next_right_wall := is_wall(next_right.x, next_right.y)

		var near: Rect2 = frames[depth - 1]
		var far: Rect2 = frames[depth]

		if has_left_wall:
			draw_left_wall(near, far)

			if not has_next_left_wall:
				draw_left_wall_end_line(far)
		elif has_next_left_wall:
			draw_left_gap_wall(near, far)

		if has_right_wall:
			draw_right_wall(near, far)

			if not has_next_right_wall:
				draw_right_wall_end_line(far)
		elif has_next_right_wall:
			draw_right_gap_wall(near, far)

		if is_wall(front.x, front.y):
			draw_front_wall_custom(
				far,
				has_next_left_wall,
				has_next_right_wall
			)
			return

		draw_corridor_lines(near, far, has_left_wall, has_right_wall)
		draw_object_at_depth(front, far, depth)

func make_view_frames(view_x: float, view_y: float, view_w: float, view_h: float) -> Array[Rect2]:
	var scales: Array[float] = [
		1.00,
		0.62,
		0.36,
		0.18,
		0.08,
	]

	var frames: Array[Rect2] = []

	for scale: float in scales:
		var w: float = view_w * scale
		var h: float = view_h * scale
		var px: float = view_x + (view_w - w) / 2.0
		var py: float = view_y + (view_h - h) / 2.0

		frames.append(Rect2(px, py, w, h))

	return frames

func draw_object_at_depth(pos: Vector2i, frame: Rect2, depth: int) -> void:
	var center := frame.position + frame.size / 2.0
	var size := max(10.0, 70.0 / float(depth))
	var enemy_index := enemy_at(pos)
	var item_index := item_at(pos)

	if pos == stairs_pos:
		draw_rect(Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)), STAIRS_COLOR, false, 3)
		draw_line(center + Vector2(-size * 0.45, 0), center + Vector2(size * 0.45, 0), STAIRS_COLOR, 3)
		draw_line(center + Vector2(0, -size * 0.45), center + Vector2(0, size * 0.45), STAIRS_COLOR, 3)

	if item_index != -1:
		draw_circle(center + Vector2(0, size * 0.35), size * 0.22, ITEM_COLOR)

	if enemy_index != -1:
		draw_circle(center + Vector2(0, -size * 0.15), size * 0.38, ENEMY_COLOR)
		draw_line(center + Vector2(-size * 0.25, -size * 0.2), center + Vector2(size * 0.25, -size * 0.2), LINE_COLOR, 2)

func draw_corridor_lines(
	near: Rect2,
	far: Rect2,
	has_left_wall: bool,
	has_right_wall: bool
) -> void:
	if has_left_wall:
		draw_line(near.position, far.position, LINE_COLOR, 2)
		draw_line(
			near.position + Vector2(0, near.size.y),
			far.position + Vector2(0, far.size.y),
			LINE_COLOR,
			2
		)

	if has_right_wall:
		draw_line(
			near.position + Vector2(near.size.x, 0),
			far.position + Vector2(far.size.x, 0),
			LINE_COLOR,
			2
		)
		draw_line(
			near.position + near.size,
			far.position + far.size,
			LINE_COLOR,
			2
		)

func draw_front_wall_custom(
	r: Rect2,
	connect_left: bool,
	connect_right: bool
) -> void:
	draw_rect(r, WALL_COLOR)

	draw_line(r.position, r.position + Vector2(r.size.x, 0), LINE_COLOR, 2)
	draw_line(r.position + Vector2(0, r.size.y), r.position + r.size, LINE_COLOR, 2)

	if not connect_left:
		draw_line(r.position, r.position + Vector2(0, r.size.y), LINE_COLOR, 2)

	if not connect_right:
		draw_line(
			r.position + Vector2(r.size.x, 0),
			r.position + r.size,
			LINE_COLOR,
			2
		)

func draw_left_wall(near: Rect2, far: Rect2) -> void:
	var points := PackedVector2Array([
		near.position,
		far.position,
		far.position + Vector2(0, far.size.y),
		near.position + Vector2(0, near.size.y),
	])

	draw_colored_polygon(points, WALL_COLOR)

	draw_line(near.position, far.position, LINE_COLOR, 2)
	draw_line(
		near.position + Vector2(0, near.size.y),
		far.position + Vector2(0, far.size.y),
		LINE_COLOR,
		2
	)

func draw_right_wall(near: Rect2, far: Rect2) -> void:
	var points := PackedVector2Array([
		near.position + Vector2(near.size.x, 0),
		far.position + Vector2(far.size.x, 0),
		far.position + far.size,
		near.position + near.size,
	])

	draw_colored_polygon(points, WALL_COLOR)

	draw_line(
		near.position + Vector2(near.size.x, 0),
		far.position + Vector2(far.size.x, 0),
		LINE_COLOR,
		2
	)
	draw_line(
		near.position + near.size,
		far.position + far.size,
		LINE_COLOR,
		2
	)

func draw_left_gap_wall(near: Rect2, far: Rect2) -> void:
	var inner_x: float = near.position.x
	var outer_x: float = far.position.x
	var top_y: float = far.position.y
	var bottom_y: float = far.position.y + far.size.y

	var points := PackedVector2Array([
		Vector2(inner_x, top_y),
		Vector2(outer_x, top_y),
		Vector2(outer_x, bottom_y),
		Vector2(inner_x, bottom_y),
	])

	draw_colored_polygon(points, WALL_COLOR)

	draw_line(Vector2(inner_x, top_y), Vector2(outer_x, top_y), LINE_COLOR, 2)
	draw_line(Vector2(outer_x, bottom_y), Vector2(inner_x, bottom_y), LINE_COLOR, 2)

func draw_right_gap_wall(near: Rect2, far: Rect2) -> void:
	var inner_x: float = near.position.x + near.size.x
	var outer_x: float = far.position.x + far.size.x
	var top_y: float = far.position.y
	var bottom_y: float = far.position.y + far.size.y

	var points := PackedVector2Array([
		Vector2(outer_x, top_y),
		Vector2(inner_x, top_y),
		Vector2(inner_x, bottom_y),
		Vector2(outer_x, bottom_y),
	])

	draw_colored_polygon(points, WALL_COLOR)

	draw_line(Vector2(outer_x, top_y), Vector2(inner_x, top_y), LINE_COLOR, 2)
	draw_line(Vector2(inner_x, bottom_y), Vector2(outer_x, bottom_y), LINE_COLOR, 2)

func draw_left_wall_end_line(far: Rect2) -> void:
	draw_line(
		far.position,
		far.position + Vector2(0, far.size.y),
		LINE_COLOR,
		2
	)

func draw_right_wall_end_line(far: Rect2) -> void:
	draw_line(
		far.position + Vector2(far.size.x, 0),
		far.position + far.size,
		LINE_COLOR,
		2
	)

func draw_info() -> void:
	var screen_size := get_viewport_rect().size

	draw_string(
		ThemeDB.fallback_font,
		Vector2(40, screen_size.y - 210),
		"B%dF  HP:%d/%d  ATK:%d  POT:%d  GOLD:%d" % [floor_level, hp, max_hp, atk, potions, gold]
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(40, screen_size.y - 180),
		"POS: " + str(x) + "," + str(y)
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(220, screen_size.y - 180),
		"DIR: " + get_dir_text()
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(40, screen_size.y - 145),
		"ARROWS: MOVE / TURN    Z: ATTACK    X: POTION    SPACE: MAP"
	)

func draw_commands() -> void:
	var screen_size := get_viewport_rect().size

	var r := Rect2(
		40,
		screen_size.y - 95,
		620,
		65
	)

	draw_rect(r, BG_COLOR)
	draw_rect(r, LINE_COLOR, false, 2)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(65, screen_size.y - 58),
		"Find stairs, survive enemies, collect gold."
	)

func draw_log() -> void:
	var screen_size := get_viewport_rect().size
	var start_y := screen_size.y - 275

	for i in range(message_log.size()):
		draw_string(
			ThemeDB.fallback_font,
			Vector2(40, start_y + i * 22),
			message_log[i]
		)

func draw_game_over() -> void:
	var screen_size := get_viewport_rect().size
	var r := Rect2(screen_size.x * 0.25, screen_size.y * 0.32, screen_size.x * 0.5, 130)
	draw_rect(r, Color(0, 0, 0, 0.85))
	draw_rect(r, Color.RED, false, 3)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(35, 50), "GAME OVER")
	draw_string(ThemeDB.fallback_font, r.position + Vector2(35, 90), "ENTER: restart")

func draw_minimap() -> void:
	var screen_size := get_viewport_rect().size

	var cell := 6
	var ox := screen_size.x - 285
	var oy := screen_size.y - 310

	for yy in range(map.size()):
		for xx in range(map[yy].size()):
			var r := Rect2(
				ox + xx * cell,
				oy + yy * cell,
				cell,
				cell
			)

			if map[yy][xx] == TILE_WALL:
				draw_rect(r, Color.DARK_GRAY)
			else:
				draw_rect(r, Color.BLACK)

			draw_rect(r, Color.GRAY, false, 1)

	draw_map_marker(ox, oy, cell, stairs_pos, STAIRS_COLOR)

	for item in items:
		draw_map_marker(ox, oy, cell, item["pos"], ITEM_COLOR)

	for enemy in enemies:
		draw_map_marker(ox, oy, cell, enemy["pos"], ENEMY_COLOR)

	var p := Vector2(
		ox + x * cell + cell / 2,
		oy + y * cell + cell / 2
	)

	draw_circle(p, 4, Color.WHITE)

	var dir_vec := get_dir_vector()
	draw_line(
		p,
		p + Vector2(dir_vec.x, dir_vec.y) * 7,
		Color.RED,
		2
	)

func draw_map_marker(ox: float, oy: float, cell: int, pos: Vector2i, color: Color) -> void:
	draw_rect(
		Rect2(ox + pos.x * cell + 1, oy + pos.y * cell + 1, cell - 2, cell - 2),
		color
	)

func get_relative_pos(side: int, forward: int) -> Vector2i:
	var forward_vec := get_dir_vector()
	var right_vec := Vector2i(-forward_vec.y, forward_vec.x)

	return Vector2i(
		x + forward_vec.x * forward + right_vec.x * side,
		y + forward_vec.y * forward + right_vec.y * side
	)

func get_dir_vector() -> Vector2i:
	match dir:
		0:
			return Vector2i(0, -1)
		1:
			return Vector2i(1, 0)
		2:
			return Vector2i(0, 1)
		3:
			return Vector2i(-1, 0)

	return Vector2i(0, 0)

func is_wall(tx: int, ty: int) -> bool:
	if ty < 0 or ty >= map.size():
		return true
	if tx < 0 or tx >= map[ty].size():
		return true

	return map[ty][tx] == TILE_WALL

func move_forward() -> bool:
	var pos := get_relative_pos(0, 1)
	return try_move(pos.x, pos.y)

func move_backward() -> bool:
	var pos := get_relative_pos(0, -1)
	return try_move(pos.x, pos.y)

func turn_left() -> void:
	dir = (dir + 3) % 4
	queue_redraw()

func turn_right() -> void:
	dir = (dir + 1) % 4
	queue_redraw()

func try_move(nx: int, ny: int) -> bool:
	var target := Vector2i(nx, ny)

	if is_wall(nx, ny):
		add_message("A wall blocks the way.")
		queue_redraw()
		return false

	if enemy_at(target) != -1:
		add_message("Enemy ahead. Press Z to attack.")
		queue_redraw()
		return false

	x = nx
	y = ny
	pickup_item()

	if Vector2i(x, y) == stairs_pos:
		descend()
		return false

	queue_redraw()
	return true

func attack_forward() -> bool:
	var target := get_relative_pos(0, 1)
	var index := enemy_at(target)

	if index == -1:
		add_message("No enemy in front.")
		queue_redraw()
		return false

	var damage := randi_range(max(1, atk - 2), atk + 2)
	enemies[index]["hp"] -= damage
	add_message("You hit for %d." % damage)

	if enemies[index]["hp"] <= 0:
		add_message("%s defeated." % enemies[index]["name"])
		gold += randi_range(2, 8)
		enemies.remove_at(index)

	queue_redraw()
	return true

func enemy_turn() -> void:
	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i]
		var pos: Vector2i = enemy["pos"]
		var player_pos := Vector2i(x, y)
		var distance := abs(pos.x - x) + abs(pos.y - y)

		if distance == 1:
			var damage: int = randi_range(1, enemy["atk"])
			hp -= damage
			add_message("%s hits for %d." % [enemy["name"], damage])
			continue

		if distance <= 6:
			var step := choose_enemy_step(pos, player_pos)
			if step != pos:
				enemies[i]["pos"] = step

	if hp <= 0:
		hp = 0
		game_over = true
		add_message("You fall in the dungeon.")

	queue_redraw()

func choose_enemy_step(from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = [
		from_pos + Vector2i(1, 0),
		from_pos + Vector2i(-1, 0),
		from_pos + Vector2i(0, 1),
		from_pos + Vector2i(0, -1),
	]

	candidates.shuffle()
	var best := from_pos
	var best_dist := abs(from_pos.x - to_pos.x) + abs(from_pos.y - to_pos.y)

	for candidate in candidates:
		if is_wall(candidate.x, candidate.y):
			continue
		if candidate == to_pos:
			continue
		if enemy_at(candidate) != -1:
			continue

		var dist := abs(candidate.x - to_pos.x) + abs(candidate.y - to_pos.y)
		if dist < best_dist:
			best_dist = dist
			best = candidate

	return best

func pickup_item() -> void:
	var index := item_at(Vector2i(x, y))

	if index == -1:
		return

	var item := items[index]

	if item["kind"] == "potion":
		potions += 1
		add_message("Potion found.")
	else:
		gold += item["amount"]
		add_message("Gold +%d." % item["amount"])

	items.remove_at(index)

func use_potion() -> void:
	if potions <= 0:
		add_message("No potion.")
		queue_redraw()
		return
	if hp >= max_hp:
		add_message("HP already full.")
		queue_redraw()
		return

	potions -= 1
	var heal := 12
	hp = min(max_hp, hp + heal)
	add_message("Potion heals %d." % heal)
	enemy_turn()

func descend() -> void:
	floor_level += 1
	max_hp += 2
	hp = min(max_hp, hp + 10)
	atk += 1 if floor_level % 2 == 0 else 0
	start_new_floor()

func enemy_at(pos: Vector2i) -> int:
	for i in range(enemies.size()):
		if enemies[i]["pos"] == pos:
			return i

	return -1

func item_at(pos: Vector2i) -> int:
	for i in range(items.size()):
		if items[i]["pos"] == pos:
			return i

	return -1

func add_message(text: String) -> void:
	message_log.push_front(text)

	while message_log.size() > 4:
		message_log.pop_back()

func get_dir_text() -> String:
	match dir:
		0:
			return "N"
		1:
			return "E"
		2:
			return "S"
		3:
			return "W"

	return "?"
