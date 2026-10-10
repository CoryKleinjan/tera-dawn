extends TestCase
## LoginGuard: wrong passwords count per address, so a stranger can't lock the owner out;
## an address waits longer after each wrong password, for any username; a connection is
## dropped after MAX_TRIES.

const HOME := "10.0.0.1"
const STRANGER := "10.0.0.66"

var g: LoginGuard

func before_each() -> void:
	g = LoginGuard.new()

## Wrong passwords for `user` from `address`, each once the last one's wait is over.
## Returns the tick of the last one.
func _guess(address: String, user: String, times: int) -> int:
	var tick := 0
	for i in times:
		if i > 0:
			tick += LoginGuard.wait_ticks(i)
		g.failed(2, address, user, tick)
	return tick

func test_the_wait_doubles_up_to_a_minute() -> void:
	check_eq(LoginGuard.wait_ticks(1), 60, "1 s after one")
	check_eq(LoginGuard.wait_ticks(2), 120, "2 s after two")
	check_eq(LoginGuard.wait_ticks(3), 240, "4 s after three")
	check_eq(LoginGuard.wait_ticks(7), LoginGuard.MAX_WAIT_TICKS, "a minute at most")
	check_eq(LoginGuard.wait_ticks(100), LoginGuard.MAX_WAIT_TICKS, "never more")

func test_an_address_waits_after_a_wrong_password_whatever_the_username() -> void:
	g.failed(2, STRANGER, "rowan", 0)
	check(g.waiting(STRANGER, "mira", 30), "another account has to wait too")
	check(not g.waiting(STRANGER, "mira", 60), "after a second")
	g.failed(2, STRANGER, "mira", 60)
	check(g.waiting(STRANGER, "ash", 60 + 119), "two seconds after the second")
	check(not g.waiting(STRANGER, "ash", 60 + 120), "then free")

func test_a_stranger_cant_lock_the_owner_out() -> void:
	var tick := _guess(STRANGER, "rowan", LoginGuard.MAX_TRIES * 3) + 1
	check(g.waiting(STRANGER, "rowan", tick), "the stranger is locked out of rowan")
	check(not g.waiting(HOME, "rowan", tick), "the owner at home is not")

func test_an_address_is_locked_out_of_a_username_after_too_many_wrong_passwords() -> void:
	var last := _guess(HOME, "rowan", LoginGuard.MAX_TRIES)
	var tick := last + LoginGuard.wait_ticks(LoginGuard.MAX_TRIES)
	check(g.waiting(HOME, "rowan", tick), "locked, past the growing wait")
	check(not g.waiting(HOME, "mira", tick), "other usernames only wait the growing wait")
	check(not g.waiting(HOME, "rowan", last + LoginGuard.LOCK_TICKS), "until the lock runs out")

func test_a_right_password_clears_the_counts() -> void:
	var tick := _guess(HOME, "rowan", LoginGuard.MAX_TRIES - 1) + 1
	g.succeeded(HOME, "rowan")
	g.failed(3, HOME, "rowan", tick)
	check(not g.waiting(HOME, "rowan", tick + LoginGuard.FIRST_WAIT_TICKS), "back to a one second wait")

func test_a_connection_is_dropped_after_too_many_wrong_passwords() -> void:
	for i in LoginGuard.MAX_TRIES - 1:
		check(not g.failed(2, "peer 2", "user%d" % i, i * LoginGuard.MAX_WAIT_TICKS), "try %d keeps the connection" % (i + 1))
	check(g.failed(2, "peer 2", "last", 0), "the last try drops it")
	g.forget_peer(2)
	check(not g.failed(2, "peer 2", "again", 0), "a new connection on that id starts over")
