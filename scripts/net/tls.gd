class_name TDTls
extends RefCounted
## Encryption for the connection between a game and a server (DTLS, built into Godot's
## ENet), so passwords and everything else can't be read on the way.
##
## The server uses the key and certificate in `<save folder>/tls/` (server.key and
## server.crt), and makes a self-signed pair there the first time if there are none. A real
## certificate (for example one bought for the live server's domain) can be dropped in
## its place.
##
## A game always encrypts. It checks who the server is only when it has the server's
## certificate: `res://certs/<address>.crt` (shipped with the game for official servers).
## For any other server the connection is encrypted but the server's identity isn't
## proven, so it stops eavesdroppers but not someone pretending to be the server.

const KEY_FILE := "server.key"
const CERT_FILE := "server.crt"
const CERTS := "res://certs"

## A stand-in trusted certificate for unchecked connections: Godot needs one to set up an
## encrypted client even when it won't check the server against it.
static var _stand_in: X509Certificate

## The server's encryption settings, making a key and certificate if there are none yet.
static func server_options(save_folder: String) -> TLSOptions:
	var dir := save_folder.path_join("tls")
	DirAccess.make_dir_recursive_absolute(dir)
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	var have := FileAccess.file_exists(dir.path_join(KEY_FILE)) and FileAccess.file_exists(dir.path_join(CERT_FILE))
	if not have or key.load(dir.path_join(KEY_FILE)) != OK or cert.load(dir.path_join(CERT_FILE)) != OK:
		var crypto := Crypto.new()
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=Tera's Dawn server,O=Tera's Dawn", "20250101000000", "20450101000000")
		key.save(dir.path_join(KEY_FILE))
		cert.save(dir.path_join(CERT_FILE))
	return TLSOptions.server(key, cert)

## A game's encryption settings for connecting to `address`.
static func client_options(address: String) -> TLSOptions:
	var known := CERTS.path_join(address + ".crt")
	if FileAccess.file_exists(known):
		var cert := X509Certificate.new()
		if cert.load(known) == OK:
			return TLSOptions.client(cert)
	if _stand_in == null:
		var crypto := Crypto.new()
		_stand_in = crypto.generate_self_signed_certificate(crypto.generate_rsa(1024), "CN=unchecked", "20250101000000", "20450101000000")
	return TLSOptions.client_unsafe(_stand_in)
