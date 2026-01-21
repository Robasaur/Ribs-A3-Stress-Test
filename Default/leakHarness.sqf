/*
  leakHarness.sqf
  Stress + leak hunting harness (bounded, controllable, logs to RPT)

  Params:
    0: duration seconds (default 900)
    1: intensity 1..10 (default 5)
    2: cycle seconds (default 10) - how often to do a churn cycle

  Kill switch:
    missionNamespace setVariable ["LEAKTEST_KILL", true, true];
*/

params [
  ["_duration", 900, [0]],
  ["_intensity", 5, [0]],
  ["_cycle", 10, [0]]
];

_intensity = _intensity max 1 min 10;
_duration  = _duration max 30 min 7200; // 30s..2h
_cycle     = _cycle max 1 min 60;

missionNamespace setVariable ["LEAKTEST_KILL", false, true];
missionNamespace setVariable ["LEAKTEST_RUNNING", true, true];

private _endAt = time + _duration;

// -
// Tunables (scaled)
// -
private _objPerCycle   = 20  * _intensity;       // create/delete objects per cycle
private _grpPerCycle   = 1   + floor (_intensity / 3); // AI groups per cycle
private _mrkPerCycle   = 30  * _intensity;       // markers per cycle
private _strLoops      = 500 * _intensity;       // string churn loops per cycle
private _arrSize       = 5000 + (5000 * _intensity); // allocation size
private _maxObjsLive   = 500 * _intensity;       // safety cap
private _maxUnitsLive  = 80  * _intensity;       // safety cap

// Containers we can clean up
private _spawnedObjs = [];
private _spawnedGrps = [];
private _spawnedMrks = [];
private _bigJunk     = []; // we overwrite this repeatedly to churn allocations

// Pick a safe-ish area near origin if nothing else
private _basePos = [0,0,0];
if (!isNil "player" && {!isNull player}) then { _basePos = getPosWorld player; };
if (_basePos isEqualTo [0,0,0]) then { _basePos = [worldSize/2, worldSize/2, 0]; };

private _log = {
  params ["_msg"];
  diag_log text format ["[LEAKHARNESS] %1 | t=%2 | fps=%3 | units=%4 | veh=%5 | objs=%6 | scripts=%7",
    _msg,
    (time toFixed 1),
    (diag_fps toFixed 1),
    (count allUnits),
    (count vehicles),
    (count allMissionObjects "All"),
    (count diag_activeSQFScripts)
  ];
};

// Helper: random pos in radius
private _rndPos = {
  params ["_center", "_r"];
  private _a = random 360;
  private _d = random _r;
  [
    (_center select 0) + (sin _a) * _d,
    (_center select 1) + (cos _a) * _d,
    0
  ]
};

// Helper: cleanup (best effort)
private _cleanup = {
  // markers
  { deleteMarker _x; } forEach _spawnedMrks;
  _spawnedMrks = [];

  // objects
  { if (!isNull _x) then { deleteVehicle _x; }; } forEach _spawnedObjs;
  _spawnedObjs = [];

  // groups/units
  {
    if (!isNull _x) then {
      { if (!isNull _x) then { deleteVehicle _x; }; } forEach (units _x);
      deleteGroup _x;
    };
  } forEach _spawnedGrps;
  _spawnedGrps = [];

  // release big allocations
  _bigJunk = [];
};

// -
// Main loop
// -
["Starting"] call _log;

