class_name LoginGuard
extends RefCounted
## Slows down password guessing without letting a stranger lock anyone else out. Wrong
## passwords are counted by where they come from (the connection's address):
## - a connection that gets the password wrong MAX_TRIES times is dropped;
## - an address that gets one username wrong MAX_TRIES times in a row can't try that
##   username again for LOCK_TICKS (the owner logging in from elsewhere still can);
## - after each wrong password an address waits before its next try, whatever the
##   username: FIRST_WAIT_TICKS, doubling each time up to MAX_WAIT_TICKS, until it gets
##   one right. So guessing many accounts from one place is slow too.
## Times are server ticks (60 a second).

const MAX_TRIES := 5
const LOCK_TICKS := 30 * 60
const FIRST_WAIT_TICKS := 60
const MAX_WAIT_TICKS := 60 * 60

## peer -> wrong passwords on that connection
var _peer_fails := {}
## "address username" -> [wrong passwords in a row, tick of the last one]
var _name_fails := {}
## address -> [wrong passwords in a row (any username), tick of the last one]
var _address_fails := {}

## Whether `address` has to wait at `tick` before trying `username` again.
func waiting(address: String, username: String, tick: int) -> bool:
	var k := _key(address, username)
	var f: Array = _name_fails.get(k, [0, 0])
	if f[0] >= MAX_TRIES:
		if tick - int(f[1]) < LOCK_TICKS:
			return true
		_name_fails.erase(k)
	var a: Array = _address_fails.get(address, [0, 0])
	return a[0] > 0 and tick - int(a[1]) < wait_ticks(a[0])

## How long an address waits after `fails` wrong passwords in a row.
static func wait_ticks(fails: int) -> int:
	return mini(MAX_WAIT_TICKS, FIRST_WAIT_TICKS << mini(fails - 1, 16))

## Counts a wrong password. True when the connection has used up its tries.
func failed(peer: int, address: String, username: String, tick: int) -> bool:
	var k := _key(address, username)
	_name_fails[k] = [int(_name_fails.get(k, [0, 0])[0]) + 1, tick]
	_address_fails[address] = [int(_address_fails.get(address, [0, 0])[0]) + 1, tick]
	_peer_fails[peer] = int(_peer_fails.get(peer, 0)) + 1
	return _peer_fails[peer] >= MAX_TRIES

## A right password clears the address's counts.
func succeeded(address: String, username: String) -> void:
	_name_fails.erase(_key(address, username))
	_address_fails.erase(address)

func forget_peer(peer: int) -> void:
	_peer_fails.erase(peer)

static func _key(address: String, username: String) -> String:
	return "%s %s" % [address, AccountStore.key(username)]
