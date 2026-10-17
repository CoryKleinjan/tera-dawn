class_name Palette
extends RefCounted
## Shared colours for the UI, effects and server messages. Use these instead of writing a
## colour by hand, so a colour means the same thing everywhere.

# Base colours: the travel leather-and-parchment UI (dark oiled leather, tan leather, brass,
# parchment cream), with the dawn's sun and ember for highlights.
const NIGHT := Color("1f140c")
const PLUM := Color("5c3b22")
const SUN := Color("ffd166")
const EMBER := Color("ff7a59")
const MIST := Color("fff3e4")
const HP := Color("ff5d73")
const MP := Color("5aa9ff")

# What a colour means.
## Secondary text: labels, descriptions, "level 12".
const MUTED := Color("d8c4a6")
## Good news: a requirement met, a quest ready, a success.
const GOOD := Color("8cf0a6")
## Bad news: unaffordable, unmet, a failure.
const BAD := Color("ff6b7d")
## A warning or a downside.
const WARN := Color("ffb38a")
## General information (system messages, whispers).
const INFO := Color("8cc6ff")
## Dark brown text on gold buttons and on paper (the Monster Book, speech bubbles, invitations).
const INK := Color("3b2208")
## Secondary text on paper.
const INK_SOFT := Color("7a5634")
## The brass trim on buttons and frames.
const GOLD_TRIM := Color("d4a759")
## Hover and selection highlight; use with HILITE_ALPHA.
const HILITE := Color(1, 0.85, 0.45)
const HILITE_ALPHA := 0.18
## The faint dark backdrop behind text drawn straight over the scene (the message log, chat).
const BACKDROP := Color(NIGHT, 0.4)

# Accents for particular things.
const PET := Color("ffd9a8")
const CARD := Color("a8e6ff")
## Runes and what they add (tooltips, the enchanter).
const RUNE := Color("d9b8ff")
const GUILD := Color("b8f070")
