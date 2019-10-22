## Why

I despise gravity boosters with a passion. Never has such a terrible method for boosting a player become so common. This at least makes them usable for lower timescale bhop styles.

## Requirements

Server running sourcemod 1.10 or greater, and a compiler to build it.
[Stripper Dump Parser](https://github.com/kidfearless/Stripper-Dump-Parser)

## What's It Do

If a trigger brush that both lowers and resets a players gravity is activated and the player is on a lower timescale, the the plugin will be called. The plugin grabs how long the gravity is lowered for and extends it proportionally to the players timescale. Does not activate for normal(1.0) timescale.   


## Notes

* Requires sourcemod 1.10
* Does not properly take into account delay.
* Does not take into account if the player is teleported after activating
* Does not work on multi-brush gravity boosters
* Might cause undesirable effects on boosters that lower and reset gravity but also have a second block to reset gravity. I wonder what kind of idiot mapper would do that (Tony Montana).
* This is not a pushfix plugin, this forces the gravity that would be set on a player of lower/higher timescale to be applied long enough for them to run the map normally.
* Tony Montana is a terrible mapper