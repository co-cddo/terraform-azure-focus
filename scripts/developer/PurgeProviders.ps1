Get-ChildItem -Hidden -Recurse -Directory -Filter '.terraform' |
Remove-Item -Recurse -Force

Get-ChildItem -Hidden -Recurse -File -Filter '.terraform.lock.hcl' |
Remove-Item -Recurse -Force
