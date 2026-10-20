class_name SocialPart
extends RefCounted
## One area of TDSocial: chat, parties or trades. The shared state
## lives on TDSocial; a part only keeps a weak reference back to it, so the two don't keep
## each other alive.

## The TDSocial this part belongs to.
var social: TDSocial:
	get:
		return _social.get_ref()
var server: TDServer:
	get:
		return social.server

var _social: WeakRef

func _init(s: TDSocial) -> void:
	_social = weakref(s)

func tell(p: SimPlayer, text: String, col := TDSocial.INFO) -> void:
	social.tell(p, text, col)
