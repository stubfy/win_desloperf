7 - NVINSPECTOR
NVIDIA driver profiles and NIS / DLSS settings
================================================

USING NVPI-R
-------------
1. Open NVPI-Revamped\NVPI-R.exe
2. Select a profile from the dropdown list (e.g. Base Profile,
   or create a per-game profile via "Add Profile")
3. Modify the desired settings across the tabs (Sync, Antialiasing,
   Texture Filtering, etc.)
4. Click "Apply Changes" to save the profile to the driver

NVPI-R writes directly to the NVIDIA driver profile store (nvdrsdb.bin)
via NvAPI. Changes are persistent and apply to all sessions regardless of
user.


.REG FILES PROVIDED
--------------------

1. Disable DLSS UI.reg
   Disables the DLSS on-screen indicator (in-game "DLSS" overlay).
   Key : HKLM\SOFTWARE\NVIDIA Corporation\Global\NGXCore
   Value : ShowDlssIndicator = 0

2. Enable DLSS UI.reg
   Re-enables the DLSS indicator (for diagnostic purposes).
   Value : ShowDlssIndicator = 0x400

3. New NIS [Default].reg
   Enables the new NIS algorithm (NVIDIA Image Scaling v2).
   Key : HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Parameters\FTS
   Value : EnableGR535 = 1
   Compatible : RTX 20 series GPUs and newer.
   NIS is a spatial super-resolution algorithm based on DLSS 2
   (adaptive neural network) ; it produces sharper output than the
   previous version, especially at low scale ratios.

4. Old NIS.reg
   Enables the legacy NIS algorithm.
   Value : EnableGR535 = 0
   Compatible : GTX 10 series GPUs and older.

Apply one or the other depending on GPU generation. Do not apply both
simultaneously. A reboot is not required but recommended so that the
driver reinitializes the NIS pipeline.

Note : NIS must be enabled in the NVIDIA Control Panel or NVIDIA App before
the .reg files take effect (NIS requires a display refresh that NVPI-R
does not perform).


NIS SHARPNESS BY GAME
----------------------
Recommended sharpness value :
  New NIS (EnableGR535=1) : 10 to 30%
  Old NIS (EnableGR535=0) : 10 to 30% (if denoise at 0%)
                             35 to 55% (if denoise at 40%)


ROLLBACK
--------
Apply the inverse .reg values (ShowDlssIndicator=0 by default,
delete the EnableGR535 key). NVPI-R can restore default profiles
via "Reset Profile".


WHAT IT DOES
------------
NVIDIA Profile Inspector Revamped (NVPI-R) exposes the full set of NVIDIA
driver parameters, including those not available in the standard NVIDIA
Control Panel or NVIDIA App. It allows creating and modifying per-game
profiles with advanced rendering, synchronization and latency options.

The .reg files provided in this folder configure specific DLSS and NIS
options independently of NVPI-R.
