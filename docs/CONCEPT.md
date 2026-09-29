# Bonfire: Concept Brief (WoW: Forever)

Formerly "Campfire Games". Status: MVP scaffold built. Researched 2026-09-28 (Forever beta, launch Nov 4 2026). Beta test runs through Oct 21.

## Why it fits

- Forever's Camping system requires players to sit or craft near a campfire for about a minute to get the camp buff. Blizzard has since allowed buffs, crafting and emotes during the wait, and a 1–2 minute game fills exactly that downtime.
- Expert campfires (Cooking 200) hold up to 10 features, and each player contributes only one, so camps naturally pull several players together.
- Players complain that campfires are hard to find (they've asked for a smoke trail or minimap icon). An addon beacon for open tables also solves discovery. **This is half of the addon, not an extra:** Bonfire is the smoke signal until the game has one.

## Technical ground truth

- Forever uses Mainline's UI architecture (roughly 12.1.5 APIs) with Midnight's addon restrictions. Client 1.60.1, `## Interface: 16001`.
- Midnight's comms restrictions apply only during M+ runs, PvP matches and instance encounters. Open-world addon comms and chat are unrestricted, so campfires are fine.
- Addons cannot move gold. Gold only moves through the trade window with both players clicking Accept.
- Addon comms are same-faction only, and players on different layers can't see each other.
- Sound APIs (PlaySoundFile / PlayMusic) weren't in the published Midnight restriction lists. Verify in beta.
- The campfire proximity aura is the likely detection hook. Confirm its name/ID in beta.

## Core pillars

1. **Discovery:** broadcast campfire, zone, coords, game and seats on a hidden custom channel; show nearby open tables on the map/minimap.
2. **Table lobby:** host-authoritative state machine, 2–10 seats plus spectators, AceComm + ChatThrottleLib.
3. **Games** (1–2 min, simultaneous turns for big tables):
   - Embers: push-your-luck with one shared die (built for the MVP)
   - Deathroll (server /roll)
   - Liar's Dice / bluff dice
   - Push-your-luck dice (Pig/Farkle-style)
   - 21 vs. dealer
   - Critter Race spectator betting on /roll-driven racers
4. **Stakes modes:** For fun (default, no gold), Banked (host escrow, built: players pay the host before a round via a trade queue; winnings held as credit until cash-out), Honor ledger (settle via trade later). Include a bet cap. Stakes are picked in steps of 5 or 10 of gold, silver or copper; gambling fires show a coin icon.
5. **Music:** a synced campfire jukebox using in-game music file IDs and scheduled start times; a band session where each player takes an instrument stem and plays a light rhythm prompt (misses mute the stem). Bundle original or public-domain music only, never extracted Blizzard audio.
6. **Extras:** fireside tales and RP prompts with voting, a camp guestbook ("shared a fire with…"), stats and addon-only titles, optional auto-emotes on win/loss.

## Duels (design, not built)

The 35 yd ring around the fire doubles as an arena.

- **Challenge:** from the table window, one player challenges another. Both must be seated, in range, and not in a game. The challenged player accepts in the window. Bonfire uses the game's own `/duel` (`StartDuel`) if addons can call it in Forever; otherwise it prompts both players to start one by hand.
- **Result:** the winner comes from the server's duel system message ("X has defeated Y in a duel"), parsed like /roll, so it can't be faked. Stepping outside the ring counts as a loss (the range check already exists). Fleeing or the game's own boundary also ends it.
- **Betting:** everyone else at the table can bet on a duelist through the same host ledger: bets are paid to the host before the fight, and the winning side splits the pot in proportion to their bets. The duelists can also stake each other. For-fun duels skip all of it.
- **Open questions (beta):** can addons call `StartDuel` and read the duel events? What are the message formats and the game's own duel radius? Does the duel radius match 35 yd, or do we need our own check?
- **Leaving the ring:** if a duelist steps outside 35 yd of the fire at any moment, the duel is cancelled automatically, the other duelist wins, and any bets pay out as if the leaver lost.
- **Known catch:** the native duel needs both players within about 10 yd to start.

## Deathroll (rules built and tested, not wired to the table yet)

Rules live in `Games/Deathroll.lua`. Every player has to click Roll within a time limit (8 s) or they fold instantly. Real `/roll`s are read from chat by the host.

- **All out:** everyone rolls 1 to 100 at once. If an even number rolled, the **highest and lowest** rollers are knocked out. If odd, only the **highest** goes. Ties for either end re-roll among just the tied players. This repeats until two remain.
- **The duel:** the last two take turns. The first rolls 1 to 100, each next roll is 1 to the roll before, and whoever rolls a 1 loses. Folding hands the win to the other player.
- **1v1 tables:** two players go straight to the duel while everyone else bets on a side (side bets: see below).
- Everyone timing out together leaves no winner and the pot is returned.

Both modes need every player's roll to be visible to the host, which is the first thing to check in the two-player test.

## The Odd Man Out (rules built and simulated, not wired to the table yet)

Rules in `Games/OddManOut.lua`; play thousands of games with `scripts\sim.ps1`.

- Two to ten players. Everyone secretly picks a number. Each round everyone rolls once; you're knocked out if any *other* player rolled your number. Players can pick the same number. Last one standing wins.
- The die is d20 while six or more players are left and d10 with five or fewer. When it shrinks, everyone picks again in the new range.
- A round that would knock out everyone left is replayed instead. Anyone who doesn't pick (15 s) or roll (8 s) in time folds.
- Simulation (20,000 games per size, random picks): 5.6 rounds on average for two players up to 9.1 for ten (median 4 to 8, 90th percentile 12 to 16), never stuck, every seat wins an equal share, about 5 to 7% of games have a replayed wipeout round. Two players on d10 have the long tail (18% chance a round decides it), up to 50-plus rounds in rare games.
- Needs each player's own `/roll` to be visible to the host (the two-player roll test), and picks are held by the host's addon and revealed when a player is knocked out.

## Side bets (built; needs two-player testing)

Spectators bet on either fighter through the host ledger: pay the host before the lock, unpaid bets are dropped when betting locks, winners get their stake back plus a share of the losing side in proportion to their bet, and the host can take an optional cut. Used by duels, 1v1 Deathroll and Critter Race. See the mockups in the design session; the window shows both pools, live odds, a lock countdown, and for the host a queue to collect bets and pay winners.

## Critter Race (design)

Six low-poly critters (rat, gopher, frog, squirrel, rabbit, and one more), shown as live 3D model frames. Each critter owns one face of a six-sided die. When the die lands, that critter steps forward; the first to take 3 or 4 steps (set per race) wins.

- **Rolls:** if `RandomRoll` can be fired without a click each time (to check in the beta), the host runs real public /rolls, one per step. If it needs a click, the host clicks once and that one public roll seeds a fixed sequence of die results that every client plays out identically: same look, one click, still publicly verifiable, and only the first roll after the start announcement counts.
- **Odds must be real.** With a fair die every critter has the same chance, so randomly shuffled odds would just create free money on whichever pick shows the biggest number. Two safe ways to make odds mean something:
  - **Pool odds:** payouts come from the betting pool (parimutuel), so the displayed odds are just how the money is split. The host carries no risk.
  - **Race form:** each race randomly gives critters a handicap (needs 3 steps or 4, a head start). The true odds come from working out every way the race can go, and the display and payouts use them.
- **Team favorites:** every player picks a favorite critter, shown beside their name. Clients share race results (deduped by race id, same way as the Honest Broker) so everyone sees how often each critter has won across all Bonfire users. A leaderboard of teams is cosmetic by default. If history should affect the race, it does so through a small bounded "form" rating that is folded into the odds, so the odds stay honest.
- Uses the same host ledger and side-bet payouts as everything else.

## Main menu and game picker (design)

`/bf` stays the front door. When you host, the lobby gets a game picker (Embers, Deathroll, Critter Race, Duel) above the bet builder, and each game has its own play view inside the same window. The table only knows "the current game" and calls into a small shared game interface, so adding a game doesn't touch the ledger or the bets.

## Settlement: prepaid or a running tab

Prepaid escrow is the model. Players trade their stake to the host before a round and winnings are held as credit until cash-out. A running tab settled at the end means fewer trades, but the game has no way to make a loser pay: gold moves only through a trade both people accept, and GMs won't recover it. A tab turns every loss into a chance to walk away, so it needs a reputation system for players as well as hosts.

To keep the trades down without going on credit: buy in once for several rounds (a deposit of, say, five stakes) instead of paying every round, keep the running balance on the table, and net everything out at the end. The end-of-table recap (built) tells each player their record and what the host still owes them. A tab could come later for trusted players once the Honest Broker exists.

## Streaks and comeback bonuses

Real odds don't change after a losing streak (the game doesn't remember), so a bonus that rewards losing would be a hidden edge: lose small on purpose, then win big. What works safely:
- Pool odds already pay more for the less-backed side, which is the honest version of "a bigger cut".
- An optional **comeback pot**, off by default: a small host cut feeds a table pot, paid to the next winner after a streak of full-stake losses, capped so it can't be farmed.
- A per-table **win/loss tally** with net gold and streaks (built) shown beside each name.

## Honest Broker (design)

A shared, gossiped reputation ledger for hosts. See [HONEST-BROKER.md](HONEST-BROKER.md).

## Trust and fairness

- Public games use server /roll parsed from system chat, so no client can fake results.
- Hidden-hand games are host-dealt. The host posts a commit-reveal hash of the shuffle before the deal, and it's verified after the round.

## Risks

- Blizzard's gambling stance is murky: casinos were banned in 2005, and a 2009 blue post said casinos "aren't necessarily" against policy but the surrounding activities can be. GMs won't recover gold lost to gambling. Hence For fun by default, and gold tables are opt-in and marked with a coin.
- Combat interruptions: auto-pause, then forfeit after a timeout. Leaving range folds your hand.
- Cross-faction camps can't share a table.

## Phases

1. **MVP:** beacon + map pins, lobby, one dice game (Embers), For fun or gold stakes with host escrow, pay-in/payout trade queue, 35 yd fold range. *Built; needs beta verification (see BETA-NOTES.md).*
2. Practice players (built), side bets, then Deathroll, Duels and Critter Race on top of them; Honest Broker alongside.
3. Synced jukebox.
4. Band session rhythm mode.
