extends TestCase
## Password hashing: PBKDF2-HMAC-SHA256 gives the standard answers, records check the
## right password and refuse others, and no password is kept in a record.

func test_pbkdf2_matches_the_standard_test_vectors() -> void:
	# RFC 7914 section 11 (PBKDF2-HMAC-SHA256, first 32 bytes)
	check_eq(PasswordHash.pbkdf2("passwd", "salt".to_utf8_buffer(), 1).hex_encode(),
		"55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc", "1 round")
	check_eq(PasswordHash.pbkdf2("password", "salt".to_utf8_buffer(), 4096).hex_encode(),
		"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "4096 rounds")

func test_a_record_checks_its_password_only() -> void:
	PasswordHash.rounds = 100
	var r := PasswordHash.make("dawn breaks")
	PasswordHash.rounds = PasswordHash.ROUNDS
	check(PasswordHash.verify("dawn breaks", r), "right password")
	check(not PasswordHash.verify("dawn Breaks", r), "case matters")
	check(not PasswordHash.verify("", r), "empty")
	check_eq(int(r["rounds"]), 100, "rounds kept in the record")

func test_records_hold_no_password_and_each_has_its_own_salt() -> void:
	PasswordHash.rounds = 50
	var a := PasswordHash.make("same password")
	var b := PasswordHash.make("same password")
	PasswordHash.rounds = PasswordHash.ROUNDS
	check(not JSON.stringify(a).contains("same password"), "no password in it")
	check_ne(a["salt"], b["salt"], "salts differ")
	check_ne(a["hash"], b["hash"], "so hashes differ")

func test_broken_records_never_match() -> void:
	check(not PasswordHash.verify("x", {}), "empty record")
	check(not PasswordHash.verify("x", {"algo": "plain", "hash": "x"}), "unknown kind")
