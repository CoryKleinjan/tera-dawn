class_name LoginGuard
extends RefCounted
## Slows down password guessing. A connection that gets the password wrong MAX_TRIES times
## is dropped, and a username that gets it wrong MAX_TRIES times in a row (from any
## connection) can't try again for LOCK_TICKS. Times are server ticks (60 a second).

const MAX_TRIES := 5
const LOCK_TICKS := 30 * 60

## peer -> wrong passwords on that connection
var _peer_fails := {}
## username key -> [wrong passwords in a row, tick of the last one]
var _name_fails := {}

## Whether `username` is waiting out a lock at `tick`.
func locked(username: String, tick: int) -> bool:
	var f: Array = _name_fails.get(AccountStore.key(username), [0, 0])
	if f[0] < MAX_TRIES:
		return false
	if tick - int(f[1]) >= LOCK_TICKS:
		_name_fails.erase(AccountStore.key(username))
		return false
	return true

## Counts a wrong password. True when the connection has used up its tries.
func failed(peer: int, username: String, tick: int) -> bool:
	var k := AccountStore.key(username)
	var f: Array = _name_fails.get(k, [0, 0])
	_name_fails[k] = [int(f[0]) + 1, tick]
	_peer_fails[peer] = int(_peer_fails.get(peer, 0)) + 1
	return _peer_fails[peer] >= MAX_TRIES

## A right password clears the username's count.
func succeeded(username: String) -> void:
	_name_fails.erase(AccountStore.key(username))

func forget_peer(peer: int) -> void:
	_peer_fails.erase(peer)
