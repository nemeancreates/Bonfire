# Two-player test plan

You need two players on the WoW: Forever beta, **same faction**, **same layer** (standing next to each other usually does it), both with Bonfire installed. Call them **A** (host) and **B**.

Before starting, both: `/console scriptErrors 1`, then `/reload`. Both need the same Bonfire version, 0.6.3 or later (the login line says `v0.6.3 loaded`): messages carry a checksum since 0.6.3, and older versions can't read them. Run `/bf api` (should say all present) and `/bf status` (`channel ... joined`, `me: ... learned from the channel`). Screenshot any red Lua error.

Write results in the tables in [BETA-NOTES.md](BETA-NOTES.md), or just tell Claude.

## 0. Do you hear each other?
Both: `/bf ping`. Six seconds later each of you should see the other listed as having answered, and `/bf status` should show "Bonfire user heard". If not, compare the `comms:` line on both sides (sent / own echoes / from others / pieces dropped / damaged) and tell Claude what each says. After any gold or bets step, `/bf status` again: *pieces dropped by the game* above 0 means the channel throttled us, which the table resends on its own. No table needs to be hosted for this.

## 1. Find and join (for fun)
1. A: place a campfire (Light a fire, or the kit from the bags). The Bonfire window should open by itself. Click **Host at this fire**.
2. B (about 50 yd away): a fire pin should show on the minimap and world map, and in `/bf`.
3. B: walk within 35 yd, click **Join**. Both windows should show both players seated.
   - This tests whispers to a two-word name, and that B's client trusts A as the host.

## 2. Rolls: the make-or-break check for Deathroll
Not grouped, standing together:
1. A types `/roll`. Does B see A's roll line in chat? B types `/roll`; does A see it?
2. Invite each other to a party and repeat.

Write down what each of you sees ungrouped and grouped. Every game where more than one player rolls depends on this.

## 3. A full Embers game
1. A clicks **Stoke**, then **Roll** repeatedly. Every roll should land: the pots grow and *last roll* shows the number (0.6.2 fixed the host's rolls being ignored). B clicks **Bank** at some point. Both windows should agree on pots and round.
   - During the game the host's money line says *In the pot: ...*, and B sees *Your stake is in the pot*, with no Pay button until the game ends.
2. Let a 1 come up (fire out, pots wiped) and finish all 5 rounds. Check the winner shows on both sides, and the **History** button on the main page (or `/bf history`) counts the game.

## 4. Range and hand-off
1. B walks past 28 yd: the top bar turns orange and says **RETURN TO THE FIRE OR FOLD**. Past 35 yd, three seconds later, B folds out of the table.
2. B rejoins. A walks 35+ yd away and waits about 12 seconds: B should be offered the table, and become host. Check both windows and that the fire pin now belongs to B.
3. The bar can be dragged and `/bf reset` puts it back.

## 5. Fire timer
A: `/bf burn 90` (fire has 90 s left). Watch the countdown on both clients. Start a game before it ends: it should become the last game, the table closes ~10 s after the result. Try again with no game running: it should close right away.

## 6. Gold (use tiny stakes: 5 copper)
1. A: pick **Gambling**, add 5 copper, **Confirm bet**, host. B: join.
2. B: click **Pay host**. The trade window should open with 5c filled in. Both click Trade. A's row for B should flip to *ready*.
   - If the amount isn't filled, note whether chat said "Enter ..." (the fallback didn't work) or "Filled in".
3. Play a game. The winner's credit shows as "held". Winner clicks **Cash out**, A clicks the **Pay** button that appears, both trade. Balance should clear.
4. If a trade isn't picked up: A can fix it with `/bf adjust <name> 5c`.

## 7. Side bets (needs a gold table, 5 copper bets are fine)
1. Both: the **Table** and **Bets** tabs sit in the title bar at any table (Bets is greyed on a For fun table). B clicks **Bets** first: it should say the host hasn't opened any rounds. A: **Bets**, then **New round**, pick a game, type `Oppa` in the first box, Tab, `Gopher` in the second (the *vs* is already between them), Enter (2 minutes to bet). The box you're typing in stays lit the whole time, even while the page updates. B's Bets page should show the round.
2. B: pick an amount, click **Bet** on a side. B's row should say *owes*; A's list shows B under "owes" with **Collect**.
3. B: **Pay host** (trade, both click Trade). B's bet should flip to *paid* and the pool should grow on both screens.
4. A: **Lock bets** on every round (Shift-click locks them all). B's window should switch to a **Payments** list showing what B owes across all rounds; B pays once, A sees B flip to paid. A presses **Start games** (unpaid bets are dropped), then **Winner** on a side. Winners' credit shows as *held*; the other side shows *lost*. A bet on a round nobody bet against should be refunded.
   B: after A presses **Winner**, B's chat should say "Your bet on ... won" if B backed the winner, and `/bf history` should show a *Side bets* line (settled, won, lost, gold) with the round listed. A round should never count twice (try `/reload` and rejoin the table). A's own bets, and a refunded round, should not appear.
5. Try two rounds at once and more than one bet from the same player.
6. A: move the **Host cut** slider (2, 5, 10, 20%) before any bets, then check it locks once B's bet is paid. Try **Remove round** on a round with no paid bets (later rounds renumber), and **Call off** on one with a paid bet (it refunds and stays listed). Use **New round** and the game dropdown to open another; the game mode (Duel, Deathroll, ...) should show at the top of B's window. With six rounds on the card **New round** greys out; once all six are finished (won or called off), New round starts a fresh card.

## 8. The Odd Man Out
1. A: pick **The Odd Man Out** in the Game button before starting. B joins. (Practice players can fill more seats.)
2. A: **Start**. Both players get a row of number buttons: pick one within 15 seconds (or a random one is picked for you).
3. **Roll** shows greyed out while anyone is still picking (it says *Others picking...* once you've picked) and lights up with the last pick. Everyone clicks **Roll** at once (it greys out at the first click and says *Rolled* once the host has read it; you get one roll per round). **Key check:** does A's window register B's roll? If B always folds after 8 seconds, A can't see B's `/roll` lines, and this game (and Deathroll) can't work between players yet.
4. Play to a winner. Watch for the die shrinking when six players drop to five (everyone picks again), near misses after a quiet round, and stakes going to the winner.

## 9. Tidy up
A closes the table. B should see "put out their fire" and the pin should disappear within ~90 s.

## What to send back
For anything that failed: which step, what you expected, what happened, and a screenshot of the chat and any Lua error.