while {time < _endAt} do {
  if (missionNamespace getVariable ["LEAKTEST_KILL", false]) exitWith {};

  //  SAFETY CAPS 
  if ((count allMissionObjects "All") > _maxObjsLive) then {
    ["Safety cap hit: too many objects -> cleanup"] call _log;
    call _cleanup;
  };
  if ((count allUnits) > _maxUnitsLive) then {
    ["Safety cap hit: too many units -> cleanup"] call _log;
    call _cleanup;
  };

  // Allocation churn (arrays/strings) 
  // (This is where leaks/fragmentation-like issues often show up in bad mission scripts/mods)
  _bigJunk = [];
  _bigJunk resize _arrSize;

  for "_i" from 0 to (_arrSize - 1) do {
    _bigJunk set [_i, [random 1e9, str random 1e9, [random 999, random 999, random 999]]];
  };

  private _s = "";
  for "_k" from 1 to _strLoops do {
    _s = _s + str (random 1e6);
    if ((_k % 50) == 0) then { _s = ""; }; // force churn rather than unbounded growth
  };

  // Marker churn 
  for "_m" from 1 to _mrkPerCycle do {
    private _name = format ["LH_MRK_%1_%2", diag_tickTime, _m];
    private _pos  = [_basePos, 200 + (50 * _intensity)] call _rndPos;
    private _mrk  = createMarker [_name, _pos];
    _mrk setMarkerShape "ICON";
    _mrk setMarkerType "mil_dot";
    _mrk setMarkerText format ["%1", _m];
    _spawnedMrks pushBack _mrk;
  };

  // delete half the markers each cycle (create/delete churn)
  private _half = floor ((count _spawnedMrks) / 2);
  for "_i" from 1 to _half do {
    private _mrk = _spawnedMrks deleteAt 0;
    deleteMarker _mrk;
  };

  // Object churn (create/delete) 
  // Use cheap objects, keep it generic. Place slightly around base.
  for "_o" from 1 to _objPerCycle do {
    private _pos = [_basePos, 50 + (10 * _intensity)] call _rndPos;
    private _obj = createVehicle ["Land_Can_V3_F", _pos, [], 0, "CAN_COLLIDE"];
    _obj setPosATL _pos;
    _spawnedObjs pushBack _obj;
  };

  // delete a chunk
  private _delCount = floor ((count _spawnedObjs) * 0.6);
  for "_i" from 1 to _delCount do {
    private _obj = _spawnedObjs deleteAt 0;
    if (!isNull _obj) then { deleteVehicle _obj; };
  };

  // AI churn (groups/units) 
  // This stresses scheduler + path + group lifecycle (another leak hotspot in sloppy scripts)
  for "_g" from 1 to _grpPerCycle do {
    private _grp = createGroup [west, true];
    _spawnedGrps pushBack _grp;

    private _countUnits = 3 + floor random (2 + _intensity);
    for "_u" from 1 to _countUnits do {
      private _pos = [_basePos, 150 + (20 * _intensity)] call _rndPos;
      _grp createUnit ["B_Soldier_F", _pos, [], 0, "NONE"];
    };

    // Give them something to do (light)
    [_grp, _basePos] spawn {
      params ["_grp", "_basePos"];
      for "_i" from 1 to 5 do {
        if (missionNamespace getVariable ["LEAKTEST_KILL", false]) exitWith {};
        private _wpPos = [_basePos, 200] call {
          params ["_c","_r"];
          private _a = random 360; private _d = random _r;
          [(_c select 0)+(sin _a)*_d, (_c select 1)+(cos _a)*_d, 0]
        };
        private _wp = _grp addWaypoint [_wpPos, 0];
        _wp setWaypointType "MOVE";
        uiSleep (0.5 + random 0.5);
      };
    };
  };

  // Delete oldest groups sometimes
  if ((count _spawnedGrps) > (3 * _intensity)) then {
    private _old = _spawnedGrps deleteAt 0;
    if (!isNull _old) then {
      { if (!isNull _x) then { deleteVehicle _x; }; } forEach (units _old);
      deleteGroup _old;
    };
  };

  // Telemetry
  ["Cycle complete"] call _log;

  uiSleep _cycle;
};

missionNamespace setVariable ["LEAKTEST_KILL", true, true];
missionNamespace setVariable ["LEAKTEST_RUNNING", false, true];

call _cleanup;
["Finished + cleaned"] call _log;