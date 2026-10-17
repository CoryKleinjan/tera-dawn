class_name Counters
extends RefCounted
## The tallies a Character keeps in `counters` (added to with Character.count) because
## nothing else records them, for achievements to measure (an AchievementDef's `kind`).
## The names are saved with the character, so never change one.

## Bosses defeated.
const BOSSES := "bosses"
## Times sat down.
const SAT := "sat"
## Times a pet was brought out.
const PETS := "pets"
## Trades finished.
const DEALS := "deals"
## Bosses defeated without taking a hit since arriving on their map.
const CLEAN_BOSSES := "clean_bosses"
## Every tally above.
const ALL: Array[String] = [BOSSES, SAT, PETS, DEALS, CLEAN_BOSSES]
