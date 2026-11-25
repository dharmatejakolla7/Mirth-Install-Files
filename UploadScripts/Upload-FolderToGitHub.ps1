<#
.SYNOPSIS
    Uploads every file and subfolder of a local folder to a new GitHub repository, as one commit.
    Needs nothing but Windows PowerShell 5.1 (or PowerShell 7): no git.

.DESCRIPTION
    Files larger than -LargeFileMB (default 50 MB) cannot go into the repository itself (GitHub's limit
    is 100 MB per file), so they are uploaded as assets of a GitHub Release (tag -ReleaseTag, up to 2 GB
    per file). The repository gets a .large-files.json listing them, and Download-GitHubRepo.ps1 uses it
    to put each one back at its original path.

.EXAMPLE
    # See what would be uploaded, without touching GitHub (no token needed)
    .\Upload-FolderToGitHub.ps1 -SourceFolder C:\Repo_Personal_Mirth -RepoName Mirth-Setup-Auto -DryRun

.EXAMPLE
    # Create a new private repo and upload the folder, leaving out logs
    .\Upload-FolderToGitHub.ps1 -SourceFolder C:\Repo_Personal_Mirth -RepoName Mirth-Setup-Auto -Exclude 'logs','*.log'

.EXAMPLE
    # Replace the contents of an existing repo with the folder (new commit, history is kept)
    .\Upload-FolderToGitHub.ps1 -SourceFolder C:\Repo_Personal_Mirth -RepoName Mirth-Setup-Auto -UpdateExisting

.NOTES
    Token: set the PERSONAL_GITHUB_TOKEN user environment variable once (or pass -Token). A classic token
    needs the "repo" scope; a fine-grained one needs Administration and Contents read/write.
    Git does not store empty folders.
#>
param(
    [Parameter(Mandatory)] [string]$SourceFolder,
    [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9._-]+$')] [string]$RepoName,
    [string]$Owner,                          # user or organization; default is the token's user
    [string]$Description = '',
    [switch]$Public,                         # default is a private repo
    [string[]]$Exclude = @(),                # wildcards on the relative path or file name, e.g. 'logs','*.log'
    [string]$CommitMessage,
    [switch]$UpdateExisting,                 # allow uploading into a repo that already exists
    [switch]$DryRun,                         # scan and report only
    [ValidateRange(1, 95)] [int]$LargeFileMB = 50,   # files above this go to the release
    [ValidatePattern('^[A-Za-z0-9._-]+$')] [string]$ReleaseTag = 'large-files',
    [string]$Token = $env:PERSONAL_GITHUB_TOKEN
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # the 5.1 progress bar slows web requests down badly
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Api          = 'https://api.github.com'
$ManifestPath = '.large-files.json'           # read by Download-GitHubRepo.ps1; keep the two in step
$LargeBytes   = [long]$LargeFileMB * 1MB
$MaxAssetBytes = 2GB - 1

# --- Helpers ------------------------------------------------------------------

# Reads a file even while another process (e.g. a running service) has it open for writing.
function Read-FileBytes {
    param([string]$Path)
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $buf = New-Object byte[] $fs.Length
        $off = 0
        while ($off -lt $buf.Length) {
            $n = $fs.Read($buf, $off, $buf.Length - $off)
            if ($n -le 0) { throw "File changed while reading: $Path" }
            $off += $n
        }
        , $buf
    }
    finally { $fs.Dispose() }
}

# The id git and GitHub give a file's contents: SHA-1 of "blob <size>\0<bytes>".
function Get-GitBlobSha {
    param([byte[]]$Bytes)
    $sha    = [Security.Cryptography.SHA1]::Create()
    $header = [Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
    [void]$sha.TransformBlock($header, 0, $header.Length, $null, 0)
    [void]$sha.TransformFinalBlock($Bytes, 0, $Bytes.Length)
    -join ($sha.Hash | ForEach-Object { $_.ToString('x2') })
}

function Get-FileSha256 {
    param([string]$Path)
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) }
    finally { $fs.Dispose() }
}

