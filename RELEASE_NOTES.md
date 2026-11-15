# What is new

What each release brings, the newest first, written for whoever plays it.
`script/publish` puts the first section on the portal page as "In this
release" and the ones under it as "Before that": write a release's
section before publishing it. A section is a line beginning `## ` and
the lines beginning `- ` under it.

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
