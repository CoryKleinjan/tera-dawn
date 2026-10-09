class_name Palette
extends RefCounted
## Shared colours for the UI, effects and server messages. Use these instead of writing a
## colour by hand, so a colour means the same thing everywhere.

# Base colours.
const NIGHT := Color("1b1230")
const PLUM := Color("4b3570")
const SUN := Color("ffd166")
const EMBER := Color("ff7a59")
const MIST := Color("fff3e4")
const HP := Color("ff5d73")
const MP := Color("5aa9ff")

# What a colour means.
## Secondary text: labels, descriptions, "level 12".
const MUTED := Color("c9b8d9")
## Good news: a requirement met, a quest ready, a success.
const GOOD := Color("8cf0a6")
## Bad news: unaffordable, unmet, a failure.
const BAD := Color("ff6b7d")
## A warning or a downside.
const WARN := Color("ffb38a")
## General information (system messages, whispers).
const INFO := Color("8cc6ff")
## Dark brown text on gold buttons.
const INK := Color("3b2208")
## The gold trim on buttons and frames.
const GOLD_TRIM := Color("e9b44c")
## Hover and selection highlight; use with HILITE_ALPHA.
const HILITE := Color(1, 0.85, 0.45)
const HILITE_ALPHA := 0.18

# Accents for particular things.
const PET := Color("ffd9a8")
const CARD := Color("a8e6ff")
const GUILD := Color("b8f070")