function Get-ResponseHeader {
    param($Response, [string]$Name)
    if (-not $Response) { return $null }
    try { $v = $Response.Headers[$Name]; if ($v) { return "$v" } } catch { }                    # Windows PowerShell 5.1
    try { $vals = $null; if ($Response.Headers.TryGetValues($Name, [ref]$vals)) { return "$(@($vals)[0])" } } catch { }   # PowerShell 7
    $null
}

# Calls the GitHub API. Waits out rate limits and retries network/5xx errors (unless -NoRetry); any
# other error is thrown with the HTTP status in $_.Exception.Data['Status'].
function Invoke-GitHub {
    param([string]$Method, [string]$Path, $Body, [string]$Uri, [string]$InFile, [switch]$NoRetry)
    $Params = @{
        Method          = $Method
        Uri             = if ($Uri) { $Uri } else { "$Api$Path" }
        Headers         = @{
            Authorization          = "Bearer $Token"
            Accept                 = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent'           = 'PowerShell-FolderUploader'
        }
        UseBasicParsing = $true
        TimeoutSec      = 3600
    }
    if ($InFile) {
        $Params['InFile']      = $InFile
        $Params['ContentType'] = 'application/octet-stream'
    }
    elseif ($null -ne $Body) {
        $Json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 -Compress }
        $Params['Body']        = [Text.Encoding]::UTF8.GetBytes($Json)
        $Params['ContentType'] = 'application/json; charset=utf-8'
    }

    for ($Attempt = 1; ; $Attempt++) {
        try { return Invoke-RestMethod @Params }
        catch {
            $Resp    = $_.Exception.Response
            $Status  = if ($Resp) { [int]$Resp.StatusCode } else { $null }
            $Message = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
            $RetryAfter = Get-ResponseHeader $Resp 'Retry-After'
            $Remaining  = Get-ResponseHeader $Resp 'X-RateLimit-Remaining'
            $Reset      = Get-ResponseHeader $Resp 'X-RateLimit-Reset'

            if (-not $NoRetry -and $Status -in 403, 429 -and ($RetryAfter -or $Remaining -eq '0' -or $Message -match 'rate limit')) {
                $Wait = if ($RetryAfter) { [int]$RetryAfter }
                        elseif ($Remaining -eq '0' -and $Reset) { [int]([long]$Reset - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) + 5 }
                        else { 60 }
                $Wait = [Math]::Max($Wait, 5)
                Write-Host "  GitHub rate limit reached; waiting $Wait s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $Wait
                continue
            }
            if (-not $NoRetry -and ($null -eq $Status -or $Status -ge 500) -and $Attempt -lt 5) {
                Write-Host "  $Method $($Params.Uri) failed ($Message); retrying..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds (5 * $Attempt)
                continue
            }
            $Err = New-Object Exception "GitHub API $Method $($Params.Uri) failed (HTTP $Status): $Message"
            $Err.Data['Status'] = $Status
            throw $Err
        }
    }
}

function Get-ReleaseAssets {
    param($ReleaseId)
    $All = @()
    for ($Page = 1; ; $Page++) {
        # Windows PowerShell 5.1 returns a JSON array as one object; ForEach-Object unrolls it (and an empty one to nothing).
        $Batch = @(Invoke-GitHub Get "$RepoPath/releases/$ReleaseId/assets?per_page=100&page=$Page" | ForEach-Object { $_ })
        $All += $Batch
        if ($Batch.Count -lt 100) { return $All }
    }
}

