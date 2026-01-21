// initServer.sqf
[] execVM "leak_ui_init.sqf";

[] spawn {
  uiSleep 15; // let mission fully settle
  [1800, 7, 8] execVM "leakHarness.sqf";
};