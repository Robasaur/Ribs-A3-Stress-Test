// leak_ui_init.sqf

LH_fnc_openUI = {
  createDialog "LeakHarnessDialog";
};

LH_fnc_uiInit = {
  private _disp = uiNamespace getVariable ["LH_ui", displayNull];
  if (isNull _disp) exitWith {};

  private _sl = _disp displayCtrl 8831;
  _sl sliderSetRange [1,10];
  _sl sliderSetPosition 5;
  (_disp displayCtrl 8832) ctrlSetText "5";

  _sl ctrlAddEventHandler ["SliderPosChanged", {
    params ["_ctrl", "_new"];
    private _d = ctrlParent _ctrl;
    (_d displayCtrl 8832) ctrlSetText str (round _new);
  }];

  // Stats updater (client asks server once per second)
  private _statsCtrl = _disp displayCtrl 8861;

  // Prevent double loops if dialog is reopened
  private _old = uiNamespace getVariable ["LH_statsHandle", scriptNull];
  if (!isNull _old) then { terminate _old; };

  private _h = [_disp, _statsCtrl] spawn {
    params ["_disp", "_statsCtrl"];

    while {!isNull _disp} do {
      // ask server for stats, server replies directly to this client
      [clientOwner] remoteExecCall ["LH_fnc_serverSendStats", 2];

      uiSleep 1;
    };
  };

  uiNamespace setVariable ["LH_statsHandle", _h];

  hint "Leak UI loaded.";
};

LH_fnc_uiStart = {
  private _disp = uiNamespace getVariable ["LH_ui", displayNull];
  if (isNull _disp) exitWith { hint "UI missing (no display)."; };

  private _duration = parseNumber ctrlText (_disp displayCtrl 8811);
  private _cycle    = parseNumber ctrlText (_disp displayCtrl 8821);
  private _intensity = round sliderPosition (_disp displayCtrl 8831);

  _duration  = _duration max 30 min 7200;
  _cycle     = _cycle max 1  min 60;
  _intensity = _intensity max 1 min 10;

  [_duration, _intensity, _cycle] remoteExec ["LH_fnc_serverStart", 2];

  hint format ["Requested start:\nDuration %1s\nIntensity %2\nCycle %3s", _duration, _intensity, _cycle];
};

LH_fnc_uiStop = {
  [] remoteExec ["LH_fnc_serverStop", 2];
  hint "Requested STOP (server kill flag set).";
};

// HUD
LH_fnc_hudStart = {
  cutRsc ["LH_StatsHUD", "PLAIN", 0, false];
  systemChat "[LH] HUD requested (cutRsc called)";

  private _old = uiNamespace getVariable ["LH_hudHandle", scriptNull];
  if (!isNull _old) then { terminate _old; };

  private _h = [] spawn {
    // wait for the HUD to be created
    waitUntil {
      uiSleep 0.05;
      !(isNull (uiNamespace getVariable ["LH_StatsHUD_Display", displayNull]))
    };

    while {true} do {
      [clientOwner] remoteExecCall ["LH_fnc_serverSendStatsHUD", 2];
      uiSleep 1;
    };
  };

  uiNamespace setVariable ["LH_hudHandle", _h];
};


LH_fnc_hudStop = {
  private _old = uiNamespace getVariable ["LH_hudHandle", scriptNull];
  if (!isNull _old) then { terminate _old; };
  uiNamespace setVariable ["LH_hudHandle", scriptNull];

  // remove overlay
  cutText ["", "PLAIN"];
};

// Server sends stats to HUD receiver
LH_fnc_serverSendStatsHUD = {
  if (!isServer) exitWith {};
  params ["_targetOwnerId"];

  private _stats = [] call LH_fnc_serverGetStats;
  [_stats] remoteExecCall ["LH_fnc_clientRecvStatsHUD", _targetOwnerId];
  diag_log format ["[LH HUD] serverSendStatsHUD called for owner %1", _targetOwnerId];
};

// Client receives stats and writes to HUD control
LH_fnc_clientRecvStatsHUD = {
  params ["_stats"];

  private _hud = uiNamespace getVariable ["LH_StatsHUD_Display", displayNull];
  if (isNull _hud) exitWith {}; // HUD not up yet

  private _ctrl = _hud displayCtrl 8902;
  if (isNull _ctrl) exitWith {};

  _stats params ["_t","_fps","_units","_groups","_veh","_objs","_scripts","_running","_kill"];

  _ctrl ctrlSetText format [
    "LEAK HARNESS (SERVER)\nFPS: %1  Units: %2  Groups: %3\nVeh: %4  Objs: %5  SQF: %6\nRunning: %7  Kill: %8  t=%9",
    _fps toFixed 1,
    _units, _groups,
    _veh, _objs, _scripts,
    _running, _kill,
    _t toFixed 0
  ];
};

// Server functions
LH_fnc_serverStart = {
  if (!isServer) exitWith {};
  params ["_duration","_intensity","_cycle"];

  missionNamespace setVariable ["LEAKTEST_KILL", true, true];
  uiSleep 0.1;
  missionNamespace setVariable ["LEAKTEST_KILL", false, true];

  [_duration, _intensity, _cycle] execVM "leakHarness.sqf";

  diag_log text format ["[LEAKHARNESS][UI] START dur=%1 int=%2 cycle=%3", _duration, _intensity, _cycle];
};

LH_fnc_serverStop = {
  if (!isServer) exitWith {};
  missionNamespace setVariable ["LEAKTEST_KILL", true, true];
  diag_log text "[LEAKHARNESS][UI] STOP";
};

LH_fnc_serverGetStats = {
  if (!isServer) exitWith {[]};

  private _running = missionNamespace getVariable ["LEAKTEST_RUNNING", false];
  private _kill    = missionNamespace getVariable ["LEAKTEST_KILL", false];

  [
    time,
    diag_fps,
    count allUnits,
    count allGroups,
    count vehicles,
    count allMissionObjects "All",
    count diag_activeSQFScripts,
    _running,
    _kill
  ]
};

LH_fnc_serverSendStats = {
  if (!isServer) exitWith {};
  params ["_targetOwnerId"];
  private _stats = [] call LH_fnc_serverGetStats;
  [_stats] remoteExecCall ["LH_fnc_clientRecvStats", _targetOwnerId];
};

LH_fnc_clientRecvStats = {
  params ["_stats"];
  private _disp = uiNamespace getVariable ["LH_ui", displayNull];
  if (isNull _disp) exitWith {};
  private _ctrl = _disp displayCtrl 8861;
  if (isNull _ctrl) exitWith {};

  _stats params ["_t","_fps","_units","_groups","_veh","_objs","_scripts","_running","_kill"];

  _ctrl ctrlSetText format [
    "SERVER STATS\nTime: %1\nFPS: %2\nUnits: %3\nGroups: %4\nVehicles: %5\nMissionObjs: %6\nSQF Scripts: %7\nRunning: %8\nKillFlag: %9",
    _t toFixed 1, _fps toFixed 1,
    _units, _groups, _veh, _objs, _scripts,
    _running, _kill
  ];
};
