# --- CONFIGURATION ---
$token       = "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"
$owner       = "dharmatejakolla7"
$repo        = "Mirth-Installer-Files"
$localFolder = "C:\Program Files\Mirth Connect" # Path to your Mirth Connect directory

# Configure API Headers
$headers = @{
    "Authorization"        = "Bearer $token"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# Fetch all files recursively (includes all subfolders and files inside them)
Write-Host "Scanning local directory structure..." -ForegroundColor Cyan
$files = Get-ChildItem -Path $localFolder -Recurse -File

Write-Host "Found $($files.Count) files. Starting API upload..." -ForegroundColor Cyan

foreach ($file in $files) {
    # 1. Preserve exact relative path (subfolders/filenames)
    $relativePath = $file.FullName.Substring($localFolder.Length).TrimStart('\', '/').Replace('\', '/')
    
    # 2. Encode file bytes to Base64 (handles text, binaries, JARs, DLLs)
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $base64Content = [System.Convert]::ToBase64String($bytes)

    # 3. Construct API URL for the file path
    $uri = "https://api.github.com/repos/$owner/$repo/contents/$relativePath"

    # 4. Prepare JSON Payload
    $body = @{
        message = "Add $relativePath via PowerShell API"
        content = $base64Content
    } | ConvertTo-Json

    # 5. Upload via HTTP PUT request
    try {
        Write-Host "Uploading: $relativePath ..." -NoNewline
        $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body -ContentType "application/json"
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "API Upload Process Completed!" -ForegroundColor Green