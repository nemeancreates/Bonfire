# Bonfire

Find campfires on your minimap and play quick dice games with whoever's sitting at them. For WoW: Forever.

Until the game gets a smoke trail for campfires, Bonfire is the signal: hosts broadcast their fire, and everyone else running the addon sees it pinned on the minimap and world map.

## Installing

Use a packaged `Bonfire-x.y.z.zip`, not GitHub's green **Code > Download ZIP**: that one is the source, without the `Libs` folder, in a folder called `Bonfire-main` that WoW won't load. Unzip the packaged zip into `World of Warcraft\_classic_beta_\Interface\AddOns\` so you end up with `AddOns\Bonfire\Bonfire.toc`, then restart the game (a `/reload` isn't enough for a new addon). Players at the same table need the same version; the login line says which one you have.

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

**Games:** the **Game** button on the main menu (and at your own open table) picks what your table plays. Embers and The Odd Man Out are playable; Deathroll, Critter Race and Duel are greyed out until they're wired in.

**The Odd Man Out:** two to ten players each secretly pick a number, then everyone rolls at once (the die is d20 with six or more players left, d10 with five or fewer, and everyone picks again when it shrinks). If anyone else rolls your number, you're out. After a round where nobody's out, a roll near your number counts too. Miss a pick and you get a random one; miss a roll and you fold. Last one standing wins the pot. Try it alone with `/bf dummy 5` and Start.

**Side bets:** a host can run a card of rounds (fights, races) and everyone else bets on a side from the **Bets** tab, one bet per round (cancel an unpaid one to change it). Your bets across every round are listed together under the sides, with how much you've staked in total. Amounts are dialled up to 100 gold or 99 silver or copper; add more than one coin type for bigger bets. Winners split the pool in proportion to their bets, minus an optional host cut, and a round nobody bet against refunds every stake. Bets are paid to the host like stakes: from credit already held, or by trade (the host's list shows who still owes). Side bets are gold, so the Bets tab is greyed out (and bets refused) on a For fun table: switch to Gambling and confirm a bet first. Try it alone with `/bf bets demo` (it opens a practice table for you and gives it a pretend stake), which seats six practice players and a card of three fights. When every round is locked (each round's timer, the **Lock bets** button, or Shift-click to lock them all), a **payment window** lists what everyone owes the host across all rounds, with a Collect button per person for the host and Pay host for each player. Payments are picked up automatically as the trades complete. The host presses **Start games** on the same page; anyone who hasn't paid has their bets dropped. Winners can only be declared once the games have started.

The host picks the cut (2, 5, 10 or 20 percent) on a slider, locked once bets are in, and opens rounds with **New round** on the Bets tab (every table has Table and Bets tabs in the title bar; Bets is greyed on a For fun table), naming the game (Duel, Deathroll, Critter Race, Dice or Custom) and the sides, one per box with the *vs* already between them (for three or more, type `Gopher vs Toad` in the second box). The game is shown at the top of the betting window. A card holds six rounds; once all six are settled, the next round starts a fresh card. `/bf bets add <A> <B>` also adds a round and `/bf bets close` ends betting.

**Chat:** Bonfire keeps its messages in their own **Bonfire** chat tab, which flashes when something new lands in it, and each table gets a chat channel that everyone at the fire joins when they sit down and leaves when the table ends (the tab tells you the channel number: type `/<number> hello`). `/bf chat` switches both off.

The table window explains the money in words: the host sees how much player credit they're holding and what players still owe, each player sees what the host is holding for them, and every row shows credit, wins, losses and net. A host can't close a table while players are owed money; if a host walks away anyway, what they owe is remembered (`/bf debts`) and shown at login.

**Quips:** random lines and emotes make the table livelier, and `/bf chat` switches them off along with the chat tab. Nothing is on a timer. Your character says a line in `/say` and does an emote, but only on one of your clicks in Bonfire (Start, Roll, Bank, Pick, Cash out, Pay, Join), because that's when the game lets an addon speak for you. A moment that comes up between clicks (a game ending, a streak of 3, a high or low roll or a rolled 1 in Embers) waits briefly for your next click: 8 seconds for a roll, 30 for a game's result, then it's dropped. A roll reaction is never said on a Roll click, so it can't sound like it's about the new roll. The full list of lines and when each is said is in [docs/QUIP-LINES.md](docs/QUIP-LINES.md). Cheer, clap and laugh for wins, sigh, shrug, laugh and facepalm for losses, flex for a win streak, cry for a losing one, and a bow when you cash out. Any click has a small chance of a line of its own. Practice players talk in the Bonfire tab when a game starts or ends. `/bf quip <kind>` tries one.

**Nearby fires:** when you come within about 60 yards of a fire that another Bonfire user lit or is hosting, you get a message: "Ratty's fire is nearby." The `/bf` list shows every fire around you, nearest first, and clicking a pin opens it.

**Rematch:** after a game the host's button becomes **Rematch**, held for 5 seconds so players can cash out first.

**Honest Broker:** hosts get a reputation. When you leave or cash out after playing at someone's table, the window asks two one-click questions, both optional: *Paid out fair?* and *Pace* (quick, OK, slow). Your addon also watches for the payout: gold the host still held for you that hasn't reached you after 10 minutes goes on record as unpaid (and comes off once it's paid; `/bf rep paid <name>` if they paid you outside Bonfire). Word travels when Bonfire users pass each other or share a table, so a host's name gets known across the realm. Each fire shows a badge (New until three players have rated it, then Trusted, Mixed or Avoid, with the pace), in the list, on the map pin and in the table header. Badges are advice; Join always works. `/bf rep <name>` for details, `/bf rep` for what players say about you (also on your History page). Design: [docs/HONEST-BROKER.md](docs/HONEST-BROKER.md).

**History:** the **History** button on the main page (or `/bf history`) shows your record in a few plain lines: games played, wins and losses, the gold you won and lost, your current streak and best runs, and your last five results. Side bets have their own line (settled, won, lost, gold) and your last three, so a night spent only betting shows up too, plus anything you still owe from a table you left. The main menu shows a one-line version. It's kept per character.

Commands (`/bf help` or `/bfhelp` lists them in game): `/bf host` (no campfire needed), `/bf chat`, `/bf burn <seconds>` (testing), `/bf ping` (find other Bonfire users), `/bf leave`, `/bf adjust`, `/bf rep`, `/bf stats`, `/bf pins`, `/bf reset`, `/bf status`, plus beta checks (`/bf api`, `/bf find`, `/bf auras`, `/bf watch`).

## Development (Windows)

Prereqs: git, LuaJIT (`winget install DEVCOM.LuaJIT`), VS Code with `ketho.wow-api`.

```
scripts\setup.ps1   # libraries -> Libs\, luacheck -> .tools\, junction into the Forever beta AddOns folder
scripts\lint.ps1
scripts\test.ps1
```

Edit, then `/reload` in game. If Windows blocks the scripts, run them from the VS Code tasks or with `pwsh -ExecutionPolicy Bypass -File scripts\test.ps1`.

## License

All rights reserved, see [LICENSE](LICENSE). Bonfire is free to download and use, and you can change it for your own use, but please don't re-upload or redistribute it, or use its code elsewhere, without asking. The libraries in `Libs/` are fetched by `scripts/setup.ps1` and keep their own licenses.
