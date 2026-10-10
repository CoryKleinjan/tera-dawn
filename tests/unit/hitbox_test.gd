extends TestCase
## Hitbox: the box stands on the feet, and an attack covers `reach` in front and a little
## behind, mirrored when facing left.

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
