# Adversarial assessment, 2026-11-22

The owner asked for an adversarial assessment of the whole game from
gameplay, security, UI and design standpoints, then fixes for whatever
needs no ruling. Four reviews ran side by side (read-only, with probes
under `/tmp`); this is their findings merged, checked and triaged.

Each finding is marked:

- **FIXED** — done tonight (committed locally; see the commit list at
  the end).
- **TO FIX** — needs no ruling; being worked through after this report.
- **RULING** — the fix changes intended design, or picks between your
  rulings. These are the questions at the end.

Severities are the reviewers', adjusted where I checked them.

---

## 1. Gameplay rules (bugs and exploits)

### Critical

| # | Finding | Status |
|---|---|---|
| G1 | **Free starter ship is a money loop.** A ship a station gave you could be repackaged and sold, then a cheap ship lost to get another (+280–350k a cycle), or repackaged and reassembled to lose the "given" mark and its insurance cap. | FIXED: a given ship cannot be packaged. (Which ship is given back is a RULING: Q1.) |
| G2 | **Scarce goods sell for ~4× base at every station, and stations never restock.** Tech 2 originals, LP-store goods, rare lots: each station is a fresh 3.9× buyer. A tech 2 original of a battleship sells for ~298B. | RULING (Q4) |
| G3 | **`Core.Step` crashed when two ships died in the same tick** (a tower core and a raider: the raider was removed while the kill list still held it). | FIXED |

### High

