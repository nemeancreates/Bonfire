# Two-player test plan

You need two players on the WoW: Forever beta, **same faction**, **same layer** (standing next to each other usually does it), both with Bonfire installed. Call them **A** (host) and **B**.

Before starting, both: `/console scriptErrors 1`, then `/reload`. Run `/bf api` (should say all present) and `/bf status` (`channel ... joined`, `me: ... learned from the channel`). Screenshot any red Lua error.

Write results in the tables in [BETA-NOTES.md](BETA-NOTES.md), or just tell Claude.

## 0. Do you hear each other?
Both: `/bf ping`. Six seconds later each of you should see the other listed as having answered, and `/bf status` should show "Bonfire user heard". If not, compare the `comms:` line on both sides (sent / own echoes / from others) and tell Claude what each says. No table needs to be hosted for this.

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
1. A clicks **Stoke**, then **Roll** repeatedly. B clicks **Bank** at some point. Both windows should agree on pots and round.
2. Let a 1 come up (fire out, pots wiped) and finish all 5 rounds. Check the winner shows on both sides, and `/bf stats` counts the game.

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
1. A: `/bf bets add Oppa Gopher` (a round with two sides, 2 minutes to bet). B: open `/bf`, click the **Bets** button top right of the window.
2. B: pick an amount, click **Bet** on a side. B's row should say *owes*; A's list shows B under "owes" with **Collect**.
3. B: **Pay host** (trade, both click Trade). B's bet should flip to *paid* and the pool should grow on both screens.
4. A: **Lock bets** on every round (Shift-click locks them all). B's window should switch to a **Payments** list showing what B owes across all rounds; B pays once, A sees B flip to paid. A presses **Start games** (unpaid bets are dropped), then **Winner** on a side. Winners' credit shows as *held*; the other side shows *lost*. A bet on a round nobody bet against should be refunded.
5. Try two rounds at once and more than one bet from the same player.
6. A: move the **Host cut** slider (2, 5, 10, 20%) before any bets, then check it locks once B's bet is paid. Try **Remove round** on a round with no paid bets (later rounds renumber), and **Call off** on one with a paid bet (it refunds and stays listed). Use **New round** and the game dropdown to open another; the game mode (Duel, Deathroll, ...) should show at the top of B's window.

## 8. Tidy up
A closes the table. B should see "put out their fire" and the pin should disappear within ~90 s.

## What to send back
For anything that failed: which step, what you expected, what happened, and a screenshot of the chat and any Lua error.
