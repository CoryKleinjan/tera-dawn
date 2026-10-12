class_name LanHost
extends RefCounted
## What a host needs so friends on the same network can join: this computer's address on
## the home network, and (on Windows) a firewall rule letting the game's port in.
##
## The firewall rule is added through Windows' own admin prompt, so it only happens when the
## player says yes. It covers private and work networks, not public ones (cafés, airports).
## macOS asks about the firewall by itself and Linux usually has none, so there's nothing to
## do on those.

## The name of the firewall rule for `port`.
static func rule_name(port: int) -> String:
	return "Teras-Dawn-UDP-%d" % port

## This computer's addresses on home or office networks (IPv4), best guess first:
## 192.168.x.x, then 10.x.x.x, then 172.16-31.x.x. Empty when it isn't on one.
static func addresses() -> PackedStringArray:
	var found: Array[String] = []
	for a in IP.get_local_addresses():
		if is_private(a) and not found.has(a):
			found.append(a)
	found.sort_custom(func(a: String, b: String) -> bool: return _rank(a) < _rank(b) or (_rank(a) == _rank(b) and a < b))
	return PackedStringArray(found)

## Whether `address` is an IPv4 address only reachable on a local network.
static func is_private(address: String) -> bool:
	return _rank(address) < 3

## 0 for 192.168.x.x, 1 for 10.x.x.x, 2 for 172.16-31.x.x, 3 for anything else.
static func _rank(address: String) -> int:
	var parts := address.split(".")
	if not address.is_valid_ip_address() or parts.size() != 4:
		return 3
	var a := int(parts[0])
	var b := int(parts[1])
	if a == 192 and b == 168:
		return 0
	if a == 10:
		return 1
	if a == 172 and b >= 16 and b <= 31:
		return 2
	return 3

## Whether this computer has a firewall the game can check and open (Windows).
static func has_firewall() -> bool:
	return OS.get_name() == "Windows"

## Whether the firewall rule for `port` is there.
static func firewall_open(port: int) -> bool:
	if not has_firewall():
		return true
	return OS.execute("netsh", ["advfirewall", "firewall", "show", "rule", "name=" + rule_name(port)]) == 0

## Adds the firewall rule for `port`, through Windows' admin prompt, and waits for it.
## Returns whether the rule is there afterwards (false if the player said no). Blocks, so
## run it on a thread.
static func open_firewall(port: int) -> bool:
	if not has_firewall():
		return true
	var rule := "advfirewall firewall add rule name=%s dir=in action=allow protocol=UDP localport=%d profile=private,domain" % [rule_name(port), port]
	OS.execute("powershell", ["-NoProfile", "-Command",
		"Start-Process -FilePath netsh -ArgumentList '%s' -Verb RunAs -Wait -WindowStyle Hidden" % rule])
	return firewall_open(port)
