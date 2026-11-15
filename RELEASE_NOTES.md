# What is new

What each release brings, the newest first, written for whoever plays it.
`script/publish` puts the first section on the portal page as "In this
release" and the ones under it as "Before that": write a release's
section before publishing it. A section is a line beginning `## ` and
the lines beginning `- ` under it.

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
