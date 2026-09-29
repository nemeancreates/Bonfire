# Bonfire

Find campfires on your minimap and play quick dice games with whoever's sitting at them. For WoW: Forever.

Until the game gets a smoke trail for campfires, Bonfire is the signal: hosts broadcast their fire, and everyone else running the addon sees it pinned on the minimap and world map.

## Playing

- `/bf` opens the window: nearby fires, or your table. A gold coin next to a fire's seats means it's played for gold; no coin means **For fun**.
- Pick **For fun** or **Gambling**. To build a bet, pick an amount (steps of 5, Shift-click for 10) and a coin type (gold, silver or copper), click **Add**, and repeat with other coins to mix them. Then **Confirm bet**. A gold table can't open until a bet is confirmed.
- Then **Light a fire** at a campfire (or **Host at this fire** if you're already at one).
- Players join from within 35 yd of the fire. A bar at the top of the screen shows your distance from the fire and turns orange, then red with a warning, before you fold past 35 yd. If the host walks away and the fire is still burning, the player who joined first becomes host, as long as the host isn't holding anyone's gold. Otherwise the table closes. The bar can be dragged anywhere.
- A fire burns for about 15 minutes. The time left counts down live at the top right of the window and on the distance bar. When it's out, the game in progress finishes as the last one, then the table closes (after paying everyone back on a gold table).
- The window opens at the left of the screen and remembers where you drag it. `/bf reset` puts it back.
- The host clicks **Stoke** to start, then **Roll** each turn (a real `/roll` everyone sees).

**Embers:** every roll of 1–6 adds to the pot of everyone still stoking. A 1 blows the fire out and every unbanked pot is lost. **Bank** to keep your pot and sit out the rest of the round. After 5 rounds the highest total wins.

### Gold tables

The host holds the pot. Before a round, each player trades their stake to the host; players who haven't paid just sit that round out. The host's **Trade next** button works through the queue (payouts first, then collections), and Bonfire fills in the gold. Both players still click Trade, since Blizzard doesn't let addons accept trades. Completed trades update the ledger automatically.

Winnings stay with the host as credit for the next round. **Cash out**, walking away, or the host closing up puts you in the payout queue. The host's ledger survives a `/reload` or relog (up to an hour); a game in progress is voided and stakes go back to balances. If a trade happens outside the addon, the host can fix it with `/bf adjust <name> <amount>`.

Placing a campfire opens the window on its own. Two-player testing: see [docs/TEST-PLAN.md](docs/TEST-PLAN.md).

**Practice alone:** host a table, then `/bf dummy 4` seats four pretend players (up to 9). They play Embers by themselves, "trade" instantly when you click Collect or Pay, and sometimes cash out. `/bf dummy clear` sends them home.

**Side bets:** a host can run a card of rounds (fights, races) and everyone else bets on a side from the **Bets** tab, one bet per round (cancel an unpaid one to change it). Amounts are dialled up to 100 gold or 99 silver or copper; add more than one coin type for bigger bets. Winners split the pool in proportion to their bets, minus an optional host cut, and a round nobody bet against refunds every stake. Bets are paid to the host like stakes: from credit already held, or by trade (the host's list shows who still owes). Side bets are gold, so the Bets tab is greyed out (and bets refused) on a For fun table: switch to Gambling and confirm a bet first. Try it alone with `/bf bets demo` (it opens a practice table for you and gives it a pretend stake), which seats six practice players and a card of three fights. When every round is locked (each round's timer, the **Lock bets** button, or Shift-click to lock them all), a **payment window** lists what everyone owes the host across all rounds, with a Collect button per person for the host and Pay host for each player. Payments are picked up automatically as the trades complete. The host presses **Start games** on the same page; anyone who hasn't paid has their bets dropped. Winners can only be declared once the games have started.

The host picks the cut (2, 5, 10 or 20 percent) on a slider, locked once bets are in, and opens more rounds with **New round**, naming the sides and the game (Duel, Deathroll, Critter Race, Dice or Custom). The game is shown at the top of the betting window. `/bf bets add <A> <B>` also adds a round and `/bf bets close` ends betting.

**Chat:** Bonfire keeps its messages in their own **Bonfire** chat tab, which flashes when something new lands in it, and each table gets a chat channel that everyone at the fire joins when they sit down and leaves when the table ends (the tab tells you the channel number: type `/<number> hello`). `/bf chat` switches both off.

Commands (`/bf help` or `/bfhelp` lists them in game): `/bf host` (no campfire needed), `/bf chat`, `/bf burn <seconds>` (testing), `/bf ping` (find other Bonfire users), `/bf leave`, `/bf adjust`, `/bf stats`, `/bf pins`, `/bf reset`, `/bf status`, plus beta checks (`/bf api`, `/bf find`, `/bf auras`, `/bf watch`, `/bf sound`, `/bf music`).

## Development (Windows)

Prereqs: git, LuaJIT (`winget install DEVCOM.LuaJIT`), VS Code with `ketho.wow-api`.

```
scripts\setup.ps1   # libraries -> Libs\, luacheck -> .tools\, junction into the Forever beta AddOns folder
scripts\lint.ps1
scripts\test.ps1
```

Edit, then `/reload` in game. If Windows blocks the scripts, run them from the VS Code tasks or with `pwsh -ExecutionPolicy Bypass -File scripts	est.ps1`.

## License

All rights reserved, see [LICENSE](LICENSE). Bonfire is free to download and use, and you can change it for your own use, but please don't re-upload or redistribute it, or use its code elsewhere, without asking. The libraries in `Libs/` are fetched by `scripts/setup.ps1` and keep their own licenses.