# Uploads one file as a release asset, replacing a broken or different asset of the same name.
function Send-ReleaseAsset {
    param($Release, $File)
    $UploadUrl = ($Release.upload_url -replace '\{.*\}$', '') + "?name=$([uri]::EscapeDataString($File.AssetName))"
    for ($Attempt = 1; ; $Attempt++) {
        $Existing = Get-ReleaseAssets $Release.id | Where-Object { $_.name -eq $File.AssetName } | Select-Object -First 1
        if ($Existing -and $Existing.state -eq 'uploaded' -and [long]$Existing.size -eq $File.Size) { return $Existing }
        if ($Existing) { [void](Invoke-GitHub Delete "$RepoPath/releases/assets/$($Existing.id)") }
        try {
            $Asset = Invoke-GitHub Post -Uri $UploadUrl -InFile $File.FullName -NoRetry
            if ([long]$Asset.size -ne $File.Size) { throw "GitHub stored $($Asset.size) bytes; expected $($File.Size)." }
            return $Asset
        }
        catch {
            if ($Attempt -ge 3) { throw "Uploading $($File.Path) to the release failed: $($_.Exception.Message)" }
            Write-Host "  Upload attempt $Attempt failed ($($_.Exception.Message)); retrying..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds (10 * $Attempt)
        }
    }
}

function Test-Excluded {
    param([string]$RelPath)
    $Name = Split-Path $RelPath -Leaf
    foreach ($p in $ExcludePatterns) {
        if ($RelPath -like $p -or $Name -like $p -or $RelPath -like "$p/*") { return $true }
    }
    $false
}

# Builds each relative path from item names, so it is right however $Root is spelled (e.g. a short 8.3 path).
function Get-FolderFiles {
    param([IO.DirectoryInfo]$Dir, [string]$Prefix)
    foreach ($f in $Dir.GetFiles()) { [PSCustomObject]@{ Rel = "$Prefix$($f.Name)"; Item = $f } }
    foreach ($d in $Dir.GetDirectories()) { Get-FolderFiles $d "$Prefix$($d.Name)/" }
}

# --- 1. Scan the folder (no network) -----------------------------------------

if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) { throw "Folder not found: $SourceFolder" }
$Root = (Resolve-Path -LiteralPath $SourceFolder).ProviderPath.TrimEnd('\')

# "-Exclude a,b" arrives as one string when the script is started with powershell.exe -File.
$ExcludePatterns = @($Exclude | ForEach-Object { $_ -split ',' } | ForEach-Object { ($_.Trim() -replace '\\', '/').Trim('/') } | Where-Object { $_ })
if (-not $CommitMessage) { $CommitMessage = "Upload $(Split-Path $Root -Leaf) ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" }

Write-Host "Scanning $Root ..." -ForegroundColor Yellow
$Files    = New-Object System.Collections.Generic.List[object]   # go into the repository
$Large    = New-Object System.Collections.Generic.List[object]   # go into the release
$TooLarge = New-Object System.Collections.Generic.List[string]
$Skipped  = 0

foreach ($Found in Get-FolderFiles ([IO.DirectoryInfo]$Root) '') {
    $Item = $Found.Item
    $Rel  = $Found.Rel
    if ($Rel -eq '.git' -or $Rel.StartsWith('.git/') -or $Rel -eq $ManifestPath -or (Test-Excluded $Rel)) { $Skipped++; continue }

    if ($Item.Length -gt $MaxAssetBytes) {
        $TooLarge.Add("$Rel ($([math]::Round($Item.Length / 1MB, 1)) MB)")
    }
    elseif ($Item.Length -gt $LargeBytes) {
        $Sha256 = Get-FileSha256 $Item.FullName
        $Large.Add([PSCustomObject]@{
            Path      = $Rel
            FullName  = $Item.FullName
            Size      = $Item.Length
            Sha256    = $Sha256
            # Unique per content, and only characters GitHub keeps unchanged in an asset name.
            AssetName = $Sha256.Substring(0, 12) + '-' + ($Item.Name -replace '[^A-Za-z0-9._-]', '_')
            AssetId   = $null
        })
    }
    else {
        $Files.Add([PSCustomObject]@{
            Path     = $Rel
            FullName = $Item.FullName
            Size     = $Item.Length
            Sha      = Get-GitBlobSha (Read-FileBytes $Item.FullName)
        })
    }
}

$Unique      = @($Files | Group-Object Sha | ForEach-Object { $_.Group[0] })
$LargeGroups = @($Large | Group-Object Sha256)
$RepoMb      = [math]::Round(($Files | Measure-Object Size -Sum).Sum / 1MB, 1)
$LargeMb     = [math]::Round(($Large | Measure-Object Size -Sum).Sum / 1MB, 1)
Write-Host "Found $($Files.Count + $Large.Count) files, $Skipped excluded:" -ForegroundColor Green
Write-Host "  repository: $($Files.Count) files ($RepoMb MB, $($Unique.Count) distinct)" -ForegroundColor Green
Write-Host "  release '$ReleaseTag' (over $LargeFileMB MB): $($Large.Count) files ($LargeMb MB)" -ForegroundColor Green

if ($TooLarge.Count) {
    throw "GitHub does not accept files over 2 GB, even in a release. Exclude or remove these first:`n  $($TooLarge -join "`n  ")"
}
if ($Files.Count + $Large.Count -eq 0) { throw "Nothing to upload in $Root." }

if ($DryRun) {
    if ($Large.Count) {
        Write-Host "`nFiles going to the release:" -ForegroundColor Yellow
        $Large | Sort-Object Size -Descending | ForEach-Object { Write-Host ("  {0,10:N1} MB  {1}" -f ($_.Size / 1MB), $_.Path) }
    }
    Write-Host "`nLargest files going to the repository:" -ForegroundColor Yellow
    $Files | Sort-Object Size -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Host ("  {0,10:N1} MB  {1}" -f ($_.Size / 1MB), $_.Path) }
    Write-Host "`nFiles per top-level folder:" -ForegroundColor Yellow
    ($Files.ToArray() + $Large.ToArray()) | Group-Object { if ($_.Path -match '/') { $_.Path.Split('/')[0] + '/' } else { '(root files)' } } |
        Sort-Object Name | ForEach-Object { Write-Host ("  {0,6}  {1}" -f $_.Count, $_.Name) }
    Write-Host "`nDry run: nothing was uploaded." -ForegroundColor Green
    return
}

