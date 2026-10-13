extends TestCase
## Hitbox: the box stands on the feet, and an attack covers `reach` in front and a little
## behind, mirrored when facing left; aimed up or down it stands on end over or under the feet.

func test_box_stands_on_the_feet() -> void:
	var box := Hitbox.new(Vector2(30, 60))
	var r := box.rect_at(Vector2(100, 500))
	check_eq(r, Rect2(85, 440, 30, 60), "centred on x, bottom on the feet")
	check_eq(r.get_center().x, 100.0, "centred")
	check_eq(r.end.y, 500.0, "bottom at the feet")

func test_default_size() -> void:
	check_eq(Hitbox.new().size, Vector2(30, 60), "30 x 60")

func test_attack_facing_right_reaches_right() -> void:
	var a := Hitbox.attack_area(Vector2(100, 500), 1, 80.0, 50.0)
	check_eq(a.position.x, 90.0, "10 behind")
	check_eq(a.end.x, 180.0, "80 in front")
	check(a.has_point(Vector2(170, 470)), "a monster in front is inside")
	check(not a.has_point(Vector2(60, 470)), "a monster far behind is outside")

func test_attack_facing_left_is_the_mirror() -> void:
	var right := Hitbox.attack_area(Vector2(100, 500), 1, 80.0, 50.0)
	var left := Hitbox.attack_area(Vector2(100, 500), -1, 80.0, 50.0)
	check_eq(left.position.x, 20.0, "80 in front, to the left")
	check_eq(left.end.x, 110.0, "10 behind, to the right")
	check_near(100.0 - left.position.x, right.end.x - 100.0, "same reach both ways")
	check_eq(left.size, right.size, "same size")

func test_attack_height_sits_on_the_feet() -> void:
	var a := Hitbox.attack_area(Vector2(100, 500), 1, 80.0, 50.0)
	check_eq(a.size.y, 50.0, "tall as asked")
	check_eq(a.end.y, 510.0, "reaches 10 below the feet")

func test_custom_reach_behind() -> void:
	var a := Hitbox.attack_area(Vector2(100, 500), 1, 80.0, 50.0, 0.0)
	check_eq(a.position.x, 100.0, "nothing behind")
	check_eq(a.size.x, 80.0, "just the reach")

func test_aimed_ahead_is_the_plain_attack() -> void:
	check_eq(Hitbox.aimed_area(Vector2(100, 500), -1, Hitbox.Aim.AHEAD, 80.0, 50.0),
		Hitbox.attack_area(Vector2(100, 500), -1, 80.0, 50.0), "same box")

func test_aimed_up_reaches_overhead() -> void:
	var a := Hitbox.aimed_area(Vector2(100, 500), 1, Hitbox.Aim.UP, 80.0, 50.0)
	check_eq(a.get_center().x, 100.0, "centred on him")
	check_eq(a.size.x, 50.0, "as wide as the attack is tall")
	check_eq(a.position.y, 500.0 - Hitbox.UP_FROM - 80.0, "reach above the start")
	check(not a.has_point(Vector2(160, 480)), "nothing ahead")

func test_aimed_down_reaches_below() -> void:
	var a := Hitbox.aimed_area(Vector2(100, 500), 1, Hitbox.Aim.DOWN, 80.0, 50.0)
	check_eq(a.end.y, 580.0, "reach below the feet")
	check(a.has_point(Vector2(100, 540)), "a monster under him")

func test_aim_directions() -> void:
	check_eq(Hitbox.aim_direction(-1, Hitbox.Aim.AHEAD), Vector2.LEFT, "ahead is the way he faces")
	check_eq(Hitbox.aim_direction(-1, Hitbox.Aim.UP), Vector2.UP, "up")
	check_eq(Hitbox.aim_direction(1, Hitbox.Aim.DOWN), Vector2.DOWN, "down")
