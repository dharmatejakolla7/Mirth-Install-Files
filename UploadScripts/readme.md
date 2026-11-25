<#
.SYNOPSIS
    Uploads every file and subfolder of a local folder to a new GitHub repository, as one commit.
    Needs nothing but Windows PowerShell 5.1 (or PowerShell 7): no git.

.EXAMPLE
    # See what would be uploaded, without touching GitHub (no token needed)
    .\Upload-FolderToGitHub.ps1 -SourceFolder 'C:\Program Files\Mirth Connect' -RepoName Mirth-Installer-Files -DryRun

.EXAMPLE
    # Create a new private repo and upload the folder, leaving out logs
    .\Upload-FolderToGitHub.ps1 -SourceFolder 'C:\Program Files\Mirth Connect' -RepoName Mirth-Installer-Files -Exclude 'logs','*.log'

.EXAMPLE
    # Replace the contents of an existing repo with the folder (new commit, history is kept)
    .\Upload-FolderToGitHub.ps1 -SourceFolder C:\MirthBuild -RepoName Mirth-Installer-Files -UpdateExisting

.NOTES
    Token: set the GITHUB_TOKEN user environment variable once (or pass -Token). A classic token needs
    the "repo" scope; a fine-grained one needs Administration and Contents read/write.
    GitHub refuses files over 100 MB, and git does not store empty folders.
#>
