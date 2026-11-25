<#
.SYNOPSIS
    Downloads a GitHub repository, or only some of its folders, into a local folder.
    Needs nothing but Windows PowerShell 5.1 (or PowerShell 7): no git.

.EXAMPLE
    .\Download-GitHubRepo.ps1 -Repo Mirth-Installer-Files -Destination C:\MirthInstaller

.EXAMPLE
    # Only two folders of the repo
    .\Download-GitHubRepo.ps1 -Repo Mirth-Installer-Files -Destination C:\MirthInstaller -Folder 'Empty SqlServer DB','server-lib'

.NOTES
    Existing files in Destination are overwritten; files that are not in the repo are left alone.
    Files that Upload-FolderToGitHub.ps1 put in a release (listed in .large-files.json) are downloaded
    from the release and placed at their original paths.
    For a private repo, set the PERSONAL_GITHUB_TOKEN user environment variable (or pass -Token).
#>
param(
    [Parameter(Mandatory)] [string]$Repo,
    [Parameter(Mandatory)] [string]$Destination,
    [string]$Owner    = 'dharmatejakolla7',
    [string]$Branch   = 'main',
    [string[]]$Folder,                       # repo folders to download; default is the whole repo
    [string]$Token    = $env:PERSONAL_GITHUB_TOKEN,   # only needed for a private repo
    [int]$Retries     = 3
)

$ErrorActionPreference = 'Stop'
# The Windows PowerShell 5.1 progress bar slows Invoke-WebRequest down 10-50x, long enough for
# GitHub to drop the connection ("unexpected EOF ... from the transport stream").
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$RepoApi      = "https://api.github.com/repos/$Owner/$Repo"
$Url          = "$RepoApi/zipball/$Branch"
$ManifestPath = '.large-files.json'   # written by Upload-FolderToGitHub.ps1; keep the two in step
$Headers = @{ 'User-Agent' = 'PowerShell-RepoDownloader' }
if ($Token) { $Headers['Authorization'] = "Bearer $Token" }

$Zip      = Join-Path ([IO.Path]::GetTempPath()) "$Repo-$Branch-$([guid]::NewGuid().ToString('N')).zip"
$DestRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
# "-Folder a,b" arrives as one string when the script is started with powershell.exe -File.
$Folder   = @($Folder | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Prefixes = @($Folder | ForEach-Object { ($_ -replace '\\', '/').Trim('/') + '/' })
$Archive  = $null

function Get-FileSha256 {
    param([string]$Path)
    $fs = [IO.File]::OpenRead($Path)
    try { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) }
    finally { $fs.Dispose() }
}

