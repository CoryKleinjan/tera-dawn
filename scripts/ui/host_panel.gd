class_name TDHostPanel
extends VBoxContainer
## On character select while hosting: what friends on the same network type under Join a
## friend (with a Copy button), and on Windows a button that lets them through the firewall
## when it would block them (LanHost).

var address_label: Label
var copy_button: Button
var firewall_label: Label
var firewall_button: Button
## What Copy puts on the clipboard ("" when no address was found).
var address := ""
## The port being hosted on.
var _port := 0
var _thread: Thread

func _init() -> void:
	add_theme_constant_override("separation", 4)
	address_label = UiBuild.label("", 14, Palette.SUN, HORIZONTAL_ALIGNMENT_CENTER)
	copy_button = UiBuild.gold_button("Copy", func() -> void: DisplayServer.clipboard_set(address), Vector2(70, 28))
	copy_button.tooltip_text = "Copy the address to send it to a friend"
	add_child(UiBuild.centered_row([address_label, copy_button]))
	firewall_label = UiBuild.label("", 13, Palette.MIST, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(firewall_label)
	firewall_button = UiBuild.gold_button("Allow friends through the firewall", _open_firewall, Vector2(260, 28))
	firewall_button.tooltip_text = "Windows will ask for permission once"
	add_child(UiBuild.centered_row([firewall_button]))

## Shows the host's address and firewall state for `port`.
func refresh(port: int) -> void:
	_port = port
	var found := LanHost.addresses()
	var suffix := "" if port == Net.DEFAULT_PORT else ":%d" % port
	address = found[0] + suffix if not found.is_empty() else ""
	address_label.tooltip_text = ""
	if address != "":
		address_label.text = "Friends on your network join with %s" % address
		if found.size() > 1:
			address_label.tooltip_text = "If that doesn't work, try %s" % ", ".join(Array(found.slice(1)).map(func(a: String) -> String: return a + suffix))
	else:
		address_label.text = "No home network found. Friends join with this computer's IP address."
	copy_button.visible = address != ""
	if _thread:
		return  # still waiting on the Windows prompt
	var open := LanHost.firewall_open(port)
	firewall_label.text = "" if open else "Windows' firewall may stop friends from joining."
	firewall_label.visible = not open
	firewall_button.visible = not open
	firewall_button.disabled = false

func _open_firewall() -> void:
	firewall_button.disabled = true
	firewall_label.text = "Say yes on the Windows prompt to let friends in."
	_thread = Thread.new()
	_thread.start(func() -> void:
		var ok := LanHost.open_firewall(_port)
		_firewall_done.call_deferred(ok))

func _firewall_done(ok: bool) -> void:
	_thread.wait_to_finish()
	_thread = null
	if ok:
		firewall_label.text = "Friends on your network can join now."
		firewall_button.hide()
	else:
		firewall_label.text = "The firewall wasn't changed, so friends may not be able to join. Press to try again."
		firewall_button.disabled = false

func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
