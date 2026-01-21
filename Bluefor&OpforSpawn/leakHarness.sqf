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

  // AI churn (BLUFOR vs OPFOR) 
  // Stresses: group lifecycle, targeting, firing, pathing under contact, combat FSM, ammo sim
  private _spawnCombatPair = {
    params ["_basePos", "_intensity", "_spawnedGrps"];

    private _arenaR = 250 + (30 * _intensity);
    private _sep    = 120 + (15 * _intensity);

    // two opposing spawn centers
    private _posB = [
      (_basePos select 0) - _sep,
      (_basePos select 1) + (random 40) - 20,
      0
    ];
    private _posO = [
      (_basePos select 0) + _sep,
      (_basePos select 1) + (random 40) - 20,
      0
    ];

    // create groups
    private _grpB = createGroup [west, true];
    private _grpO = createGroup [east, true];
    _spawnedGrps pushBack _grpB;
    _spawnedGrps pushBack _grpO;

    // unit counts scale with intensity (kept sane)
    private _countB = 4 + floor random (2 + _intensity);
    private _countO = 4 + floor random (2 + _intensity);

    // spawn units
    for "_i" from 1 to _countB do {
      private _p = [_posB, 25] call {
        params ["_c","_r"];
        private _a = random 360; private _d = random _r;
        [(_c select 0)+(sin _a)*_d, (_c select 1)+(cos _a)*_d, 0]
      };
      _grpB createUnit ["B_Soldier_F", _p, [], 0, "NONE"];
    };

    for "_i" from 1 to _countO do {
      private _p = [_posO, 25] call {
        params ["_c","_r"];
        private _a = random 360; private _d = random _r;
        [(_c select 0)+(sin _a)*_d, (_c select 1)+(cos _a)*_d, 0]
      };
      _grpO createUnit ["O_Soldier_F", _p, [], 0, "NONE"];
    };

    // make them actually fight
    {
      _x allowFleeing 0;
      _x setBehaviourStrong "COMBAT";
      _x setCombatMode "RED";
      _x enableAttack true;
      _x enableGunLights "AUTO";
      _x enableIRLasers true;
      _x setSpeedMode "FULL";
    } forEach [_grpB, _grpO];

    // Force mutual hostility (usually default, but this removes “why aren’t they shooting??” moments)
    west setFriend [east, 0];
    east setFriend [west, 0];

    // Waypoints: both sides push into the arena center and hunt
    private _center = _basePos;

    private _wpB1 = _grpB addWaypoint [_center, 0];
    _wpB1 setWaypointType "SAD";
    _wpB1 setWaypointCompletionRadius (30 + 5 * _intensity);

    private _wpO1 = _grpO addWaypoint [_center, 0];
    _wpO1 setWaypointType "SAD";
    _wpO1 setWaypointCompletionRadius (30 + 5 * _intensity);

    // Optional: keep them “re-energized” briefly (prevents some AI from derping after contact)
    [_grpB, _grpO, _center, _arenaR] spawn {
      params ["_gb","_go","_c","_r"];
      private _t0 = time;
      while {time < _t0 + 60} do {
        if (missionNamespace getVariable ["LEAKTEST_KILL", false]) exitWith {};
        if (isNull _gb || isNull _go) exitWith {};
        // if groups drift too far, shove them back towards the arena
        if ((leader _gb distance2D _c) > _r) then { _gb move _c; };
        if ((leader _go distance2D _c) > _r) then { _go move _c; };
        uiSleep 2;
      };
    };
  };

  // Spawn X combat pairs per cycle
  private _pairsPerCycle = 1 + floor (_intensity / 4);
  for "_p" from 1 to _pairsPerCycle do {
    [_basePos, _intensity, _spawnedGrps] call _spawnCombatPair;
  };

  // Delete oldest groups sometimes (keeps long runs stable)
  private _maxGroups = 8 * _intensity; // note: each “pair” adds 2 groups
  if ((count _spawnedGrps) > _maxGroups) then {
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