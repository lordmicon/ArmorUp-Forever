ARMORUP  (version 1.3.0)
Warlock armor reminder for WoW Forever (Interface 16001)
==========================================================

WHAT IT DOES
ArmorUp warns you shortly before your Demon Skin or Demon Armor runs out, so you
can refresh it before it drops. A popup appears showing the best rank of the
spell you know, and a sound plays. Click the popup to recast.

By default the warning comes 15 seconds before the armor drops. If you set the
warning time to 0, ArmorUp warns you only when the armor is already down.

ArmorUp loads for Warlocks only. On any other class it prints a message in chat
saying it did not load, and does nothing else.

SPELLS USED
  Demon Skin   - level 1 and level 10 (two ranks)
  Demon Armor  - levels 20, 30, 40, 50 and 60 (five ranks)
The highest rank you know is chosen automatically, and it updates when you
level up or learn a new rank.

WHY YOU HAVE TO CLICK
WoW does not let addons cast spells on their own (the game blocks it), so
ArmorUp shows the popup and you click it. You can also bind a key (see below).

NOTES ON COMBAT
If the game hides your buff information during combat, ArmorUp keeps track of
the timer itself (it assumes the armor lasts 30 minutes and notes when you cast
it), so the warning still works. The timer is corrected as soon as combat ends.
If something removes your armor mid-fight, ArmorUp may not notice until combat
ends.

THE POPUP
 - Click it to cast the armor spell.
 - Drag it with the left mouse button to move it.
 - It also shows during combat (you can turn that off in settings), so you
   can refresh your armor in the middle of a fight. It hides while you are dead,
   and while you are mounted (that can be turned off too).
 - Moving or resizing the popup only works out of combat (a game restriction).

SETTINGS
Type /armorup (or /au) to open the settings window. You can also open it from
Options > AddOns > ArmorUp.

  Warn before it drops ...  seconds of warning. Arrows change it by 15, hold
                            Shift for 60. 0 = warn only when the armor is down.
  Show during combat .....  on by default.
  Hide while mounted .....  on by default.
  Popup size (%) .........  make the popup bigger or smaller.
  Alert sound ............  turn the sound on or off and pick which one plays
                            (see below).

Buttons along the bottom: Test popup, Reset popup position, Reset defaults, Close.

KEYBIND (OPTIONAL)
Key Bindings > AddOns > ArmorUp > "Cast best armor spell"
or make a macro containing:   /click ArmorUpButton

OTHER COMMANDS
  /armorup test     show the popup for a few seconds
  /armorup status   print your best spell and whether the armor is active

ALERT SOUND
Pick the sound in the settings window. Each choice has a Play button to hear it:
  1H Armor Plate Critical  (148)  - the default
  Ready Check              (8960)
  Raid Warning             (8959)
Or choose "Custom ID", type any sound ID, press Play to hear it, then select the
Custom ID button (or press Enter) to use it. Sound IDs can be looked up at
https://www.wowhead.com/classic/sounds

INSTALL
Copy the ArmorUp folder into  Interface/AddOns/  so the path is
Interface/AddOns/ArmorUp/ArmorUp.toc, then restart the game or type /reload.
The folder contains ArmorUp.toc, ArmorUp.lua, Bindings.xml and this readme.
(Bindings.xml only adds the entry to the Key Bindings screen. It can be deleted
if you do not want it.)
