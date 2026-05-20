function Invoke-WinUtilRemoveEdge {
  $Path = @(
    Get-ChildItem -Path "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$Env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue
  ) | Select-Object -First 1

  if (-not $Path) {
    Write-Host "Microsoft Edge installer not found; Edge appears already removed." -ForegroundColor Yellow
    return
  }

  New-Item -Path "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" -Force | Out-Null
  Start-Process -FilePath $Path.FullName -ArgumentList '--uninstall --system-level --force-uninstall --delete-profile' -Wait

  Write-Host "Microsoft Edge was removed" -ForegroundColor Green
}
