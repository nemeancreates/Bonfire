# Honest Broker (design, not built)

A shared reputation ledger for table hosts. Every Bonfire client keeps a growing record of which hosts pay out and which don't, built from things the addon saw happen, and swaps those records with other users even if they've never shared a table.

## Who needs rating

Gold tables are pre-paid: players trade their stake to the host before a round. So the risk sits with players trusting a host, not the other way round. **Hosts are what get rated.** (Players who never pay just aren't dealt in.)

## What counts as evidence

Nothing is typed in by hand. Records come from what a client observed:

- **Player side, the main source.** The host's table state tells every seated player what the host says it holds for them. When a table closes, the host leaves, or you cash out, your client watches for a completed trade with that host that pays you. Result: `paid` (amount received) or `unpaid` (amount still owed after a grace period, say 10 minutes).
- **Host side.** The host's own ledger and payout trades are kept as their own history, shown as their record but weighted low, since it's self-reported.

Only the counterparty's account of a host counts for much.

## What's stored per host

`name-realm` -> `paid` copper, `unpaid` copper, `tables`, distinct `attesters`, first and last seen.

Score = paid / (paid + unpaid), shown with how much evidence is behind it (attesters and volume):

| Badge | When |
|---|---|
| New | fewer than 3 distinct players have vouched either way |
| Trusted | enough evidence, nearly all paid out |
| Mixed | some unpaid |
| Avoid | several distinct players report unpaid winnings |

Badges are advice. They show on each fire in the list, the map tooltip and the join button, and never block joining.

## How records spread

- On login and every few minutes a client shares a small digest: the hosts it has first-hand evidence about.
- When you see a fire from a host you know nothing about, your client asks nearby users "anyone heard of this host?" and merges the answers.
- Merged records are keyed by (host, attester, table id), so the same event heard from five people is still one event. Second-hand records count for less and expire if nobody refreshes them.

## Abuse and gaps

| Risk | Mitigation |
|---|---|
| Slandering a host | one report per table id, needs several distinct attesters to reach Avoid, and reporters build their own standing over time |
| Hosts boosting themselves with alts | tiny trades are ignored, weight scales with volume and with how long an attester has been seen, self-reports count little |
| False "unpaid" because the addon missed a trade | grace period, and the player can confirm they were paid with a command, which cancels that report |
| Name changes and transfers | records key on name-realm, so a rename starts fresh |
| Data growth | store the most recent few hundred hosts, expire old evidence |
| Privacy | only host names and totals are shared, never who lost how much |

## What this can't do

It can't stop a host running off with a pot. It makes doing that cost them every future table, and gives players a way to check before they trade.

## Open questions

- Should Avoid warn before joining, with a "join anyway" confirm, or stay advisory?
- Can a host see who reported them, to dispute a mistake?
- Should good hosts get anything visible, like a "trusted host" mark on their pin?
- How many distinct reports should it take to reach Avoid?
