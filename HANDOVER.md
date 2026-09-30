# Bonfire handover

For starting a fresh session. Read this, then `CLAUDE.md`, then the docs it points to.

## What it is

A WoW: Forever beta addon (Interface 16001, Lua 5.1) in `C:\Dev\Bonfire`. Public repo: https://github.com/nemeancreates/Bonfire (All Rights Reserved). The player is Nemean, who tests in game and reports by screenshot. Current version **0.6.1** (`dist\Bonfire-0.6.1.zip`).

**Purpose (the user's words):** the campfire buff system is for player engagement; the addon makes the journey a more engaging, fast moment for everyone. So: public by default, few clicks, quick games, groups forming naturally. Classic feel, no fancy graphs.

## State of play

Everything below is built. It has passed lint, 88 offline rules tests, and a 470-game table simulation. Only some of it has been seen in game (see "Confirmed in game").

- Campfire finding: fires (placed or hosted) announce themselves on a hidden channel and SAY; others get minimap/world pins, a "Ratty's fire is nearby" message within 60 yd, and a list in `/bf`.
- Tables: host-run, up to 10 seats, prepaid gold escrow (stake traded to the host, winnings held as credit, cash out to be paid), or For fun. Range bar (fold past 35 yd, host loses table after 12 s or hands it to the first joiner), 15-minute fire timer that follows the real campfire buff, rematch after 5 s.
- Games: **Embers** (mine), **The Odd Man Out** (the user's own, fully playable with practice players), Deathroll rules written and tested but NOT wired to the table. Critter Race and Duel not built. The Game picker in `/bf` lists them, unready ones greyed.
- Side bets: rounds with two or more sides, pool payouts, host cut slider (2/5/10/20%), one bet per player per round, payment window before games start, winners declared by the host.
- Practice players: `/bf dummy N`, `/bf bets demo`.
- Quips: `/say` plus emotes only on the user's own clicks, nothing on timers, practice players speak as text. `/bf chat` toggles the Bonfire chat tab, table chat and quips.
- History: `/bf history`, per character. Debts a host leaves behind: `/bf debts`.

## Standing decisions (don't re-litigate)

- Prepaid escrow, no running tab. No "put it out" while players are owed. A host walking away leaves remembered debts.
- Side bets are parimutuel; bets need a Gambling table (Bets tab greyed on For fun).
- Amounts dial to 100 gold or 99 silver/copper; bigger bets by adding coin types.
- Deathroll all-out: even count drops highest and lowest, odd drops highest, ties re-roll; final roll-off starts at 1-10 with the higher last-round roller first; classic 1v1 starts at 1-100. Pace unchanged until multi-player testing.
- Odd Man Out: d20 with 6+ players, d10 with 5 or fewer, everyone re-picks when the die shrinks, near-miss reach widens after quiet rounds (caps at 2 on d10, 4 on d20), a wipeout backs the reach off one step and replays.
- Game action timers stay (Embers gap 4 s, Bank lock 3 s, Odd Man Out pick 15 s / roll 10 s) so slow PCs can click. Quips have no timers.
- Sound/music: hidden commands only (`/bf sound`, `/bf music`), never advertised; planned for later.
- No hot-fire marker. No privacy switch for fires.
- Do not push to GitHub unless asked. Commits use the noreply address; end commit messages with the Co-Authored-By line the session gives.

## Confirmed in game

Bonfire chat tab, range bar (drag, disappears when away), fire countdown, `/bf help`, hosting at another player's fire, the Odd Man Out with practice players, Embers, gold pay-in/out with practice players, the payment window and bets demo, campfire timeout payout.

## NOT yet tested (needs a second real player)

- Do two players hear each other? (`/bf ping`, `/bf status`; the channel and the SAY fallback.)
- Whispers to two-word names, joining, trades: does the host's `InitiateTrade` by name work, does the gold fill-in fallback work (`SetTradeMoney` is missing in this client), does "Trade complete" mark players paid.
- **Roll visibility:** can the host see another player's own `/roll`? Odd Man Out and Deathroll depend on it. If not, real players fold every round.
- Host hand-off, side bets between real players, the quips' `/say` and emotes from addon clicks (`/bf quip start` tests one), campfire-only pins on other players' maps, whether the "Campfire nearby" buff exists (matching is by name containing "campfire" plus ID 1229739), whether the placement-vs-crafting kit count works.
- `docs/TEST-PLAN.md` is the two-player script.

## Open items / next candidates

1. Second-player test (highest value).
2. Wire Deathroll into the picker (rules in `Games\Deathroll.lua`, tested). Needs roll visibility.
3. Build Critter Race: six critters, one per d6 face, first to 3-4 steps, pool payouts, team favorites shared between users, shown as 3D model frames. HUD mockup was agreed in principle.
4. Race/class quip lines: proposals are in `docs/QUIP-LINES.md`, awaiting the user's edits. `/bf whoami` prints race/class tokens (needed to match the Forever roster).
5. Honest Broker reputation ledger: designed in `docs/HONEST-BROKER.md`, not built. Debts (`/bf debts`) are its first piece.
6. ~~Side-bet results in `/bf history`~~ done in 0.6.1 (`Table:CountBets`, `History.AddBet`; every player works out their own result from the market the host sends, host's free bets and refunded rounds don't count). Untested with a real second player: needs a spectator to bet, the host to press Winner, then `/bf history` on the spectator.
7. Duels (design in `docs/CONCEPT.md`) need the native duel API confirmed.
8. The user may want an explicit "Play again" button instead of the default-continue rematch.
9. Not on GitHub: everything since the last push (commit `6c4aaf3`, version 0.3.5) is uncommitted in the working tree. Ask before committing and pushing.

## Working here

- Tools: use the **PowerShell tool** for `scripts\*.ps1` (the bash tool's PowerShell gets execution-policy errors unless `-ExecutionPolicy Bypass`). LuaJIT, luacheck, VS Code WoW API extension are installed; `scripts\setup.ps1` recreates `Libs\` and the AddOns junction (`...\_classic_beta_\Interface\AddOns\Bonfire` links to the repo, so the game runs the repo directly).
- Before reporting any change: `scripts\lint.ps1` (0 warnings), `scripts\test.ps1`, `scripts\tablesim.ps1` (plays real Table.lua against a fake clock), then `scripts\package.ps1` for the zip. `scripts\sim.ps1` simulates Odd Man Out. Bump `## Version` in `Bonfire.toc` each round.
- New `.lua` files need a full WoW restart; edits to existing files only need `/reload`. Add new files to `Bonfire.toc` (and the tests/harness load lists if pure).
- Files are LF with tabs. Pure logic (no WoW API) lives in `Money`, `Roll`, `Ledger`, `History`, `Bets`, `Games\*`, `Quips` (mostly) so tests can load it; keep it that way.
- The game has no `GetCoinTextureString` or `SetTradeMoney`; `/bf api` lists what's missing, `/bf find <text>` searches names. Add new game API calls to `/bf api` in `Debug.lua`.
- Names: comms carry "Firstname Surname-Realm" while `UnitName` returns the first name only. Use `ns.Me()` (learned from the channel echo) and `ns.NameKey` for comparisons.
- Multi-step edits were done with small Python scripts that assert each anchor text exists; that worked well.
- The user prefers to see lists/mockups before big builds and says "do it all" for setup and publishing. Reply in plain language with what changed, what's unverified, and 2-3 next options.

## File map

`Bonfire.toc` load order, `Core.lua` (defaults, helpers, `/bf` dispatch), `Chat.lua`, `Quips.lua`, `Comm.lua` (channel + SAY, session id, diagnostics), `Beacon.lua` (fires, pins, nearby alert), `Table.lua` (the table: hosting, ledger use, games, bets, hand-off, practice players), `Trade.lua`, `UI.lua` (main window), `BetsUI.lua` (Bets tab and payment window), `Range.lua` (distance bar), `Debug.lua` (beta commands), `Games\List.lua|Embers|OddManOut|Deathroll`, `Ledger.lua`, `Bets.lua`, `History.lua`, `Money.lua`, `Roll.lua`, `tests\run.lua|sim.lua|table_sim.lua`, `docs\` (CONCEPT, TEST-PLAN, BETA-NOTES, HONEST-BROKER, QUIP-LINES).
