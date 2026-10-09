class_name PasswordHash
extends RefCounted
## Turns a password into something safe to keep on disk, and checks a password against it.
## The server never stores a password, only this: PBKDF2-HMAC-SHA256 with a random salt
## per account, run many rounds so guessing passwords from a stolen file is slow.
##
## A record is a Dictionary saved inside the account file:
##   {"algo": "pbkdf2-sha256", "rounds": 100000, "salt": "<hex>", "hash": "<hex>"}
## The round count is kept per record, so ROUNDS can be raised later and old accounts
## still log in.

const ALGO := "pbkdf2-sha256"
const ROUNDS := 100000
const SALT_BYTES := 16

## Rounds for new records. Tests lower it so they run quickly.
static var rounds := ROUNDS

## A new record for `password`, with a fresh random salt.
static func make(password: String) -> Dictionary:
	var salt := Crypto.new().generate_random_bytes(SALT_BYTES)
	return {"algo": ALGO, "rounds": rounds, "salt": salt.hex_encode(), "hash": pbkdf2(password, salt, rounds).hex_encode()}

## Whether `password` is the one `record` was made from.
static func verify(password: String, record: Dictionary) -> bool:
	if record.get("algo") != ALGO:
		return false
	var n := int(record.get("rounds", 0))
	var salt := String(record.get("salt", "")).hex_decode()
	var want := String(record.get("hash", "")).hex_decode()
	if n <= 0 or salt.is_empty() or want.size() != 32:
		return false
	return _same(pbkdf2(password, salt, n), want)

## PBKDF2-HMAC-SHA256 with one 32-byte block (RFC 8018). The XOR runs on four 64-bit
## numbers instead of 32 bytes, which keeps it fast enough in GDScript.
static func pbkdf2(password: String, salt: PackedByteArray, n: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var key := password.to_utf8_buffer()
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, key, salt + PackedByteArray([0, 0, 0, 1]))
	var acc := [u.decode_s64(0), u.decode_s64(8), u.decode_s64(16), u.decode_s64(24)]
	for i in n - 1:
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, key, u)
		acc[0] ^= u.decode_s64(0)
		acc[1] ^= u.decode_s64(8)
		acc[2] ^= u.decode_s64(16)
		acc[3] ^= u.decode_s64(24)
	var out := PackedByteArray()
	out.resize(32)
	for k in 4:
		out.encode_s64(k * 8, acc[k])
	return out

## Compares every byte, so how long it takes doesn't hint at where they differ.
static func _same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0
