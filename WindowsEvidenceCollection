$Out="E:\IR-$(hostname)-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $Out | Out-Null
Start-Transcript "$Out\powershell_transcript.txt"

hostname | Out-File "$Out\hostname.txt"
Get-Date -Format o | Out-File "$Out\collection_time.txt"
whoami /all > "$Out\whoami_all.txt"
systeminfo > "$Out\systeminfo.txt"
ipconfig /all > "$Out\ipconfig_all.txt"
route print > "$Out\routes.txt"
arp -a > "$Out\arp.txt"
netstat -ano > "$Out\netstat_ano.txt"
netstat -abno > "$Out\netstat_abno.txt" 2>&1
Get-NetTCPConnection | Sort-Object State,LocalPort | Export-Csv "$Out\net_tcp_connections.csv" -NoTypeInformation

tasklist /v > "$Out\tasklist_v.txt"
tasklist /svc > "$Out\tasklist_svc.txt"
Get-Process | Select Name,Id,Path,StartTime,Company,Description |
  Export-Csv "$Out\processes.csv" -NoTypeInformation

Get-Service | Sort Status,Name | Export-Csv "$Out\services.csv" -NoTypeInformation
Get-ScheduledTask | Export-Csv "$Out\scheduled_tasks.csv" -NoTypeInformation
schtasks /query /fo LIST /v > "$Out\schtasks_verbose.txt"

net user > "$Out\net_users.txt"
net localgroup administrators > "$Out\local_admins.txt"
net share > "$Out\net_shares.txt"
net use > "$Out\net_use.txt"
quser > "$Out\logged_on_users.txt" 2>&1
qwinsta > "$Out\sessions.txt" 2>&1

Get-SmbSession > "$Out\smb_sessions.txt" 2>&1
Get-SmbOpenFile > "$Out\smb_open_files.txt" 2>&1

Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" |
  Out-File "$Out\hklm_run.txt"
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" |
  Out-File "$Out\hkcu_run.txt"

Get-MpComputerStatus > "$Out\defender_status.txt" 2>&1
Get-MpThreatDetection > "$Out\defender_detections.txt" 2>&1
Get-BitLockerVolume > "$Out\bitlocker.txt" 2>&1

Get-Volume | Export-Csv "$Out\volumes.csv" -NoTypeInformation
Get-PSDrive | Out-File "$Out\psdrives.txt"
vssadmin list shadows > "$Out\vss_shadows.txt" 2>&1
wmic shadowcopy list brief > "$Out\wmic_shadowcopies.txt" 2>&1

wevtutil el > "$Out\event_logs_list.txt"
wevtutil qe Security /c:200 /f:text /rd:true > "$Out\Security_last200.txt"
wevtutil qe System /c:200 /f:text /rd:true > "$Out\System_last200.txt"
wevtutil qe Application /c:200 /f:text /rd:true > "$Out\Application_last200.txt"
wevtutil qe "Microsoft-Windows-Sysmon/Operational" /c:200 /f:text /rd:true > "$Out\Sysmon_last200.txt" 2>&1
wevtutil qe "Microsoft-Windows-PowerShell/Operational" /c:200 /f:text /rd:true > "$Out\PowerShell_last200.txt" 2>&1

Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
              "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Force |
  Out-File "$Out\startup_folders.txt"

Get-FileHash "$Out\*" -Algorithm SHA256 |
  Export-Csv "$Out\collection_hashes.csv" -NoTypeInformation

Stop-Transcript
