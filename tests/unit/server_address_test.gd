extends TestCase
## ServerAddress reads the Server box: an address, with an optional :port; LanHost picks
## the addresses friends on the same network can reach.

func test_a_plain_address_uses_the_default_port() -> void:
	var s := ServerAddress.parse(" 192.168.1.20 ")
	check_eq(s["host"], "192.168.1.20", "the address")
	check_eq(s["port"], Net.DEFAULT_PORT, "the default port")
	check_eq(s["error"], "", "no problem")

func test_a_port_after_a_colon() -> void:
	var s := ServerAddress.parse("192.168.1.20:7351")
	check_eq(s["host"], "192.168.1.20", "the address")
	check_eq(s["port"], 7351, "the port typed")
	check_eq(ServerAddress.parse("play.example.com:9000")["port"], 9000, "a name with a port")

func test_ipv6() -> void:
	check_eq(ServerAddress.parse("::1")["host"], "::1", "a bare IPv6 address has no port")
	check_eq(ServerAddress.parse("::1")["port"], Net.DEFAULT_PORT, "so it uses the default")
	check_eq(ServerAddress.parse("fe80::")["error"], "", "even one ending in a colon")
	var s := ServerAddress.parse("[::1]:7351")
	check_eq(s["host"], "::1", "the address in brackets")
	check_eq(s["port"], 7351, "the port after them")

func test_a_bad_port_is_refused() -> void:
	for text in ["192.168.1.20:", "192.168.1.20:abc", "192.168.1.20:0", "192.168.1.20:70000", ":7350", "[::1", "[::1]7350"]:
		check_ne(ServerAddress.parse(text)["error"], "", "%s is refused" % text)

func test_only_home_network_addresses_are_private() -> void:
	for a in ["192.168.1.20", "10.0.0.5", "172.16.0.1", "172.31.255.1"]:
		check(LanHost.is_private(a), "%s is on a home network" % a)
	for a in ["127.0.0.1", "8.8.8.8", "172.32.0.1", "169.254.1.1", "fe80::1", "nonsense"]:
		check(not LanHost.is_private(a), "%s isn't" % a)

func test_home_addresses_are_listed_best_first() -> void:
	for a in LanHost.addresses():
		check(LanHost.is_private(a), "%s is a home network address" % a)
