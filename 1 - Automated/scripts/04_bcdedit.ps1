# 04_bcdedit.ps1 - Boot configuration to reduce latency
#
# disabledynamictick: Disables the dynamic tick (tickless idle) feature.
#   Normally the OS coalesces timer interrupts and skips ticks during idle periods
#   to save power. This means the timer interrupt rate is variable and can drop
#   well below the requested resolution during brief CPU idle moments within a game
#   frame. Setting disabledynamictick=yes forces a constant TSC-based tick at the
#   full requested timer resolution, reducing jitter in frame-to-frame timing.
#   Slight power consumption increase (irrelevant on a plugged-in gaming PC).
#
# bootmenupolicy legacy: Reverts to the pre-Windows 8 text-mode boot menu.
#   The modern graphical boot menu (default on UEFI systems) requires a full Windows
#   environment to display, which delays the boot menu by loading graphical subsystem
#   components. The legacy text menu is rendered by the bootloader itself and appears
#   immediately after POST.
#   WARNING: Disables the graphical Recovery Environment entry in the boot menu.
#   Recovery options are still accessible via: Settings > Recovery > Advanced startup,
#   or by pressing F8 / Shift+F8 during boot (may require fast boot disabled in UEFI).
#
# Rollback: restore\03_bcdedit.ps1

# Force constant TSC tick (reduces timer latency jitter in games)
bcdedit /set disabledynamictick yes 2>&1 | Out-Null
Write-Host "    disabledynamictick = yes"

# Classic boot menu (faster to display; loses graphical recovery entry)
bcdedit /set bootmenupolicy legacy 2>&1 | Out-Null
Write-Host "    bootmenupolicy = legacy"
