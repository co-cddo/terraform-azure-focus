$tfDirs = Get-ChildItem -Path $PSScriptRoot/.. -Filter "*.tf" -Recurse |
Select-Object -ExpandProperty DirectoryName -Unique

foreach ($dir in $tfDirs) {
    Write-Host "Locking providers in $dir"
    Push-Location $dir
    terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
    terraform init --backend=false
    Pop-Location
}
