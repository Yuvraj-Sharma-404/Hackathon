<#
.SYNOPSIS
    Prepares a clean deployment package of RAISE for Raspberry Pi.
.DESCRIPTION
    Creates a zip archive or copies files to a USB flash drive, ensuring proper Unix line endings
    and excluding unnecessary development artifacts.
#>

param(
    [string]$DestinationPath = "$PSScriptRoot\..\..\raise-pi-kiosk.zip"
)

$ErrorActionPreference = "Stop"

$sourceDir = Resolve-Path "$PSScriptRoot\.."
Write-Host "Packaging RAISE Kiosk from: $sourceDir" -ForegroundColor Cyan

# Files/Folders to include
$excludeItems = @(".git", ".gitignore", "*.bak", "*.tmp")

if ($DestinationPath.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path $DestinationPath) {
        Remove-Item -Force $DestinationPath
    }
    
    Write-Host "Creating zip package at: $DestinationPath" -ForegroundColor Yellow
    
    # Create temp directory to stage clean files
    $guid = [System.Guid]::NewGuid().ToString()
    $tempStage = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "raise-pi-stage-$guid")
    New-Item -ItemType Directory -Path $tempStage -Force | Out-Null
    
    try {
        # Copy files to stage
        Copy-Item -Path "$sourceDir\*" -Destination $tempStage -Recurse -Exclude $excludeItems -Force
        
        # Ensure all shell and python scripts have Unix LF line endings
        Get-ChildItem -Path $tempStage -Recurse -Include *.sh, *.py | ForEach-Object {
            $content = [System.IO.File]::ReadAllText($_.FullName)
            if ($content.Contains("`r`n")) {
                $content = $content.Replace("`r`n", "`n")
                [System.IO.File]::WriteAllText($_.FullName, $content, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        
        # Compress
        Compress-Archive -Path "$tempStage\*" -DestinationPath $DestinationPath -CompressionLevel Optimal
        Write-Host "Package successfully created at: $DestinationPath" -ForegroundColor Green
    }
    finally {
        if (Test-Path $tempStage) {
            Remove-Item -Path $tempStage -Recurse -Force
        }
    }
} else {
    # Directory destination (e.g. USB Drive letter E:\)
    Write-Host "Copying directly to: $DestinationPath" -ForegroundColor Yellow
    if (!(Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }
    Copy-Item -Path "$sourceDir\*" -Destination $DestinationPath -Recurse -Exclude $excludeItems -Force
    
    Get-ChildItem -Path $DestinationPath -Recurse -Include *.sh, *.py | ForEach-Object {
        $content = [System.IO.File]::ReadAllText($_.FullName)
        if ($content.Contains("`r`n")) {
            $content = $content.Replace("`r`n", "`n")
            [System.IO.File]::WriteAllText($_.FullName, $content, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
    Write-Host "Files copied and formatted for Linux at: $DestinationPath" -ForegroundColor Green
}