if (-not $Token) { throw "No GitHub token. Set the PERSONAL_GITHUB_TOKEN user environment variable or pass -Token." }
$Timer = [Diagnostics.Stopwatch]::StartNew()

# --- 2. Create the repository (or use the existing one) ----------------------

$Login = (Invoke-GitHub Get '/user').login
if (-not $Owner) { $Owner = $Login }
$RepoPath = "/repos/$Owner/$RepoName"

$Repo = $null
try { $Repo = Invoke-GitHub Get $RepoPath }
catch { if ($_.Exception.Data['Status'] -ne 404) { throw } }
$RepoExisted = [bool]$Repo

if ($Repo) {
    if (-not $UpdateExisting) {
        throw "Repository $Owner/$RepoName already exists. Pass -UpdateExisting to replace its contents with this folder in a new commit."
    }
    Write-Host "Using existing repository $($Repo.html_url)" -ForegroundColor Yellow
}
else {
    $Visibility = if ($Public) { 'public' } else { 'private' }
    Write-Host "Creating $Visibility repository $Owner/$RepoName ..." -ForegroundColor Yellow
    $NewRepo   = @{ name = $RepoName; description = $Description; private = (-not $Public); auto_init = $false }
    $CreatePath = if ($Owner -ieq $Login) { '/user/repos' } else { "/orgs/$Owner/repos" }
    $Repo = Invoke-GitHub Post $CreatePath $NewRepo
}
$Branch = $Repo.default_branch
if (-not $Branch) { $Branch = 'main' }

