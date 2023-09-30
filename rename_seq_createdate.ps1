$files = Get-ChildItem -Path .\*.mp4 | Sort-Object CreationTime
$i = 1
foreach ($file in $files) {
    $newName = "{0:D1}. {1}" -f $i, $file.Name
    Rename-Item -Path $file.FullName -NewName $newName
    $i++
}
