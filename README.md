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

Commands: `/bf host` (no campfire needed), `/bf leave`, `/bf adjust`, `/bf stats`, `/bf pins`, `/bf reset`, `/bf status`, plus beta checks (`/bf api`, `/bf find`, `/bf auras`, `/bf watch`, `/bf sound`, `/bf music`).

## Development (Windows)

Prereqs: git, LuaJIT (`winget install DEVCOM.LuaJIT`), VS Code with `ketho.wow-api`.

```
scripts\setup.ps1   # libraries -> Libs\, luacheck -> .tools\, junction into the Forever beta AddOns folder
scripts\lint.ps1
scripts\test.ps1
```

Edit, then `/reload` in game. If Windows blocks the scripts, run them from the VS Code tasks or with `pwsh -ExecutionPolicy Bypass -File scripts	est.ps1`.
