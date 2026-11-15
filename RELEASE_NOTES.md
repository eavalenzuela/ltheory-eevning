# What is new

What each release brings, the newest first, written for whoever plays it.
`script/publish` puts the first section on the portal page as "In this
release" and the ones under it as "Before that": write a release's
section before publishing it. A section is a line beginning `## ` and
the lines beginning `- ` under it.

## Looking inside the anti-aliasing

- The Graphics page has two more controls at its foot, for finding a fault in the picture: what the anti-aliasing shows (the picture, the edges it found, or the weights it made of them), and how it blends (the game's own way, or the plain way of the method). Neither is kept: the game starts with the picture and its own blend.

## Starting with the sound off

- The game stopped as it started if sound was switched off in the options. It starts now. (Switching sound off in the options while nothing was playing stopped it the same way.)

## When it fails, it says where

- If the game stops on an error, `log.txt` in the game's folder now says what it was doing when it did: send that file.

## Paints for good, and a Graphics page

- A paint or a design is now yours for good. Buy one, open the fitting screen, and it is on the list at its left, marked new: click it and it is yours (the thing bought is used up) and on your ship. From then on every paint and design you own is on that list for any ship you fly: click one to switch, as often as you like, for nothing. The first row of each list takes it off. (You can also right-click one in the inventory and choose "Make it yours".)
- A paint's page on the market says when it is yours already.
- If you painted a ship before this release, what your ships are painted in is yours.
- Options has a Graphics page: a switch for each stage the picture is made in (sun and sky light, lights near things, glows and beams, particles, lens flares, bloom, tone mapping, colour grading, anti-aliasing, dither). All on is the game as it is meant to look. If something in the picture looks wrong on your machine, switch stages off one at a time: the one that makes it go away is where the fault is.

## A night's work

- The game opens on a splash: its mark and its name come up out of black, and any key or a click sends it on to the menu.
- Paint for your ship. Stations sell twelve paints and eight designs (Market, Paints). A paint is a set of colours; a design is a figure laid over it (a racing stripe, hoops, chevrons, dazzle, tiger stripes, chequers, a bow cap, port and starboard). "Try on" on a paint's market page shows your ship in it on the fitting screen before you buy. Bought, right-click it in the hangar and choose "Paint the ship with it": it is used up, and the ship keeps it until you paint it again or strip it (fitting screen, Strip). A design needs a paint under it. Paint changes nothing but how the ship looks.
- The picture of your ship on the fitting screen no longer flashes wrong for a moment when the fit changes.
- New towers. Every station's tower is a new model, grown the way the ship generator grows hulls and stood on end: a spindle that tapers to a spire above and a tail below, with a lit mooring ring round its waist. The Vessari's are blocky and square, the Talmar's smooth and swelling, the Orun's thin spars with masts. Three sizes of each.
- The ship generator has two more styles to draw hulls in: triangular (a dagger of stepped decks with a conning tower) and asymmetrical (one side heavier than the other, often with an outrigger). No ship in the game is drawn in them yet: they are there to pick seeds from (`bin/launch hulls`, S for the style).
- More music: two more pieces for space, one more for a station and one more for a fight, and a piece of its own for space no chart shows. A mood now goes through its pieces in turn.
- Sounds for what had none: a cloak going on and coming off, a module coming out of a mutator, a deal done on a market, a lock in a derelict opened or lost, drones going out and coming back, armour and shield being mended, an afterburner lit, a salvager's cut, loot taken aboard, a mining laser at work, a capital ship breaking up, and a warning when your hull is nearly gone. Word of an invasion has a graver sound than the rest, and what begins too far away to be told of is no longer sounded at all. Uncharted space has an air of its own.

## Better makes of a module

- Each of the four peoples has its own make of what it is known for, and of one useful thing besides: Vessari launchers, armour and cargo extensions; Talmar autocannons, artillery, shields and tracking; Orun blasters, railguns, armour and engines; Kethri lasers, armour and capacitor. A people's make gives 15% more than the plain module (more than a Custom make, less than Tech 2), fits the same and needs no more skill. Their own stations sell a few, at about six times the price, to a pilot they think well of (standing 2 or better), and about one job in five at their stations pays in one instead of credits: the job's line says which.
- Officers. A named pirate captain that is sighted, the leader of an invasion and the commander of a pirate tower each carry modules of their own, with their name on them: better than a Masterwork in everything, and easier to fit. They are only ever found in that officer's wreck.
- Mutators. A mutator puts a module through once, and what comes out is another module: what it gives, how hard it is to fit, what it draws and how far it reaches are each thrown again, anywhere from a quarter worse to three tenths better. It cannot be undone and cannot be done twice. Right-click a module in a station's hangar and choose "Mutate" (a mutator has to be in the same hangar). Mutators come from officers' wrecks and from some derelicts.
- An officer's module and a mutated one are not sold on any market: what you find is what there is.

## Three things from play

- A ship sent somewhere from a standstill no longer snaps to face it: the hull comes round as it gets under way, quickly for a frigate and slowly for a big ship.
- Skill books: right-click a book in the inventory and choose "Learn this skill". It works from the hangar or from your hold, docked or in space, and if the skill needs another first the menu says which. (The Skills tab's Learn button now finds a book in your hold too.)
- The assets window has a "Set course" button beside every station that holds something of yours in another system.

## Things going on

- Pirates now mass where the galaxy says they would: in systems where order is thin and trade is rich, several at once across the map, instead of one surge at a time near you. Destroying pirates in a system holds a surge off, and ten destroyed during one breaks it.
- A surge that runs its course leaves that system a little less safe for three days. One that is broken leaves it a little safer.
- A new Events button at the foot of the screen opens a list of everything going on, nearest first: where, how many jumps, how long it has left, and a button to set course there. The star map rings each such system.
- Sightings, every hour or two within a few jumps: a named pirate captain with an escort and a wreck worth taking, a derelict hull already found for you, or a wandering trader whose rare stock is on a station's contract board while they stay.
- Luck at places, every few hours: a station's refinery, yards or laboratory out of use for a day, a gate closed for repairs (routes and the autopilot go round it), or a rich belt of rare ore.
- Invasions: now and then a force comes out of wormhole space into a system and digs in for four hours. Its lines are on the overview; fight it there and the system's keeper pays 400,000 when the last of them is gone. Left alone, it shuts the works of that system's stations and leaves the place less safe for days. (For now the invaders are pirates.)

## Trial 1 of 3 for the dark specks

- One of the three withdrawn changes is back by itself, to find which of them blacked the sky in warp on AMD cards: effects that only add light (the stars, the warp streaks, glows) now say outright that they change nothing of the surface under them. To look for: is the sky right in warp, and are the dark specks on bright things gone?

## The sky in warp, put back

- The last release's change for the dark specks made the whole sky go black in warp on some graphics cards (AMD's, on Windows). That change is withdrawn: the sky is as it was, and so, for now, are the specks. They will be gone for properly once it is known which part of the change the card took badly.

## A station's field is a wall

- Nothing shoots across a station's field, in or out. Inside it nothing outside can lock you, and you can lock nothing outside: a missile already on its way stops at the field.
- A station's batteries now stand outside its field, where they can shoot and be shot at. They are on the overview (Gun Battery, Missile Battery). One that is destroyed is rebuilt in two hours.
- To go inside, approach the station (Approach, or Q with it selected): you fly in to the tower, and are told when you cross the field. Docking still works from the field's edge, as before.
- Pirates cannot come in, and neither can you while the patrols have you marked: the field puts you out. Pirates who were after you go for the batteries, or circle the field firing on the tower, and give up after a few minutes.
- Your own tower's field is up while it has fuel, and stays up when the tower seals itself. Raiders shoot at it from outside.

## A frigate of your own, and windows that move

- A new pilot begins in a frigate of the people whose station they start at (at a Vessari one, an Akashi), cheaply fitted: one small gun, one light missile launcher and a plate of armour, with a slot left free, and the skills to fit all of it. The old Courier is no longer where anybody begins. (A game already begun keeps the ship it has.)
- A pilot who wakes with no ship is given a bare frigate of the people whose station it is. A ship that was given pays little when it is lost (12,000 credits, as before): ships you buy or build are insured for what they are.
- The docked screen and the star map are windows now: drag either by its heading to put it where you like. They stay where you leave them.
- Traders fly the haulers and freighters of the people whose space they are in, and no longer the plain hulls nobody's yards build.

## No more dark boxes

- On some graphics cards (AMD's, on Windows) ships and station modules sat in large dark rectangles. A few pixels were being worked out as something that is no number at all, and the glow that spreads bright light spread those too. They are now caught before they can spread, and the places they came from are mended.

## Mended for Windows, and an icon

- The star could not be drawn on some graphics cards (AMD's, on Windows), which stopped the game as it started: its shaders, and every other one, have been gone through for what such a driver refuses.
- If something still fails to draw, the game says so in `log.txt` and carries on, where before it stopped and waited.
- On a screen with Windows' text scaled up (125%, 150%), the game now uses the screen's real size.
- The game and its launcher have an icon of their own, on the desktop and in the taskbar.
- On Windows the game no longer opens a black console window beside itself. What it has to say is kept in `log.txt`, in the game's folder: send that along if something goes wrong.
- This page now says what changed in words meant for players.

## First release on the LAN

- Limitless Space installs and updates itself from this page's launcher: put the launcher in an empty folder and run it.
- Options, Window: choose how the game opens (automatic, fitted to the screen, or a window of 1920 by 1080 or 2560 by 1440). It takes effect the next time the game starts.
- The inventory is a window you can move and resize (the Inventory button, or I): drag things between your hold, the hangar and wrecks, right-click for what can be done with them, and open any place in a window of its own.
- Pilots who join your corporation can be seen at their work where you are: miners at the belts, haulers at the gates, and fighters who come when pirates go for you.
- Known for now: the interface is laid out for screens of 1920 by 1080 and larger, and crowds itself on smaller ones.
