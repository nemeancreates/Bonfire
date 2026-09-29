# Beta checks

Open questions from the concept brief, and how to answer each one in the Forever beta. Fill in results as we get them.

| Question | How to check | Result |
|---|---|---|
| Name and spell ID of the campfire proximity aura (auto-detect "at a fire") | Walk up to a campfire with `/bf watch` on, or stand at one and run `/bf auras` | Expected: Welcoming Campfire, 1229739 (from DynamicCam's Forever situation). It only applies after resting ~1 min at the fire. Unverified in our client. |
| Exact name of the Basic Campfire Kit item, and does a secure `item` button using "bag slot" place it? | Craft a kit (Cooking 1 + Simple Wood), run `/bf status` (it lists the kit it found), then click **Light a fire** | Bag scan matches any item with "campfire" in its name. |
| Does the placement cast fire `UNIT_SPELLCAST_SUCCEEDED` so the table opens by itself? | Same click; the chat should say "Campfire lit (spell name)" | |
| Names: comms carry the full name ("Firstname Surname-Realm") while `UnitName` gives "Firstname". Bonfire learns its own name from its channel echo and matches other names on the first word. | `/bf status` should say `me: ... (learned from the channel)`. Then two players: join, pay, roll | Needs a second player to confirm. |
| Can a whisper (addon message) be sent to a name containing a space ("Firstname Surname-Realm")? Joining, banking and cash-out all depend on it | Second player clicks **Join** and the host sees them seated | |
| Does a Basic Campfire last 15 minutes? Bonfire closes the table after `FIRE_LIFETIME` (900 s in `Table.lua`) from when the host lit it or hosted at it | Light a fire and time it | Unconfirmed; adjust the constant. |
| Are all game APIs Bonfire calls present in this client? (`GetCoinTextureString` and `SetTradeMoney` weren't) | `/bf api` lists any that are missing; `/bf find <text>` searches names | `SetTradeMoney` is missing: the fill-in now falls back to `MoneyInputFrame_SetCopper(TradePlayerInputMoneyFrame, ...)`. Unverified. |
| Does the gold fill-in work in the trade window (fallback path)? | Pay in on a gold table; chat says "Filled in" only if the trade box really shows the amount | |
| Host hand-off: does the first-joined player get the table when the host walks off, and do all players follow? | Two players at a for-fun table; host walks 35+ yd away and waits ~12 s | Needs 3 clients to check that a third player follows. |
| Do side bets pay in and settle correctly between two real players? (whisper a bet, trade the gold, lock, declare a winner, credit held) | See TEST-PLAN step 7. `/bf bets demo` tries the window alone with practice players | Engine has offline tests; the window and the trades have not been run in game. |
| Do duels exist for addons? (`StartDuel`, `DUEL_*` messages) | `/bf api` lists them if missing; see Duels in CONCEPT.md | |
| Does the Expert (Cooking 200) campfire use a different aura? | Same as above, at an Expert fire | |
| Can addons join the `BonfireCamp` channel and send addon messages on it outdoors? | `/bf status` on two clients, host on one and check the other sees the fire | |
| Are ungrouped players' `/roll` results visible to nearby players? (The table trusts the host's roll, which players see in chat) | Host rolls with **Stoke!**; players check their chat shows it | |
| Do grouped players still see rolls from ungrouped table members? | Same, with some of the table in a party | |
| Does `RandomRoll` work from an addon button? Could it run on a timer (no click)? | **Roll** works = button OK. Timer is untested (it may need a hardware event) | |
| Can an addon open a trade by name (`InitiateTrade`) without targeting first? | Host clicks **Trade next** with the player untargeted, then targeted | |
| Does `SetTradeMoney` fill in the gold? | Open a trade on a gold table; the payer's window should show the stake | |
| Does "Trade complete" (`UI_INFO_MESSAGE` / `ERR_TRADE_COMPLETE`) fire reliably so the ledger updates? | Pay in; host's row should flip to *ready* | |
| Is 35 yd the right fold range for a campfire hangout? | Walk away from a fire with `/bf status` | |
| `PlaySoundFile` / `PlayMusic` allowed? | `/bf sound`, `/bf sound <fileID>`, `/bf music <fileID>` | |
| HereBeDragons map data correct for Forever zones (pin lands on the fire) | Host a table; a second client checks the pin location | |
| Is the realm name in roll lines identical to `GetNormalizedRealmName()`? | Roll with a player from a connected realm | |

## Known MVP gaps

- No combat handling yet (brief: auto-pause, then forfeit after a timeout).
- Hosting doesn't require being at a campfire until the aura is confirmed.
- Trust: players trust the host with the pot (the brief's "Banked" mode). No trust history yet.
- No bet cap beyond 1000 of a coin (1000g max stake).
- Table state goes out on the realm-wide channel; fine for the beta, may need per-zone channels at launch scale.
