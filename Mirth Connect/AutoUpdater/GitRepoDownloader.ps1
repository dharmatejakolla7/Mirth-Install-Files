# 1. Define your details
$token = "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"#"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"
$username = "dharmatejakolla7"
$repo = "Mirth-4.5.2-Personal"
$branch = "main" # Change to master if your default branch is master

# 2. Setup the authentication headers
$headers = @{
    "Authorization" = "token $token"
    "Accept"        = "application/vnd.github.v3.raw"
}

# 3. Target URL for the repository ZIP source
$sourceUrl = "https://github.com/$username/$repo/archive/refs/heads/$branch.zip"
$destinationZip = "C:\Users\$env:USERNAME\Downloads\MirthGitRepo.zip"
$extractPath = "C:\Users\$env:USERNAME\Downloads\MirthGitRepo-extracted"
Write-Host "Connecting the EndPoint: $sourceUrl" -Foregroundcolor Yellow
# 4. Download the private ZIP file safely using the authentication headers
Write-Host "Command being used: Invoke-WebRequest -Uri $sourceUrl -Headers $headers -OutFile $destinationZip" -Foregroundcolor Yellow

try{
    Invoke-WebRequest -Uri $sourceUrl -Headers $headers -OutFile $destinationZip -ErrorAction Stop
}catch{
    Write-Host "Unable to download the Git Repo due to $_ Check the connection/endpoint" -ForegroundColor Red
    exit 1
}

Write-Host "Downloaded Git Repo at: $destinationZip" -Foregroundcolor Yellow

Write-Host "Extracting the Git Repo" -Foregroundcolor Yellow
# 5. Extract the downloaded archive
try{
    Expand-Archive -Path $destinationZip -DestinationPath $extractPath -Force
}catch{
    Write-Host "FAILED to extract the downloaded repository to: $extractPath" -Foregroundcolor Red
    exit 1
}
Write-Host "Success! Your private repository has been securely downloaded and extracted to $extractPath" -ForegroundColor Green

exit 0