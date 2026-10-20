[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptRoot 'RCloudTools.config'
$backupRoot = Join-Path $scriptRoot 'Backups'

function Get-ProfileRecords {
	$records = [System.Collections.Generic.List[object]]::new()
	$excludedRoot = [IO.Path]::GetFullPath($backupRoot).TrimEnd('\')
	$roots = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }

	foreach ($driveRoot in $roots) {
		Write-Host "Scanning $driveRoot ..."
		$allDirectories = @(Get-ChildItem -LiteralPath $driveRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
			Where-Object { $_.FullName -notlike "$excludedRoot\*" })

		foreach ($profilesDirectory in $allDirectories | Where-Object { $_.Name -ieq 'Profiles' }) {
			if ($profilesDirectory.FullName -notmatch '(?i)Rockstar Games') { continue }

			$category = if ($profilesDirectory.FullName -match '(?i)(^|[\\/])Launcher([\\/]|$)') {
				'Launcher'
			} else {
				'Rockstar profile'
			}

			foreach ($profileDirectory in @(Get-ChildItem -LiteralPath $profilesDirectory.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
				$files = @(Get-ChildItem -LiteralPath $profileDirectory.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)
				$records.Add([PSCustomObject]@{
					Category = $category
					ProfilesDirectory = $profilesDirectory.FullName
					Path = $profileDirectory.FullName
					FileCount = $files.Count
					Bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
				})
			}
		}
	}

	@($records | Sort-Object Category, Path -Unique)
}

function Save-Records($records) {
	[PSCustomObject]@{
		LastScan = (Get-Date).ToString('o')
		Locations = @($records)
	} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Load-Records {
	if (-not (Test-Path -LiteralPath $configPath)) { return @() }
	try {
		$saved = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
		return @($saved.Locations)
	} catch {
		return @()
	}
}

function Clear-PendingKeys {
	try {
		while ([Console]::KeyAvailable) {
			[Console]::ReadKey($true) | Out-Null
		}
	} catch {
	}
}

function Get-MenuChoice([string]$title, [string[]]$labels) {
	while ($true) {
		Write-Host $title -ForegroundColor Gray
		for ($index = 0; $index -lt $labels.Count; $index++) {
			Write-Host ("[{0}] {1}" -f ($index + 1), $labels[$index]) -ForegroundColor Gray
		}

		$key = [Console]::ReadKey($true)
		$keyCharacter = [string]$key.KeyChar

		if ($keyCharacter -match '^[1-9]$') {
			$selected = [int]$keyCharacter - 1
			if ($selected -lt $labels.Count) { return $selected }
		}
	}
}

function Show-Records($records) {
	if (-not $records -or @($records).Count -eq 0) {
		Write-Host 'No Rockstar profile locations were found.' -ForegroundColor Yellow
		return
	}

	foreach ($category in @('Rockstar profile', 'Launcher')) {
		$group = @($records | Where-Object Category -eq $category)
		Write-Host "`n$category data ($($group.Count) location(s))" -ForegroundColor Cyan
		foreach ($record in $group) {
			$size = '{0:N0}' -f $record.Bytes
			Write-Host "  $($record.Path) [$($record.FileCount) file(s), $size bytes]"
		}
	}
}

function Backup-Records($records, [string]$category) {
	$targets = @($records | Where-Object Category -eq $category | Where-Object { Test-Path -LiteralPath $_.Path })
	if ($targets.Count -eq 0) {
		Write-Host "No $category data is currently available." -ForegroundColor Yellow
		return
	}

	Show-Records $targets
	$answer = Get-MenuChoice "Move this data into a backup under '$backupRoot'?" @('Move data', 'Cancel')
	if ($answer -ne 0) { Write-Host 'Cancelled.'; return }

	$session = Join-Path $backupRoot ('Backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
	New-Item -ItemType Directory -Path $session -Force | Out-Null
	$manifest = [System.Collections.Generic.List[object]]::new()

	foreach ($record in $targets) {
		$source = [IO.Path]::GetFullPath($record.Path)
		$root = [IO.Path]::GetPathRoot($source)
		$relative = $source.Substring($root.Length).TrimStart('\').Replace(':', '_')
		$destination = Join-Path (Join-Path $session $root.TrimEnd('\').Replace(':', '')) $relative
		New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null

		try {
			Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Stop
			if (-not (Test-Path -LiteralPath $destination)) { throw 'Backup verification failed.' }
			Remove-Item -LiteralPath $source -Recurse -Force -ErrorAction Stop
			$manifest.Add([PSCustomObject]@{ Original = $source; Backup = $destination; Category = $category })
			Write-Host "Backed up and moved: $source" -ForegroundColor Green
		} catch {
			Write-Host "Could not move $source : $($_.Exception.Message)" -ForegroundColor Red
		}
	}

	$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $session 'manifest.json') -Encoding UTF8
	Write-Host "Backup created at: $session" -ForegroundColor Green
}

function Remove-Backups {
	$backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue)
	if ($backups.Count -eq 0) { Write-Host 'No backups were found.' -ForegroundColor Yellow; return }
	$backups | ForEach-Object { Write-Host "  $($_.FullName)" }
	$answer = Get-MenuChoice 'Permanently delete all listed backups?' @('Delete backups', 'Cancel')
	if ($answer -ne 0) { Write-Host 'Cancelled.'; return }
	Remove-Item -LiteralPath $backupRoot -Recurse -Force
	Write-Host 'Backups permanently deleted.' -ForegroundColor Green
}

if (Test-Path -LiteralPath $configPath) {
	$records = Load-Records
	Clear-PendingKeys
	$scanChoice = Get-MenuChoice 'A previous scan was found. What would you like to do?' @(
		'Rescan all drives'
		'Use the previous scan'
	)
	if ($scanChoice -eq 0) {
		$records = Get-ProfileRecords
		Save-Records $records
	}
} else {
	$records = Get-ProfileRecords
	Save-Records $records
}
Clear-PendingKeys

while ($true) {
	Clear-Host
	Write-Host 'R* Cloud Tools' -ForegroundColor Cyan
	Write-Host "Last scan saved to: $configPath"
	Show-Records $records
	$choice = Get-MenuChoice 'Select an option' @(
		'Clear Rockstar profile data (fix cloud save sync)'
		'Clear Rockstar Launcher data'
		'Delete backups permanently'
		'Rescan all drives'
		'Exit'
	)

	switch ($choice) {
		0 { Backup-Records $records 'Rockstar profile'; Get-MenuChoice 'Continue' @('Return to menu') | Out-Null }
		1 { Backup-Records $records 'Launcher'; Get-MenuChoice 'Continue' @('Return to menu') | Out-Null }
		2 { Remove-Backups; Get-MenuChoice 'Continue' @('Return to menu') | Out-Null }
		3 { $records = Get-ProfileRecords; Save-Records $records }
		4 { exit 0 }
	}
}