# The git-data API cannot write to a repository with no commits, so an empty one gets a first commit.
$Head = $null
try { $Head = (Invoke-GitHub Get "$RepoPath/git/ref/heads/$Branch").object.sha }
catch { if ($_.Exception.Data['Status'] -notin 404, 409) { throw } }
if (-not $Head) {
    $Init = @{ message = 'Initialize repository'; branch = $Branch
               content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Repository initialized by Upload-FolderToGitHub.ps1`n")) }
    $Head = (Invoke-GitHub Put "$RepoPath/contents/.upload-init" $Init).commit.sha
}

# --- 3. Upload large files to the release, and list them in the manifest -----
# Done before the commit, so a failed upload never leaves the repository pointing at a missing asset.

if ($Large.Count) {
    $Release = $null
    try { $Release = Invoke-GitHub Get "$RepoPath/releases/tags/$ReleaseTag" }
    catch { if ($_.Exception.Data['Status'] -ne 404) { throw } }
    if (-not $Release) {
        Write-Host "Creating release '$ReleaseTag'..." -ForegroundColor Yellow
        $Release = Invoke-GitHub Post "$RepoPath/releases" @{
            tag_name         = $ReleaseTag
            target_commitish = $Branch
            name             = 'Large files'
            body             = "Files over $LargeFileMB MB from this repository. $ManifestPath maps each one to its path; Download-GitHubRepo.ps1 restores them. Do not delete these assets."
        }
    }

    Write-Host "Uploading $($LargeGroups.Count) large files to release '$ReleaseTag'..." -ForegroundColor Yellow
    $i = 0
    foreach ($g in $LargeGroups) {
        $i++
        $f = $g.Group[0]
        Write-Host ("  [{0}/{1}] {2} ({3:N1} MB)" -f $i, $LargeGroups.Count, $f.Path, ($f.Size / 1MB))
        if ((Get-FileSha256 $f.FullName) -ne $f.Sha256) { throw "File changed after the scan: $($f.Path). Run the script again." }
        $Asset = Send-ReleaseAsset $Release $f
        foreach ($m in $g.Group) { $m.AssetId = $Asset.id }
    }

    $Manifest = [ordered]@{
        release = $ReleaseTag
        files   = @($Large | Sort-Object Path | ForEach-Object {
            [ordered]@{ path = $_.Path; asset = $_.AssetName; assetId = $_.AssetId; size = $_.Size; sha256 = $_.Sha256 }
        })
    }
    $ManifestBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Manifest -Depth 5))
    $ManifestSha   = Get-GitBlobSha $ManifestBytes
    $Blob = Invoke-GitHub Post "$RepoPath/git/blobs" @{ encoding = 'base64'; content = [Convert]::ToBase64String($ManifestBytes) }
    if ($Blob.sha -ne $ManifestSha) { throw "GitHub stored $ManifestPath with a different checksum." }
    $Files.Add([PSCustomObject]@{ Path = $ManifestPath; FullName = $null; Size = $ManifestBytes.Length; Sha = $ManifestSha })
}

# --- 4. Upload files and build one tree per folder, deepest folder first -----
# GitHub times out on a single tree request listing every path, so each folder gets its own small one.
# In a repo that already existed (a re-run), each folder's tree is tried before uploading its files:
# it succeeds when GitHub already has them, so they are not sent again.

function Get-ParentPath { param([string]$P) $i = $P.LastIndexOf('/'); if ($i -lt 0) { '' } else { $P.Substring(0, $i) } }
function Get-LeafName   { param([string]$P) $P.Substring($P.LastIndexOf('/') + 1) }

$Children = @{ '' = New-Object System.Collections.Generic.List[object] }   # folder ('' = root) -> its entries
foreach ($f in $Files) {
    $Dir = Get-ParentPath $f.Path
    for ($d = $Dir; -not $Children.ContainsKey($d); $d = Get-ParentPath $d) {
        $Children[$d] = New-Object System.Collections.Generic.List[object]
    }
    $Children[$Dir].Add([PSCustomObject]@{ Name = Get-LeafName $f.Path; Mode = '100644'; Type = 'blob'; Sha = $f.Sha; File = $f })
}
$Dirs = @($Children.Keys | Sort-Object @{ Expression = { ($_ -split '/').Count + [int][bool]$_ }; Descending = $true }, @{ Expression = { $_ } })

$Uploaded = New-Object 'System.Collections.Generic.HashSet[string]'
if ($Large.Count) { [void]$Uploaded.Add($ManifestSha) }

function Send-Blob {
    param($f)
    $Bytes = Read-FileBytes $f.FullName
    if ((Get-GitBlobSha $Bytes) -ne $f.Sha) { throw "File changed after the scan: $($f.Path). Run the script again." }
    $BlobJson = '{"encoding":"base64","content":"' + [Convert]::ToBase64String($Bytes) + '"}'
    $Bytes = $null
    $Blob = Invoke-GitHub Post "$RepoPath/git/blobs" $BlobJson
    if ($Blob.sha -ne $f.Sha) { throw "GitHub stored $($f.Path) with a different checksum ($($Blob.sha) vs $($f.Sha))." }
    [void]$Uploaded.Add($f.Sha)
}

Write-Host "Uploading $($Unique.Count) files in $($Dirs.Count) folders to $Owner/$RepoName ($Branch)..." -ForegroundColor Yellow
$i = 0
$Sent = 0
$RootTree = $null
foreach ($Dir in $Dirs) {
    $i++
    $Entries = $Children[$Dir]
    $Body    = @{ tree = @($Entries | ForEach-Object { @{ path = $_.Name; mode = $_.Mode; type = $_.Type; sha = $_.Sha } }) }
    $Label   = if ($Dir) { $Dir } else { '(root)' }

    $Tree = $null
    if ($RepoExisted) {
        try { $Tree = Invoke-GitHub Post "$RepoPath/git/trees" $Body }
        catch { if ($_.Exception.Data['Status'] -ne 422) { throw } }   # 422: some files are not on GitHub yet
    }
    if ($Tree) {
        Write-Host ("  [{0}/{1}] {2}: already on GitHub" -f $i, $Dirs.Count, $Label)
    }
    else {
        $ToSend = @($Entries | Where-Object { $_.File -and -not $Uploaded.Contains($_.Sha) })
        Write-Host ("  [{0}/{1}] {2}: uploading {3} files" -f $i, $Dirs.Count, $Label, $ToSend.Count)
        foreach ($e in $ToSend) {
            if ($Uploaded.Contains($e.Sha)) { continue }   # same content twice in one folder
            Send-Blob $e.File
            $Sent++
        }
        $Tree = Invoke-GitHub Post "$RepoPath/git/trees" $Body
    }

    if ($Dir) {
        $Children[(Get-ParentPath $Dir)].Add([PSCustomObject]@{ Name = Get-LeafName $Dir; Mode = '040000'; Type = 'tree'; Sha = $Tree.sha; File = $null })
    }
    else { $RootTree = $Tree.sha }
}
Write-Host "Uploaded $Sent files." -ForegroundColor Green

# --- 5. Commit ----------------------------------------------------------------

Write-Host "Creating commit..." -ForegroundColor Yellow
$Commit  = Invoke-GitHub Post "$RepoPath/git/commits" @{ message = $CommitMessage; tree = $RootTree; parents = @($Head) }
[void](Invoke-GitHub Patch "$RepoPath/git/refs/heads/$Branch" @{ sha = $Commit.sha; force = $false })

# --- 6. Verify ----------------------------------------------------------------

$Check = Invoke-GitHub Get "$RepoPath/git/trees/$($Commit.sha)?recursive=1"
$Count = @($Check.tree | Where-Object { $_.type -eq 'blob' }).Count
if ($Check.truncated) {
    Write-Host "GitHub truncated the verification listing; file count not checked." -ForegroundColor DarkYellow
}
elseif ($Count -ne $Files.Count) {
    throw "Commit $($Commit.sha) holds $Count files; expected $($Files.Count)."
}

$Summary = "$($Files.Count) files committed to $($Repo.html_url) ($Branch, commit $($Commit.sha.Substring(0, 7)))"
if ($Large.Count) { $Summary += ", $($Large.Count) large files in release '$ReleaseTag'" }
Write-Host "Done in $([int]$Timer.Elapsed.TotalSeconds) s: $Summary." -ForegroundColor Green
