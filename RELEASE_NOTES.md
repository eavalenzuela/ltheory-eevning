# What is new

What each release brings, the newest first, written for whoever plays it.
`script/publish` puts the first section on the portal page as "In this
release" and the ones under it as "Before that": write a release's
section before publishing it. A section is a line beginning `## ` and
the lines beginning `- ` under it.

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
