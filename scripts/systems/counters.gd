class_name Counters
extends RefCounted
## The tallies a Character keeps in `counters` (added to with Character.count) because
## nothing else records them, for achievements to measure (an AchievementDef's `kind`).
## The names are saved with the character, so never change one.

## Bosses defeated.
const BOSSES := "bosses"
## Upgrade scrolls that worked.
const SCROLLS := "scrolls"
## Times sat on a chair.
const SAT := "sat"
## Times a pet was brought out.
const PETS := "pets"
## Trades and player-shop sales finished.
const DEALS := "deals"
## Every tally above.
const ALL: Array[String] = [BOSSES, SCROLLS, SAT, PETS, DEALS]
