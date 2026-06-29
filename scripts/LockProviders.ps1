$tfDirs = Get-ChildItem -Path $PSScriptRoot/.. -Filter "*.tf" -Recurse |
    Where-Object { $_.FullName -notmatch '[/\\]\.terraform[/\\]' } |
    Select-Object -ExpandProperty DirectoryName -Unique

foreach ($dir in $tfDirs) {
    Write-Host "Locking providers in $dir"
    Push-Location $dir
    Remove-Item -Path "$dir/.terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$dir/.terraform" -Recurse -Force -ErrorAction SilentlyContinue
    terraform init --backend=false
    terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
    Pop-Location
}
