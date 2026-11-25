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
