Let it run for 15–30 minutes and watch your FPS drop!
- If objs= / units= / scripts= steadily climb even though we’re deleting stuff 
> you’ve got a leak in mission code (or something holding references / not deleting EHs, PFHs, UI handles, etc.).
- If fps drops over time without counts rising, that often screams fragmentation / runaway scheduled scripts / handler buildup.

---

serverInit.sqf - Runs the serversided scripts - ensure you run your mission in multiplayer - should work in single, but may need to launch UI from debug console?
leakHarness.sqf - Is the script that breaks things (deliberately).
description.ext - contains the extensions and classes necessary for the UI hpp to function
leak_ui.hpp - contains the classes that draws the UI/HUD
leak_ui_init.sqf - contains the scripting side of the UI/HUD

---

files structure (root of mission folder)
mission.sqm
serverInit.sqf
leakHarness.sqf
+ all UI files from the UI folder

---

player init (double click the unit, paste this in the init):
[] execVM "leak_ui_init.sqf";

[] spawn {
  uiSleep 2;
  [] call LH_fnc_hudStart;
};

this addAction ["Open Leak Harness Control", { [] call LH_fnc_openUI; }];

---

kill command:
missionNamespace setVariable ["LEAKTEST_KILL", true, true];
