# Bonfire quip lines

Your character says a line in `/say` and does an emote on one of your clicks. Nothing here is on a timer.

## When a line is said

The game only lets an addon speak for you during one of your own clicks in Bonfire (Start, Roll, Bank, a number pick, Pay, Cash out, Join). So a moment that happens between clicks waits for your next click, briefly:

- A reaction to your roll (high, low, fire out) keeps for **8 seconds** and is **never said on a Roll click**, since that click makes a new roll and the line would sound like it's about that one. In practice it's said when you Bank.
- A win, loss or streak line keeps for **30 seconds**, and any click can carry it (usually Rematch, Cash out or Pay).
- After that it's dropped, never said out of context later.
- Nothing is ever said on its own. If you click a lot, a line can't follow another within **8 seconds** (a spam limit, not a timer). `/bf chat` turns all of it off. Practice players say their lines as text in the Bonfire tab.

| Moment | How often | Whose |
|---|---|---|
| Start | 40% when the host presses Start | host |
| Win / Lose | 60% at the end of a game you played | anyone |
| Win streak / Lose streak | always, at 3+ in a row | anyone |
| Game begun | always, on the host's first roll of a game | host |
| High roll (5-6) / Low roll (2) | 10%, Bonfire game only | the host (the one rolling) |
| Fire goes out (a 1) | 35%, Bonfire game only | the host |
| Cashing out | 60% on Cash out | players |
| Any other click | 8% | anyone |

## What's in the addon now (generic, same for every race and class)

**Start** (host pressing Start)
- Let's light this fire!
- Fortune favors the bold.
- May the dice be kind.
- Everyone ready? Here we go.
- Stoke the flames!

