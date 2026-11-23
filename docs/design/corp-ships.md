# Ships, the corp hangar, and members who fly what they are given: the plan

Planning only (the owner, 2026-11-23): nothing here is built until the owner says so.

## Why

The owner, 2026-11-23, on ship entry and management, and on assigning ships for corp members to fly:

- "It feels weird to have the ships be managed in 2 places: first in the ships window (unpacked), and then in the inventory (packaged)."
- "in actual corps, you can't refuse to join fleet ops or train into corp doctrines and just be a miner; everyone is expected to help out with varied tasks."
- "I tried the 'simulating real players' setup, and it's too fickle. Ultimately this is a single player game, so no reason to recreate real-life pain points like people not joining corp ops."
- "there is no corp assets window, from which to see which stations have corp hangar assets in them"

## The owner's rulings (2026-11-23)

| Question | Answer |
|---|---|
| Where ships are managed | **In the inventory.** Assembled ships are icons there, right-clicked to board, repackage, assemble and so on. The Ships window goes. |
| Leaving a ship | **You can step out into your capsule**, not only move to another ship. |
| Ejecting | **Anywhere**, in space too. NPCs may steal a ship left on grid with an NPC station or citadel. |
| Corp ships | **A corp hangar of ships.** The owner fits them, puts them in the corp hangar, and assigns a member to one in the member pane. (Single player: whether the pilot or the corp owns a ship makes no real difference.) |
| Trades | **Gone, with their chosen trade fits.** A member joins with a random low-level ship; what they do follows from their assignment and their grade. "A G2 pilot should be g2 for everything." |
| Assigning | The member pane's ship button **lists corp hangar ships that member can fly**; picking one puts them in that ship and its role. |
| Do members buy ships | **No: (a).** They fly their own ship or the one assigned. |
| A corp ship lost | **The insurance pays the corp**; the member goes back to their own ship. |
| Doctrines | **Yes**, with a per-member override (to logi, tackle, and so on). |
| Doctrine supply | **Ships may be assembled** for a doctrine when the corp hangar holds the exact parts of its saved fit. **If any module is missing, it is not made.** "Keep it as simple as possible while allowing for quick outfitting of larger fleets." |
| Calls, not orders | **Overturned.** Invited members always join the fleet. Ops are mandatory. |
| Old saves | Each member's current ship stays theirs. |
| Corp assets | **A Personal / Corporation switch on the Assets window.** |
| Where members deposit | **A headquarters**, set in the corp window to the station or citadel the pilot is docked at. Each member has a **deliver-to** button in their pane: the HQ, and any station or citadel the player owns. |
| Moving corp goods around | **Later:** a hauling job, "move the corp hangar at X to Y", done by a member. |

## The plan, in phases

### 1. Ships in the inventory

- Assembled ships appear in a station's hangar in the inventory, as icons, by their own names.
- **Right-click on a ship:** Board, Fit (the fitting window on that ship, without boarding it), Rename, Repackage, Move to corp hangar / Move to my hangar, Info.
- **Right-click on a packaged hull:** Assemble, beside what an item has now.
- **The ship flown**, the top of the inventory tree: Leave ship.
- **Leave ship, docked** (or in a tower's field): the pilot is in a fresh capsule; the ship stays in the hangar.
- **Leave ship, in space (eject):** the pilot is in a capsule where the ship was; the ship floats there, nobody's flying it, and can be boarded again from close by. On grid with an NPC station or citadel, an NPC may take it.
- The Ships window, its dock icon and its script names go; scenarios move to the inventory's.

### 2. Corp ships, the corp assets view, the headquarters

- A ship is in the pilot's hangar or the corp hangar, moved between them by drag or the right-click menu.
- **Assets window: Personal / Corporation.** Personal is the pilot's alone (corp stacks no longer mixed in). Corporation lists every place with corp things (station corp hangars, towers', citadels'), corp ships among the goods, and a group **With members**: each assigned corp ship, who has it, and where they are, away or not.
- **Headquarters:** "Make this the headquarters" in the corp window, where the pilot is docked at a station or citadel.
- **Deliver to:** each member's pane has a button choosing among the HQ and the player's own stations and citadels. Without an HQ, it is the pilot's home, as now.

### 3. Members without trades

- `member.trade` goes. A member's **role** follows from the ship they are in, read from its fit: mining lasers, mining; a hauler hull, hauling; remote repairers, logi; disruptors or webs, tackle; probes, scouting; guns or launchers, combat. The pane shows the role read, and the owner can set it by hand.
- **Grade 1 to 5 counts for everything**, rising with practice at whatever they do.
- **A new member brings a random low-level ship**, from their faction's hulls, with a plain fit.
- **Away from the pilot**, what a member earns and delivers follows from their role and grade, where trade did before.
- **Members buy no ships.** Lose their own and they get a plain one again, from their own money (the plainest hull is free, as now).
- **Fleets:** an invited member always comes, and stays until dismissed.
- **Ops:** every member not in the pilot's fleet goes to the pilot's ops, and to a Fleet Commander's strikes.
- **Old saves:** each member keeps the ship they fly now, as their own; their first role is read from it.

### 4. Assigning corp ships

- The member pane's ship button (today the hull an own character aims for) becomes the list of corp hangar ships that member can fly, wherever they are, and "their own ship".
- Picked, the member goes to it and boards it; their own ship stays theirs, kept where they left it.
- Lost: the insurance goes to the corp wallet, and the member goes back to their own ship.
- The fleet screen's "Give <ship>" uses corp hangar ships.

### 5. Doctrines

- **A doctrine** has a name and roles, each a saved fit (a hull and its modules), and one role is the main one.
- **Applying it to the fleet**, docked: every member takes the main role unless set to another for them. Each is given a corp hangar ship at the station whose hull and modules are that fit's exactly. With none ready, one is assembled from a packaged hull and the fit's modules in the corp hangar there, if every one of them is there; otherwise nobody gets that role's ship, and the screen says what is short (so many of a hull, so many of a module).

### Later

- A corp hauling job: "move the corp hangar at X to Y", done by a member.

## Mine to propose (the owner may say otherwise)

- Re-boarding an ejected ship: within 2,500 m.
- Theft: a ship left on grid with an NPC station or citadel is taken after an hour unflown, one chance in four each hour after.
- An assigned member away from the pilot reaches the ship's station after a few minutes a jump, coarsely, as their other travel.
- Members' own ops (posted by members of grade 3 and over) go: with ops mandatory, the pilot's ops and Fleet Commanders' strikes are the ops. Titles and the FC stay.
- Members still leave when they are owed pay and neither wallet has it (the pay is real); loyalty no longer makes them leave a fleet or skip an op.
- The owner's own characters keep their skill queue and skill books from their budget; they no longer buy hulls (they fly what is assigned, like everyone).
- Logi and tackle away from the pilot earn as combat does.