| # | Finding | Status |
|---|---|---|
| G4 | LP store blueprints resell for hundreds of times their LP price (a cruiser blueprint: 1,800 LP + 3.6M, sells for 1.38B). | RULING (Q4) |
| G5 | Home is never moved when its station goes (own citadel unanchored or lost, a faction citadel fallen). The pilot then wakes "docked" in a hulk or nothing, where the market works on a station that isn't there, and cannot set a new home. Stacks left in a fallen faction citadel are stranded. | TO FIX (home reset, unanchor guard, no services where there is no station); what a fallen faction citadel's hangar does is RULING (Q8) |
| G6 | A citadel hulk rebuilt at half materials and then unanchored gives a whole packaged citadel (~34M in, 307M bid). | RULING (Q9) |
| G7 | A war job could be taken again at once, and each kill counted for every copy. | FIXED |
| G8 | Expelling a member (or a fleet member quitting) sends their ship and its cargo home instantly, from anywhere, scrambled or not. | RULING (Q10): the code says sending it home is meant |
| G9 | A pirate's Trident drone paid a 1.2M bounty and standing. | FIXED |
| G10 | Coming out of wormhole space into a charted system seen for the first time erased its faction citadels (the far end took a citadel's id). | FIXED |

### Medium

| # | Finding | Status |
|---|---|---|
| G11 | Courier jobs could be finished with crates bought at the destination (297 cr for a 225k job), and two jobs either way between two stations finished each other. | FIXED: job cargo is not for sale, and crates handed out for other jobs there don't count |
| G12 | Tethered at a citadel, a drone boat keeps its tether (unlockable) while its drones fight. | RULING (Q11) |
| G13 | Unanchoring is instant and ignores sieges, seals and damage: a sealed tower can be packed up and saved before the raiders return. | RULING (Q12) |
| G14 | A buy order and a sell order at one station take the spread risk-free with maxed skills (+~1% of turnover). | RULING (Q4) |
| G15 | Supply jobs can be filled straight from the same station's market. | RULING (Q4) |
| G16 | Members judged the tax once a day: raise it after their check and drop it before the next, and they paid ~49% while bearing 10%. | FIXED: a member who won't bear a new tax leaves when it is set |
| G17 | One of your own characters in the fleet flew with every skill at V (the ship's stats used the hired-pilot table). | FIXED |
| G18 | Two sieges begun in one round shared an operation id. | FIXED |
| G19 | With no places to work, every member left at the day's end, your own characters included. | FIXED: those are thin days like any (characters stay) |
| G20 | A jump portal worked from wormhole space, and from beyond the holder's reach once it had moved. | FIXED |

### Low

| # | Finding | Status |
|---|---|---|
| G21 | Orders and contracts at a citadel are stranded (escrow locked) when its Market Hub or the citadel goes. | TO FIX |
| G22 | Refining ore bought at the same station is a small profit at Refining 5. | RULING (Q4) |
| G23 | ReplaceKit gives the career kit again after it was sold or listed. | TO FIX |
| G24 | A Field Depot took unfitted modules and unloaded charges without limit. | FIXED |
| G25 | NaN in a Goto or a range was accepted and put the ship at NaN. | FIXED |
| G26 | Picking a deployable up resets its life. | RULING (Q13) |
| G27 | A lost member's free replacement hull is insured at full value (5 losses: 652k to the corp). | TO FIX |
| G28 | A ship that left a tower's field by docking or jumping kept its mooring for the rest of the tick. | FIXED |
| G29 | Dock and Jump orders are checked when given, never on arrival (a gate closed or a citadel shut meanwhile). | TO FIX |
| G30 | War then peace a day later lifts any standing to −4. | RULING (Q14): a comment says it is meant |
| G31 | Ops are a free, permanent +20% (see D23). | RULING (Q15) |
| G32 | Members spawn with modules they never bought, which drop as loot. | TO FIX |

Checked and sound: save/load round trip over 30,000 ticks (hashes equal),
no `math.random`/`os.*` in Core, quantity and price validation, market
escrow, contracts and jobs cancelling, ships in transit locked out.

---

## 2. Security

Threat model: an offline single-player game handed out over plain HTTP on
a home LAN. What matters: a misused NAS or a device on the LAN, a hostile
save or character file passed between players, a hostile picture imported
as a portrait.

| # | Sev | Finding | Status |
|---|---|---|---|
| S1 | High | **Releases are not signed.** The launcher takes the manifest and its hashes from the same plain-HTTP server, so whoever can write the NAS's dist folder (or intercept LAN traffic) can ship any binary, including a new launcher. Old releases can be replayed. | RULING (Q2): signing needs a key you keep |
| S2 | High | **Manifest paths can escape the install folder** (`../` or absolute): proven to write (and chmod +x) files outside it, and to delete arbitrary user files, including without sending any content. | TO FIX |
| S3 | High | **A hostile save can write files anywhere:** a skill name with a newline injects lines into the character file, an injected id with a NUL byte cuts the path at the C boundary, and deleting a character removes any file a crafted portrait names. Proven up to writing `Save Editor.bat` outside the characters folder. | TO FIX |
| S4 | Low | A 9-byte save makes the decoder allocate 1 GB (counts are trusted before any elements exist); a 54-byte one ~5 GB. | TO FIX |
| S5 | Low–Med | Pictures are decoded by a 2017 stb_image with every format on; an imported "png" can be decoded as PSD/GIF/HDR, which had heap-overflow CVEs since. | TO FIX (restrict formats) |
| S6 | Low | The launcher reads manifests and files with no size limit and follows redirects. | TO FIX |
| S7 | Low | Shipped binaries carry your home path (RUNPATH and source paths). | TO FIX if cheap; only matters if binaries leave the LAN |
| S8 | Low | Housekeeping: `.env` is group-readable; `.gitignore` covers only `/.env`; `eleven_labs_api_examples.txt` and `script/__pycache__/` aren't ignored. Git history is clean (all 558 commits checked). Commits carry your Gmail address on GitHub. | TO FIX (ignores, permissions); the commit address is yours to decide (Q3) |
| S9 | Info | Debug surfaces (`--console`, `--script`, GameDebug, the Save Editor) ship. No privilege boundary on a player's own machine, so it doesn't matter. | — |

Checked and sound: no `loadstring`; requires are literals; slot names
can't traverse; meta.txt parsing; the sound/art tools don't use a shell or
print keys; Linux and Windows binaries have PIE/RELRO/NX/stack protection
(from toolchain defaults).

---

## 3. UI

| # | Sev | Finding | Status |
|---|---|---|---|
| U1 | High | Closing a window while typing in one of its fields leaves the field focused off-screen: every hotkey is dead until you click another field. | TO FIX |
| U2 | High | F10 quick-loads instantly with no confirmation, next to the module keys. | RULING (Q16) |
| U3 | High | Quit / Main menu drop unsaved progress silently (the last save is the last docking). | RULING (Q16) |
| U4 | High | "Unplug" destroys the implant, in one click, and the label doesn't say so. | TO FIX |
| U5 | High | In a tower's field the target cards are drawn on top of the berth panel (Make home, Repair, Starbase). | TO FIX |
| U6 | High | The fleet panel grows with the fleet and runs off the top of the screen past ~30 members. | TO FIX |
| U7 | High | Price fields take 9 digits; capital hulls cost up to 40B. | TO FIX |
| U8 | High | Flying into any tower's field pops station windows open over the flying screen (and may again at the edge). | TO FIX: open them on "Enter field", not on crossing the edge; what should open is a RULING detail (Q17) |
| U9 | Med | Rigs are destroyed with one click on the fitting wheel, and Repackage destroys them silently. | TO FIX |
| U10 | Med | Order buttons on the selected panel are greyed with no reason, and their keys fail silently. | TO FIX |
| U11 | Med | Many destructive actions happen in one click (abandon job, expel, dismiss, delete fit, mutate, forget place, cancel contract, jettison all, sell all, apply saved fit). | RULING (Q18): which ones ask twice |
| U12 | Med | Refusals are shown with internal command names ("UnanchorTower: …"). | TO FIX |
| U13 | Med | Notices last 10 game ticks (0.6 s at ×16, forever paused) and there is no message log. | TO FIX (real-time); a log is RULING (Q19) |
| U14 | Med | Every station dock button is live in any tower's field whatever the tower has; Sell is live where the Core will refuse. | TO FIX |
| U15 | Med | Rack F-keys go by position in the full fitted list (passives take numbers; low-slot repairers end up keyless). | TO FIX |
| U16 | Med | Market details: reasons missing, one Quantity field drives five actions unannounced, whole-credit order prices vs fractional asks, list rounding differs from the detail. | TO FIX (reasons, rounding); price resolution is RULING (Q4) |
| U17 | Med | Scrollbars can't be dragged or clicked. | TO FIX |
| U18 | Med | Interface scale is offered by screen height only; the fitting window doesn't fit some 4:3/5:4 screens. | TO FIX |
| U19 | Med | Tower/citadel "Take down" is always live; the reason comes only after the click. | TO FIX |
| U20 | Med | Inventory "worth" is base price; the menu's "Sell" only opens the market; greyed entries without reasons. | TO FIX |
| U21 | Med | Stale wording: "hired pilots", "dock at one" (towers have fields now). | TO FIX |
| U22 | Med | A fourth row of order buttons (deployables) overflows the selected panel onto the overview. | TO FIX |
| U23 | Med | Onboarding: the guide never opens on its own; the dock is icons only. | RULING (Q20) |
| U24 | Low | Escape always opens the menu instead of closing the front thing first. | RULING (Q20) |
| U25 | Low | The same thing named differently (Bookmark / Mark here / Places; Crew / Fleet / Pilots / Members…). | RULING (Q21): you pick the words |
| U26 | Low | Units and formats vary (durations, "0.5 km" vs "500 m", TF vs tf). | TO FIX |
| U27 | Low | Some names are cut by letter count, not width; the notice has no width limit. | TO FIX |
| U28 | Low | Time can't run faster in a tower's field. | RULING (Q22, with D3) |
| U29 | Low | Vague hover reasons ("Not here", "They cannot keep it in stock from there"). | TO FIX |
| U30 | Low | Saving a fit under an existing name overwrites it silently. | TO FIX |

---

## 4. Design

These are mostly yours to decide. The reviewers' evidence is in brief;
probes and numbers are in the review notes.

| # | Impact | Finding | Status |
|---|---|---|---|
| D1 | High | **Income per hour differs 10–100× between activities.** A level 4 courier run pays ~49–78M with no risk and chains; level 4 combat jobs ~9–10M; lawless ratting ≤ ~15M/h; secure ratting ≤ 0.3M/h; mining 2–4M/h. No tool measures earnings per hour. | RULING (Q5); I can build the earnings report (TO FIX) |
| D2 | High | The free ship on loss (see G1): your two rulings conflict, people's frigate (11-14) vs the Courier as the free ship (11-18). | RULING (Q1) |
| D3 | High | **The docked ×16 clock multiplies every passive income** (members, citadel miners, drills, industry, research, colonies): an AFK money press. | RULING (Q22) |
| D4 | High | **A citadel Moon Miner yields 37–187× a tower's Moon Drill**, and asteroid miners never deplete: towers' extraction and active mining are obsolete. | RULING (Q6) |
| D5 | High | **Training no longer gates anything:** battleship 0.8 h, ultracapital 7.8 h, everything at V in ~170 real hours. Progression is money alone after week one. | RULING (Q7) |
| D6 | High | **PvE ends at battleship scale;** the 26 capital combat hulls (1.2–40B) have nothing to fight. | RULING (Q23) |
| D7 | High | **Every region meets the same four pirate hulls** (27 of 169 hulls are ever flown by NPCs; packs chosen by security only; mission chiefs are plain pirates). | RULING (Q24) |
| D8 | High | **Station market depth caps all trade:** best 1–2 jump trade ~+16k whatever the hold; selling 6M of ore fetches 60% of par. A bigger hauler gains nothing. | RULING (Q4) |
| D9 | High | **Corporation members drain the pilot's wallet:** shares are paid at par in cash at once, goods sit unsold in many hangars, and `Corporation.Spend` falls back silently on the pilot's wallet (−60M of the pilot's own in a 2,000 h probe). | RULING (Q25); a warning before using the pilot's wallet is TO FIX |
| D10 | High | NPC members never climb their hull ladder in realistic play (no fighter bought a destroyer in 2,000 h). | RULING (Q25) |
| D11 | High | Members of four peoples (Vessari, the default start, among them) can never get a barge; every member of a people flies the same hull. | TO FIX (fall back to another people's hull of the class; vary hulls) |
| D12 | High | A new corporation's haulers always leave within three days (the prospect table assumes price gaps 3× those the economy makes). | TO FIX |
| D13 | High | At 2,000–5,000 systems the war layer goes quiet after day one (0 wars in 30 days). | RULING (Q26) |
| D14 | High | A pilot's citadel in lawless space is always raided to a hulk when the pilot is away: raid defence counts only tower batteries, which citadels can't have. | TO FIX (count its defence and shield modules); weights are mine, say if wrong |
| D15 | High/Med | Tower risk is a cliff (no batteries: falls in ~6.5 h; five batteries: never); claiming a system makes its towers permanently safe; raids ignore wormhole depth. | RULING (Q12) |
| D16 | Med | PvE danger only at belts; hauling, trading and exploring carry no risk; capsules are never targeted. | RULING (Q27) |
| D17 | Med | The sim's timescales (wars, shocks, grades) assume game days, but game time is play time: a 2-hour session sees ~0.08 war declarations. | RULING (Q26) |
| D18 | Med | Price screens show the system level, not what the player can trade at; news says "dear for N days" while the spike decays in hours. | TO FIX (honest news wording, real range on the legend); the rest RULING (Q4) |
| D19 | Med | Industry's margin is fixed at ~40% everywhere; battleships and up can't be built from market materials. | RULING (Q4) |
| D20 | Med | Scouts are the best-paid member trade and earn from nothing. | RULING (Q25) |
| D21 | Med | Fighter members multiply the belt respawn wait (10 fighters: 57×), taking the pilot's ratting away. | RULING (Q25) |
| D22 | Med | Your own characters are strictly better members than NPCs. | RULING (Q25) |
| D23 | Med | Ops are a free permanent buff (= G31). | RULING (Q15) |
| D24 | Med | 120 members: 85 extra ships in the pilot's system (Core tick 0.5 → 10 ms); members list can't be sorted; logs hold about a day. | TO FIX (sortable list); a cap on ships shown nearby is RULING (Q25) |
| D25 | Med | Wormhole depths 4–5 add danger but no content; Benthic Alloy is used by nothing. | RULING (Q28) |
| D26 | Med | Exploration never gets harder (signal strength and hacking size don't scale with depth/band). | RULING (Q28) |
| D27 | Med | Jobs and invasions come from fixed tables, not the sim; careers stop after hour 1. | RULING (Q29) |
| D28 | Med | Holes in the hull ladder: barge → capital industrial; battleship → carrier (8×); industrial → freighter. | RULING (Q30) |
| D29 | Med | Almost no recurring costs, so money only piles up. | RULING (Q27) |
| D30 | Low/Med | Clarity: the death message names nothing; a cloaked Drowned pack arrives unannounced; the citadel window doesn't show a raid defence of 0. Performance: the commerce step is 218 ms at 5,000 systems in one tick, and station markets are never closed. | TO FIX (messages, citadel defence shown, spread the commerce step) |

Also safe to fix, from the design review: the balance tool compares hulls
without their bonuses (27 false "same as" hulls); a stale comment says a
freighter courier run pays 10–15M (it pays ~49M); siege captures ignore
the 40-claim cap. TO FIX.

---

## 5. Questions for you

1. **Free ship after a loss** (G1/D2): your 11-14 ruling has a pilot begin in their people's frigate; 11-18 says the Courier stays as the free ship. On a loss, should the capsule be given a Courier (cheap, so losing isn't income) or the people's frigate? I've already stopped given ships being packaged or sold either way.
2. **Signing releases** (S1): sign the manifest with a key kept on this laptop, the launcher refusing anything unsigned or older than what is installed? It means one key file you must not lose (losing it means reinstalling launchers by hand).
3. **Commit e-mail** (S8): keep your Gmail address on GitHub commits, or switch to a GitHub no-reply address for future commits?
4. **The market as a money tap** (G2, G4, G14, G15, G22, D8, D18, D19, U16): several rules let money be made from the market itself — scarce goods at 4× at every station with no restock, LP blueprints resold for billions, two orders at one station farming the spread, supply jobs filled from the same station, refining at a profit, and markets too shallow for any real trade run. I'd suggest: scarce goods priced near par and restocking over days; LP store items priced against their worth (or unsellable); orders not filling against your own opposite orders; supply jobs for goods the station doesn't sell; a small refining fee; and deeper markets at trade hubs (depth following the system's stock). Go ahead with all of that, some, or none?
5. **Income balance** (D1): courier pay dominates. Make it grow less than linearly with volume × jumps (and/or ask collateral), and target a band (say combat within 2× of hauling)? I'll build an earnings-per-hour report either way so it can be measured.
6. **Citadel miners vs towers** (D4): scale citadel miners to the tower drill's yield × citadel size (so a big citadel is ~5 towers, not ~180), and make the asteroid miner deplete belts?
7. **What gates the big hulls** (D5): with training ~10× faster, a capital is hours of training away. Gate capitals by something besides time (standing with a faction, a shipyard citadel, certification jobs), or steepen capital skill ranks, or leave it?
8. **A fallen faction citadel's hangar** (G5): the pilot's things there — lost, half kept (as at a pilot's citadel hulk), or moved to the nearest station?
9. **Rebuilt hulk then unanchored** (G6): unanchoring a rebuilt citadel gives back only the rebuild materials, or a damaged packaged citadel worth less, or forbid unanchoring a rebuilt one for some time?
10. **Expelled member's ship** (G8): leave it where it is with nobody flying it (my suggestion), or keep sending it home?
11. **Tether while drones fight** (G12): end a tether when drones are launched or told to attack?
12. **Towers under threat** (G13, D15): no unanchoring while sealed/under siege (and unanchoring takes time); raid strength grows with depth and the Drowned raid at depths 4–5; claimed systems still get raids; a small chance of a raid bigger than the defence?
13. **Deployables picked up** (G26): keep their remaining life on the item (my suggestion), or make them single use?
14. **War then peace** (G30): peace restores at most the standing you had before the war?
15. **Ops** (G31/D23): give ops a cost (a reward pool from the corp wallet, or the pilot being there), or a cooldown?
16. **F10 and quitting** (U2, U3): F10 asks again before loading; Quit and Main menu save first (or ask)?
17. **Windows in a tower's field** (U8): on "Enter field", open just the Starbase window (your own tower) and nothing else?
18. **Ask twice** (U11): which should ask "Sure?": abandon job, expel member, dismiss from fleet, delete saved fit, mutate, forget place, cancel contract, jettison a whole stack, sell all, apply a saved fit over the current one? (My suggestion: all but forget place and apply fit.)
19. **A message log** (U13): add a small history of notices (click the notice to open it)?
20. **Onboarding and Escape** (U23, U24): open the guide on a new game and badge its dock icon; Escape closes the front window/menu/field before opening the menu?
21. **Names** (U25): pick one word each for: Bookmark / Mark here / Places; Keep at / Keep at range; Align / Align to; Lock / Lock target; Crew / Fleet / Pilots / Members.
22. **The ×16 clock** (D3, U28): remove it, keep it but hold passive producers at ×1, or allow it in a tower's field too?
23. **Capital PvE** (D6): add capital-scale content (fleet invasions, Drowned strongholds, keep fortresses), or rule capitals are for war and industry only?
24. **Pirate variety** (D7): pirates fly their region's faction derivative hulls, mission chiefs are captains, and the unused pirate hulls come into packs?
25. **Members' economy** (D9, D10, D20–D22, D24): members sell their own goods (share paid on what it fetches) instead of cash at par; earnings and grade hours scaled to the hull ladder; scouts paid per site; fighters' effect on belt respawn capped at ~2×; and a cap on how many members' ships are drawn near you?
26. **Wars and the sim's clock** (D13, D17): friction by proximity/contested claims and a claim cap scaled to the galaxy so wars happen at 5,000 systems; and a faster strategic clock (or shorter durations) so a session sees the galaxy move?
27. **Risk outside belts, and money sinks** (D16, D29): gate camps that can catch a hauler, capsules targeted in lawless space; and recurring costs (clone upkeep, insurance premiums, citadel upkeep)?
28. **Deep wormholes and exploration** (D25, D26): what Drowned sites are and what Benthic Alloy is for; exploration difficulty scaling with depth/band?
29. **Content from the sim** (D27): jobs drawn from the economy and events, a reroll, a second tier of career lessons (agents, wormholes, towers, citadels), invasions from the Drowned by depth?
30. **Hull ladder holes** (D28): add a mid-size miner, a battleship→carrier step, and a mid-size hauler (class names and seeds yours)?

---

## Commits made tonight

(Filled in as the fixes land.)
