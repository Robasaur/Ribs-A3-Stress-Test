class LeakHarnessDialog
{
  idd = 8800;
  movingEnable = 1;
  enableSimulation = 1;

  onLoad = "uiNamespace setVariable ['LH_ui', _this select 0]; [] call LH_fnc_uiInit;";

  class controlsBackground
  {
    class BG: RscText
    {
      idc = 8801;
      x = 0.27;
      y = 0.17;
      w = 0.46;
      h = 0.70;
      colorBackground[] = {0,0,0,0.75};
    };

    class Title: RscText
    {
      idc = 8802;
      text = "Ribs Leak/Stress Control Panel";
      x = 0.27;
      y = 0.13;
      w = 0.46;
      h = 0.04;
      colorBackground[] = {0.1,0.1,0.1,0.9};
      style = 2;
    };
  };

  class controls
  {
    class DurationLabel: RscText
    {
      idc = 8810;
      text = "Duration (sec)";
      x = 0.32; y = 0.235;
      w = 0.18; h = 0.03;
    };

    class DurationEdit: RscEdit
    {
      idc = 8811;
      text = "900";
      x = 0.52; y = 0.235;
      w = 0.16; h = 0.03;
    };

    class CycleLabel: RscText
    {
      idc = 8820;
      text = "Cycle (sec)";
      x = 0.32; y = 0.275;
      w = 0.18; h = 0.03;
    };

    class CycleEdit: RscEdit
    {
      idc = 8821;
      text = "10";
      x = 0.52; y = 0.275;
      w = 0.16; h = 0.03;
    };

    class IntensityLabel: RscText
    {
      idc = 8830;
      text = "Intensity (1-10)";
      x = 0.32; y = 0.320;
      w = 0.36; h = 0.03;
    };

    class IntensitySlider: RscSlider
    {
      idc = 8831;
      x = 0.32; y = 0.355;
      w = 0.36; h = 0.03;
    };

    class IntensityValue: RscText
    {
      idc = 8832;
      text = "5";
      x = 0.32; y = 0.390;
      w = 0.36; h = 0.03;
      style = 2;
    };

    class StartBtn: RscButton
    {
      idc = 8840;
      text = "Start (Server)";
      x = 0.32; y = 0.445;
      w = 0.17; h = 0.045;
      action = "[] call LH_fnc_uiStart;";
    };

    class StopBtn: RscButton
    {
      idc = 8841;
      text = "Stop";
      x = 0.51; y = 0.445;
      w = 0.17; h = 0.045;
      action = "[] call LH_fnc_uiStop;";
    };

    class CloseBtn: RscButton
    {
      idc = 8842;
      text = "Close";
      x = 0.32; y = 0.505;
      w = 0.36; h = 0.045;
      action = "closeDialog 0;";
    };

    class HintText: RscText
    {
      idc = 8850;
      text = "Stop sets LEAKTEST_KILL=true. Check RPT for [LEAKHARNESS].";
      x = 0.32; y = 0.565;
      w = 0.36; h = 0.04;
      style = 2;
      sizeEx = 0.028;
    };

    class StatsBG: RscText
    {
      idc = 8860;
      x = 0.30;
      y = 0.62;
      w = 0.40;
      h = 0.22;    // was 0.17
      colorBackground[] = {0,0,0,0.35};
    };

    class StatsText: RscText
    {
      idc = 8861;
      x = 0.31;
      y = 0.63;
      w = 0.38;
      h = 0.20;
      sizeEx = 0.032;
      style = 16;
      text = "Stats: (waiting...)";
    };
  };
};