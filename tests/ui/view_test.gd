extends TestCase
## The screen and camera: everything is drawn between its last two ticks so motion is
## smooth at any refresh rate, the camera looks ahead and ignores small hops, and the HUD
## follows the screen's shape (16:10, like the Steam Deck's 1280x800).

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	ui.world.fit_to(Vector2(960, 540))
	ui.stop()

func test_moving_things_are_drawn_between_their_last_two_ticks() -> void:
	var w := ui.world
	var p := w.player
	await ui.ticks(2)
	var from := p.position
	ui.teleport(from + Vector2(30, 0))
	w._prev[p] = from
	var at := w.drawn(p)
	check(at.x >= from.x - 0.01 and at.x <= from.x + 30.01 and is_equal_approx(at.y, from.y), "on the way from %s to %s: %s" % [from, p.position, at])
	w._prev[p] = from - Vector2(500, 0)
	check_eq(w.drawn(p), p.position, "a jump (a portal, a respawn) doesn't glide")

func test_the_camera_looks_ahead_and_ignores_small_hops() -> void:
	var w := ui.world
	w.snap_camera()
	var p := w.player
	p.face = 1
	p.vel.x = 3.0
	for i in 60:
		w.camera.aim()
	check_eq(w.camera.look, float(WorldCamera.LOOK_AHEAD), "walking right, it looks ahead to the right")
	var floor_y := w.camera.floor_y
	p.vel.x = 0.0
	p.on_ground = false
	p.position.y -= WorldCamera.DEAD_ZONE - 20.0
	w.camera.aim()
	check_eq(w.camera.floor_y, floor_y, "a hop doesn't move it up or down")
	p.position.y -= 60.0
	w.camera.aim()
	check(w.camera.floor_y < floor_y, "rising well past where they stood does")

func test_the_hud_fits_a_16_by_10_screen() -> void:
	var w := ui.world
	w.fit_to(Vector2(960, 600))
	check_eq(TDWorld.VIEW, Vector2(960, 600), "the view grows taller")
	var hud := ui.hud
	check_eq(hud.quickslots.position.y + hud.quickslots.size.y, 600.0 - TDStatusBar.HEIGHT - 4, "quickslots sit on the status bar")
	check_eq(hud.chat.position.y + hud.chat.size.y, 600.0 - TDStatusBar.HEIGHT - 4, "so does the chat")
	check_eq(TDOverlay.minimap_rect().end.x, 960.0 - 189.0 + TDOverlay.minimap_rect().size.x, "the minimap keeps to the right edge")
	var inv: TDWindow = hud.windows["inventory"]
	inv.position = Vector2(0, 900)
	w.fit_to(Vector2(960, 540))
	check(Rect2(Vector2.ZERO, TDWorld.VIEW).encloses(Rect2(inv.position, inv.size)), "a window off a smaller screen comes back into view")
