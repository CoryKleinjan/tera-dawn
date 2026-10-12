class_name ServerAddress
extends RefCounted
## Reads what a player typed in the Server box: an address, optionally with a port after a
## colon ("192.168.1.20", "192.168.1.20:7351", "[::1]:7351"). A plain address uses
## Net.DEFAULT_PORT.

## {host, port, error}: `error` is "" or what's wrong, in words for the player.
static func parse(text: String, default_port := Net.DEFAULT_PORT) -> Dictionary:
	var t := text.strip_edges()
	var host := t
	var port_text := ""
	var has_port := false
	if t.begins_with("["):  # an IPv6 address in brackets, maybe with a port
		var close := t.find("]")
		if close < 0:
			return _bad("The server address is missing a ].")
		host = t.substr(1, close - 1)
		var rest := t.substr(close + 1)
		if rest != "":
			if not rest.begins_with(":"):
				return _bad("Put the port after the ] and a colon, like [::1]:%d." % default_port)
			port_text = rest.substr(1)
			has_port = true
	elif t.find(":") >= 0 and t.find(":") == t.rfind(":"):  # more than one colon is a bare IPv6 address, with no port
		host = t.get_slice(":", 0)
		port_text = t.get_slice(":", 1)
		has_port = true
	if host == "":
		return _bad("Type the server's address.")
	var port := default_port
	if has_port:
		if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
			return _bad("The port after the colon must be a number from 1 to 65535.")
		port = int(port_text)
	return {"host": host, "port": port, "error": ""}

static func _bad(why: String) -> Dictionary:
	return {"host": "", "port": 0, "error": why}
