#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remove Microsoft Edge using the vendored WinUtil uninstall flow.

.DESCRIPTION
    Loads the vendored WinUtil function and runs its Edge removal flow when
    an Edge installer is present.
    WebView2 Runtime is not touched by this script.

    Rollback: restore\opt_edge_restore.ps1 reinstalls Edge via winget.
#>

$VendorFunction = Join-Path $PSScriptRoot 'vendor\winutil\Invoke-WinUtilRemoveEdge.ps1'
if (-not (Test-Path -LiteralPath $VendorFunction)) {
    throw "Missing vendored WinUtil function: $VendorFunction"
}

. $VendorFunction
Invoke-WinUtilRemoveEdge

Write-Host 'WebView2 Runtime: preserved (handled separately by opt_webview2_uninstall.ps1).' -ForegroundColor DarkGray
