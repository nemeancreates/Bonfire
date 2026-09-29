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
- **Known catch:** the native duel needs both players within about 10 yd to start.

## Trust and fairness

- Public games use server /roll parsed from system chat, so no client can fake results.
- Hidden-hand games are host-dealt. The host posts a commit-reveal hash of the shuffle before the deal, and it's verified after the round.

## Risks

- Blizzard's gambling stance is murky: casinos were banned in 2005, and a 2009 blue post said casinos "aren't necessarily" against policy but the surrounding activities can be. GMs won't recover gold lost to gambling. Hence For fun by default, and gold tables are opt-in and marked with a coin.
- Combat interruptions: auto-pause, then forfeit after a timeout. Leaving range folds your hand.
- Cross-faction camps can't share a table.

## Phases

1. **MVP:** beacon + map pins, lobby, one dice game (Embers), For fun or gold stakes with host escrow, pay-in/payout trade queue, 35 yd fold range. *Built; needs beta verification (see BETA-NOTES.md).*
2. Duels with spectator bets (see above), then Critter Race + Deathroll with a gold ledger and spectator side bets.
3. Synced jukebox.
4. Band session rhythm mode.