**Game begun** (always said on the host's first roll of a game)
- And we're off!
- The game is on!
- Dice in the air!
- First roll, here we go!

**Win**
- That's how it's done!
- Sweet, sweet victory.
- The fire loves me.
- Better luck next time, friends.
- Beginner's luck? I think not.
- Emotes: cheer, clap, laugh

**Lose**
- Well, that stung.
- The fire has other plans for me.
- Next round is mine.
- I'll get it back.
- Ouch. Just ouch.
- Emotes: sigh, shrug, laugh, facepalm

**Win streak (3+)**
- I can't stop winning!
- The flames are on my side today.
- Is this luck or skill?
- Hot streak, don't touch me!
- Emotes: cheer, flex, clap

**Lose streak (3+)**
- Is the fire mocking me?
- Three in a row. Really?
- I'm officially cursed.
- Somebody check the dice.
- Emotes: cry, sigh, facepalm

**High roll** (Bonfire game, 5 or 6)
- Now THAT'S a roll!
- Feeling lucky!
- Big number, big smile.
- Emote: cheer

**Low roll** (Bonfire game, 2)
- Oof, small one.
- The dice hate me.
- Could've been worse. Maybe.
- Emote: sigh

**Fire goes out (a rolled 1 in the Bonfire game)**
- It sizzled out!
- Not the fire!
- And there goes the pot.
- Emote: cry

**Cashing out**
- Pleasure doing business.
- Thank you kindly!
- Until next time, friends.
- Emote: bow

**Any other click** (8%, Roll and number picks included)
- Nothing like a fire on a cold night.
- Anyone else smell marshmallows?
- This is the life.
- Who's up for another round?
- Watch the sparks!
- Don't stand too close to the fire.

Practice players use the same lines, as text in the Bonfire tab.

---

## Proposed: by race (each has a start line, two win lines, two lose lines)

Lines for a moment of that mood are sometimes swapped in for the generic ones. Nothing below is in the addon yet.

**Human**
- Start: For the Alliance, and for a good pot!
- Win: Never underestimate a human with a plan. / Stormwind stands tall tonight!
- Lose: A setback. Humans always bounce back. / Even the Light needs a reroll.

**Dwarf**
- Start: Pour me an ale and deal me in!
- Win: Hah! Ironforge steel and Ironforge luck! / That'll pay for the next round o' ale!
- Lose: By my beard, the dice are cheatin'! / Bah! I've lost more at Thelsamar.

**Night Elf**
- Start: Elune, guide the dice.
- Win: The night favors me. / Ishnu-alah, friends.
- Lose: The moon hides her face tonight. / Patience. Even the Ancients lost a game or two.

**Gnome**
- Start: Calculating odds... and they look excellent!
- Win: Exactly as I predicted. Mostly. / My probability engine never fails!
- Lose: Note to self: recalibrate the dice. / That wasn't in the schematics.

**Orc**
- Start: Lok'tar! Let's see who's strong!
- Win: Victory! Lok'tar ogar! / Strength wins again!
- Lose: Bah! I'll crush the next one. / The spirits test me.

**Undead**
- Start: Let's see if the living can keep up.
- Win: Even in death, I never lose. / Delicious. Well, not literally.
- Lose: I've lost worse. Ask my left arm. / Dead broke, and I mean that literally.

**Tauren**
- Start: May the Earthmother watch over this fire.
- Win: The spirits have blessed me. / Bulls are strong, but luck is stronger.
- Lose: The hunt teaches patience. / A stumble. The Earthmother is testing me.

**Troll**
- Start: Ya mon, let's roll dem bones!
- Win: Da loa smile on me today, mon! / Hah! Zul'jin himself couldn't beat dat!
- Lose: Da loa be playin' tricks on me. / Bad roll, mon. I be back.

## Proposed: by class

**Warrior**
- Start: Battle stance, everyone!
- Win: Victory through strength! / I don't need luck. Okay, maybe a little.
- Lose: I've taken worse hits than this. / That one went right through my armor.

**Paladin**
- Start: The Light guides this table.
- Win: The Light provides! / Justice is served.
- Lose: The Light tests the faithful. / I bless this loss. Sort of.

**Hunter**
- Start: Time to track down some fortune.
- Win: Another trophy for the wall! / Clean shot.
- Lose: The prey got away this time. / Even the best trackers lose a trail.

**Rogue**
- Start: Check your pockets. Kidding. Deal me in.
- Win: Easy pickings. / I never reveal my tricks.
- Lose: That's suspicious. Somebody stacked the deck. / I'll steal it back next round.

**Priest**
- Start: May fortune shine on us all.
- Win: Blessed be the lucky! / Praise be... to me?
- Lose: I forgive the dice. Mostly. / My faith is shaken, not broken.

**Shaman**
- Start: The spirits are restless. Let's play.
- Win: The elements answer my call! / Earth, wind and fire, all on my side.
- Lose: The elements are cruel tonight. / Even lightning misses sometimes.

**Mage**
- Start: A little arcane luck never hurt.
- Win: It's all in the wrist. And the arcane. / Cast: Win.
- Lose: That spell did not go as planned. / Time to blink out of this losing streak.

**Warlock**
- Start: Let's see what this fire demands.
- Win: The shadows favor me! / A fine offering to the flames.
- Lose: I traded my luck for power. Worth it. / The Void demands a sacrifice. Apparently it's my gold.

**Druid**
- Start: The wild has a lot to say about this game.
- Win: Nature provides! / Grows like a weed, this pot.
- Lose: Winter comes for us all. / I'll bear it. Get it? Bear?

## Proposed: race and class combinations (a start, a win and a lose line each)

These only fire for that exact pairing, and are picked before the race or class lines.

| Combo | Start | Win | Lose |
|---|---|---|---|
| Undead Warlock | The fire suits me. Warm, for once. | Dead men tell no tales, but they do win. | First my soul, now my gold. |
| Undead Rogue | Nobody checks a skeleton's pockets. | Dead quiet, dead good. | I'd say you got me, but I'm already dead. |
| Troll Shaman | Rollin' bones wit' da elements, mon! | Da spirits an' me, we be tight, mon! | Even da loa need a break, mon. |
| Troll Hunter | Da hunt be startin', mon! | Da hunt be good tonight, mon! | Da prey outsmarted me dis time. |
| Tauren Druid | The Earthmother and Elune agree: pass the ale. | Bear and bull together: unstoppable. | The moon and the earth both look away. |
| Tauren Warrior | Bulls charge first. | Bull rush! The pot is mine! | Bulls get back up. |
| Gnome Mage | Running the numbers on this fire... | Calculated. Spell-checked. Won. | Fascinating! ...and expensive. |
| Gnome Warlock | Small warlock, big appetite. | Imp-ossibly good luck! | Even my imp is embarrassed. |
| Dwarf Paladin | A cold ale and a warm fire. Light bless. | By the Light and by my beard! | Even a hammer can miss. |
| Dwarf Hunter | Me an' my rifle an' my luck. | Bullseye! Ha! | Missed. Bah. |
| Orc Warrior | For the Horde, and for gold! | Blood and thunder! The pot is mine! | I'll break the next thing that rolls. |
| Orc Shaman | The ancestors are watching. Deal. | Thrall would be proud! | The ancestors are laughing. |
| Night Elf Hunter | Even the forest listens to this fire. | Silent, patient, deadly. | The trail's gone cold. |
| Human Priest | A quiet prayer, a warm fire. | Light bless this winning hand. | Forgive me, Light, for what I just said. |
| Human Mage | Studied at Dalaran, and it shows. | Top of the class! | That's not what the textbook said. |

## How they would be chosen

When a quip fires, it first looks for a combo line, then a class line, then a race line, then a generic one. A flavored line is used some of the time rather than always (say combo 20%, class 25%, race 25%), so the plain ones still come up.

## Still to decide

- Which races and classes the Forever beta actually has. `/bf whoami` (new) prints the race and class your character reports, so the lines can be matched to it. Blood Elf, Draenei, Death Knight and so on can be added if they exist.
- Whether any lines are too much or not enough your style.