function Get-SafeTarget {
    param([string]$Rel)
    $Target = [IO.Path]::GetFullPath((Join-Path $DestRoot $Rel))
    if (-not $Target.StartsWith($DestRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to write outside $DestRoot : $Rel" }
    $Target
}

function Test-Wanted {
    param([string]$Rel)
    -not $Prefixes.Count -or [bool]($Prefixes | Where-Object { $Rel.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })
}

try {
    # --- Download (whole zip in one request; retried because GitHub builds it on the fly and can drop it) ---
    for ($Attempt = 1; ; $Attempt++) {
        try {
            Write-Host "Downloading $Owner/$Repo ($Branch), attempt $Attempt of $Retries..." -ForegroundColor Yellow
            $Timer = [Diagnostics.Stopwatch]::StartNew()
            Invoke-WebRequest -Uri $Url -Headers $Headers -OutFile $Zip -UseBasicParsing -TimeoutSec 900
            $Archive = [IO.Compression.ZipFile]::OpenRead($Zip)   # fails on a truncated download
            $SizeMb  = [math]::Round((Get-Item $Zip).Length / 1MB, 1)
            Write-Host "Downloaded $SizeMb MB in $([int]$Timer.Elapsed.TotalSeconds) s." -ForegroundColor Green
            break
        }
        catch {
            $Status = $null
            if ($_.Exception.Response) { $Status = [int]$_.Exception.Response.StatusCode }
            if (Test-Path $Zip) { Remove-Item $Zip -Force }

            if ($Status -eq 404) { throw "Repo $Owner/$Repo or branch '$Branch' not found (HTTP 404). A private repo also returns 404 without a valid token." }
            if ($Status -in 401, 403) { throw "GitHub refused the download (HTTP $Status). Check the token, or the anonymous API limit of 60 requests/hour." }
            if ($Attempt -ge $Retries) { throw "Download failed after $Retries attempts: $($_.Exception.Message)" }

            Write-Host "Attempt $Attempt failed: $($_.Exception.Message) Retrying..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds (5 * $Attempt)
        }
    }

    # --- Extract (zip entries are "<owner>-<repo>-<sha>/<path>"; that top folder is dropped) ---
    Write-Host "Extracting to $DestRoot ..." -ForegroundColor Yellow
    $Count    = 0
    $Manifest = $null
    foreach ($Entry in $Archive.Entries) {
        $Rel = $Entry.FullName.Substring($Entry.FullName.IndexOf('/') + 1)
        if (-not $Rel -or $Rel.EndsWith('/')) { continue }
        if ($Rel -eq $ManifestPath) {
            $Reader = New-Object IO.StreamReader($Entry.Open())
            try { $Manifest = $Reader.ReadToEnd() | ConvertFrom-Json } finally { $Reader.Dispose() }
            continue
        }
        if (-not (Test-Wanted $Rel)) { continue }

        $Target = Get-SafeTarget $Rel
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
        [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Target, $true)
        $Count++
    }

    # --- Large files: download from the release named in the manifest ---
    $LargeFiles = @(if ($Manifest) { $Manifest.files | Where-Object { Test-Wanted $_.path } })
    if ($LargeFiles.Count) {
        Write-Host "Downloading $($LargeFiles.Count) large files from release '$($Manifest.release)'..." -ForegroundColor Yellow
        $Release = Invoke-RestMethod "$RepoApi/releases/tags/$($Manifest.release)" -Headers $Headers -UseBasicParsing
        $AssetIds = @{}
        foreach ($a in $Release.assets) { $AssetIds[$a.name] = $a.id }

        $i = 0
        foreach ($f in $LargeFiles) {
            $i++
            $Target = Get-SafeTarget $f.path
            if ((Test-Path -LiteralPath $Target) -and (Get-Item -LiteralPath $Target).Length -eq [long]$f.size -and (Get-FileSha256 $Target) -eq $f.sha256) {
                Write-Host ("  [{0}/{1}] {2}: already present" -f $i, $LargeFiles.Count, $f.path)
                $Count++
                continue
            }
            $AssetId = $AssetIds[$f.asset]
            if (-not $AssetId) { throw "Release '$($Manifest.release)' has no asset '$($f.asset)' for $($f.path)." }
            Write-Host ("  [{0}/{1}] {2} ({3:N1} MB)" -f $i, $LargeFiles.Count, $f.path, ($f.size / 1MB))

            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
            $Part = "$Target.part"
            $AssetHeaders = $Headers.Clone()
            $AssetHeaders['Accept'] = 'application/octet-stream'
            for ($Attempt = 1; ; $Attempt++) {
                try {
                    Invoke-WebRequest -Uri "$RepoApi/releases/assets/$AssetId" -Headers $AssetHeaders -OutFile $Part -UseBasicParsing -TimeoutSec 3600
                    if ((Get-FileSha256 $Part) -ne $f.sha256) { throw "checksum does not match the manifest" }
                    break
                }
                catch {
                    if (Test-Path -LiteralPath $Part) { Remove-Item -LiteralPath $Part -Force }
                    if ($Attempt -ge $Retries) { throw "Downloading $($f.path) failed after $Retries attempts: $($_.Exception.Message)" }
                    Write-Host "  Attempt $Attempt failed: $($_.Exception.Message) Retrying..." -ForegroundColor DarkYellow
                    Start-Sleep -Seconds (5 * $Attempt)
                }
            }
            Move-Item -LiteralPath $Part -Destination $Target -Force
            $Count++
        }
    }

    if ($Count -eq 0) {
        if ($Prefixes.Count) { throw "None of the folders were found in the repo: $($Folder -join ', ')" }
        throw "The repo archive contained no files."
    }
    Write-Host "Done: $Count files written to $DestRoot" -ForegroundColor Green
}
finally {
    if ($Archive) { $Archive.Dispose() }
    if (Test-Path $Zip) { Remove-Item $Zip -Force }
}
