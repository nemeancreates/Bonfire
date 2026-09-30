# Honest Broker

A shared reputation for table hosts, built in 0.6.6. Every Bonfire client keeps what it knows about hosts and swaps it with other Bonfire users it meets, so word about who pays out and who runs a good table spreads across the realm. Rules: `Reputation.lua` (pure, tested in `tests/run.lua`). Legwork: `Broker.lua`. Hooks: `Table.lua` (visits), `UI.lua` (the question, badges), `Beacon.lua` (pin tooltip).

## Who gets rated

Hosts. Gold tables are prepaid, so the risk is players trusting the host with their stake and winnings. Players who don't pay just aren't dealt in. Practice players never rate and are never rated.

## Where the evidence comes from

- **The payout clock (automatic).** When you leave or cash out while the host holds credit for you (or the host starts closing up), your addon notes how much. A trade from that host paying you counts as paid out. Anything still owed after 10 minutes goes on record as unpaid, and comes off again once it's paid. `/bf rep paid <name>` clears it if you were paid outside Bonfire.
- **Your word (one click each, optional).** When a visit ends (you leave or walk off, the table closes, the host drops you or goes quiet), or when you cash out, and you played at least one game there, the window asks: *Paid out fair?* Yes / No, and *Pace* Quick / OK / Slow. Once per visit, skippable. If the window is closed it waits a quarter of an hour, and chat says to open `/bf`, rather than popping up.

Each player has one record per host: their latest word replaces their earlier one.

## Badges

| Badge | When |
|---|---|
| New | fewer than 3 different players have rated the host (shows "New, 1 unpaid" if any were bad) |
| Trusted | 3 or more, and no more than a quarter bad |
| Mixed | more than a quarter of raters report unpaid or unfair |
| Avoid | 3 or more bad reports, at least as many as good ones ("Avoid: 3 unpaid" / "Avoid: 3 say unfair") |

Pace (quick, steady, slow) shows once 3 players have voted on it. Badges show on each fire in the list, the map pin tooltip and the header of a table you've joined. They're advice only: Join always works. `/bf rep <name>` gives the details; `/bf rep` shows what players say about you, which is also on your History page.

## How word spreads

Every minute each client says a quiet hello to anyone within /say range. When two Bonfire users meet (passing each other, or sitting at the same table), they whisper each other a digest: up to 12 records, their own first, each name sent once. The same pair trades again after half an hour at most, and a client sends one digest every 20 seconds at most, so a crowd can't flood the game's send limit. There's no realm-wide broadcast: the realm channel already drops pieces of messages under load.

Merging: a player's own record (heard from them) always beats a copy passed along by someone else; otherwise the newest wins. Nobody can send a record in your name to you, hosts can't rate themselves, and records stamped in the future or older than 30 days are ignored. The store keeps at most 1500 records, forgetting the oldest passed-along ones first.

## What it can't do

Any client could be edited to send made-up records; there's no way to sign them in an addon. It can't stop a host running off with a pot. It makes doing that cost them at every future fire, and lets players check before they trade.

## Open questions

- Should a host be able to see who reported them, to sort out a mistake?
- Should good hosts get something visible on their map pin?
