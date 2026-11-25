function Get-GitRepo {
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
    $destinationZip = "C:\Users\DharmaTeja.Kolla\Downloads\MirthGitRepo.zip"
    $extractPath = "C:\Users\DharmaTeja.Kolla\Downloads\MirthGitRepo-extracted"
    Write-Host "Connecting the EndPoint: $sourceUrl" -Foregroundcolor Yellow
    # 4. Download the private ZIP file safely using the authentication headers
    Write-Host "Command being used: Invoke-WebRequest -Uri $sourceUrl -Headers $headers -OutFile $destinationZip" -Foregroundcolor Yellow

    try{
        Invoke-WebRequest -Uri $sourceUrl -Headers $headers -OutFile $destinationZip -ErrorAction Stop
    }catch{
        Write-Host "Unable to download the Git Repo due to $_ Check the connection/endpoint" -ForegroundColor Red
        # exit 1
        throw "$($_.Exception.Message)"
    }

    Write-Host "Downloaded Git Repo at: $destinationZip" -Foregroundcolor Yellow

    Write-Host "Extracting the Git Repo" -Foregroundcolor Yellow
    # 5. Extract the downloaded archive
    try{
        Expand-Archive -Path $destinationZip -DestinationPath $extractPath -Force
    }catch{
        Write-Host "FAILED to extract the downloaded repository to: $extractPath" -Foregroundcolor Red
        # exit 1
        throw "$($_.Exception.Message)"
    }
    Write-Host "Success! Your private repository has been securely downloaded and extracted to $extractPath" -ForegroundColor Green

    # exit 0
    #Insted of exit 0, return the path of extracted folder
    return $extractPath
}


function Make-Item {
    param(
        [String]$path,
        [String]$type
    )

    if(!(Test-Path -path $path)){
        if($type.toUpper() -eq 'DIRECTORY'){
            try{
                $generatedDir = New-Item -Path $path -ItemType Directory -Force
            }catch{
                Write-Host "Failed to create a Directory due to : $($_.Exception.Message)"
                throw "$($_.Execption.Message)"
            }
           return $generatedDir
        }

        if($type.toUpper() -eq 'FILE'){
            try{
                $generatedFile = New-Item -Path $path -ItemType File -Force
            }catch{
                throw "$($_.Exception.Message)"
            }
            return $generatedFile
        }

    }else{
        return $path
    }
}

function Execute-MirthCommand {
    param(
        # [String]$command,
        [String]$scriptPath
    )
    # Set-Content -path $scriptPath -value $command
    # Write-Host "Command being executed is: $command" -Foregroundcolor Yellow
    .\mccommand.exe -u admin -p @dm!n -s $scriptPath
}

#Execution Starts from here#
Push-Location -path "C:\Program Files\Mirth Connect"
$executionLocation = Get-Location
$Date = Get-Date -Format 'yyyy-MM-dd HH-mm'
Start-Transcript -path "$executionLocation\MirthUpdate $Date.log" -Force
$ErrorActionPreference = 'Stop'
$backupXMLFile = $null
$ErrorMessage = $null
try{

$repoPath = Get-GitRepo
#check Mirth service
$serviceStatus = Get-Service -Name "Mirth Connect Personal" | Select-Object -Property Status

if($serviceStatus.status -ne "Running"){
    throw "Mirth Service is not running"
}

#Script for Mirth Connect Command LIne tool
$MirthScriptPath = "$executionLocation\AutoUpdater\MirthScript.txt"
$MirthScriptPath = Make-Item -path $MirthScriptPath -type File
Write-Host "Path of the script file for Mirth Connect Command line tool is:  $MirthScriptPath"

#clear old commands from previous run
Write-Host "Clearing the contents of Mirth Scrip File: $MirthScriptPath file" -ForegroundColor Yellow
Clear-Content -path $MirthScriptPath

#create Mirth Backup file
$backupXMLFile = "$executionLocation\AutoUpdater\BackupBeforeUpdate\$Date\Mirth Backup\Mirth Backup $Date.xml"
$backUpXMLFile = Make-Item -path $backUpXMLFile -type File
#backup Mirth XML
$MirthCommand = "exportcfg `"$backUpXMLFile`""
Add-Content -path $MirthScriptPath -Value $MirthCommand
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

#create backup ConfigurationMap file
$backUpConfigurationMapFile = "$executionLocation\AutoUpdater\BackupBeforeUpdate\$Date\ConfigurationMap\backupConfiguraionMap.properities"
$backUPConfigurationMapFile = Make-Item -path $backUpConfigurationMapFile -type File
#backup ConfigurationMap.properties
$MirthCommand = "exportmap `"$backUpConfigurationMapFile`""
Add-Content -path $MirthScriptPath -Value $MirthCommand
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

#create backup globalScripts file
$backUpGlobalScriptsFile = "$executionLocation\AutoUpdater\BackupBeforeUpdate\$Date\GlobalScripts\backupGlobalScripts.xml"
$backUpGlobalScriptsFile = Make-Item -path $backUpGlobalScriptsFile -type File 
#backup globalscripts
$MirthCommand = "exportscripts `"$backUpGlobalScriptsFile`""
Add-Content -path $MirthScriptPath -Value $MirthCommand
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

#create backup CodeTemplates file
$backUpCodeTemplatesFile = "$executionLocation\AutoUpdater\BackupBeforeUpdate\$Date\CodeTemplates\backupCodeTemplates.xml"
$backUpCodeTemplatesFile = Make-Item -path $backUpCodeTemplatesFile -type File 
#backup Code Templates
$MirthCommand = "codetemplate library export * `"$backUpCodeTemplatesFile`""
Add-Content -path $MirthScriptPath -Value $MirthCommand
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

#create backup Channels folder
$backUpChannelsFolder = "$executionLocation\AutoUpdater\BackupBeforeUpdate\$Date\Backup Channels"
$backUpChannelsFolder = Make-Item -path $backUpChannelsFolder -type Directory
#backup Channels
$MirthCommand = "export * `"$backUpChannelsFolder\`""
Add-Content -path $MirthScriptPath -Value $MirthCommand
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

#create backup Alerts Folder
$backUpAlertsFolder = "$executionLocation\AutoUpdater\BackupBeforeUpdate\$Date\Backup Alerts"
$backUpAlertsFolder = Make-Item -path $backUpAlertsFolder -type Directory
#backup Alerts
$MirthCommand = "exportalert * `"$backUpAlertsFolder\`""
Add-Content -path $MirthScriptPath -Value $MirthCommand
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath



#Export all of them in one command session
Execute-MirthCommand -scriptPath $MirthScriptPath
 
$updateFolders = Get-ChildItem -path "$repoPath\Mirth-4.5.2-Personal-main" -Directory 


#clear old commands from previous run
Write-Host "Clearing the contents of Mirth Scrip File: $MirthScriptPath file" -ForegroundColor Yellow
Clear-Content -path $MirthScriptPath

foreach($cfgMapFolder in $updateFolders){
    $cfgFolderName = $cfgMapFolder.name
    if($cfgFolderName.toUpper() -eq 'CONFIGURATIONMAP'){
        Write-Host "Finding all properties files in $cfgFolderName" -ForegroundColor Yellow
        $cfgMapPropertiesFiles = Get-ChildItem -path $cfgMapFolder.fullname -Filter *.properties -File
        if($cfgMapPropertiesFiles.count -gt 0){
            Write-Host "Importing ConfigurationMap"
            foreach($cfgMapFile in $cfgMapPropertiesFiles){
                Write-Host "$cfgMapFile"
                $MirthCommand = "importmap `"$cfgMapFile`""
                Add-Content -path $MirthScriptPath -Value $MirthCommand
                # Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
            }
        }
    }
}

foreach($globalScriptsFolder in $updateFolders){
    $globalScriptsFolderName = $globalScriptsFolder.name
    if($globalScriptsFolderName.toUpper() -eq 'GLOBALSCRIPTS'){
        Write-Host "Finding all xml files in $globalScriptsFolderName" -ForegroundColor Yellow
       $globalScriptsXMLFiles = Get-ChildItem -path $globalScriptsFolder.fullname -Filter *.xml -File
       if($globalScriptsXMLFiles.count -gt 0){
            Write-Host "Importing Global Scripts"
            foreach($globalScriptsFile in $globalScriptsXMLFiles){
                Write-Host "$globalScriptsFile"
                $MirthCommand = "importscripts `"$globalScriptsFile`""
                Add-Content -path $MirthScriptPath -Value $MirthCommand
                # Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
            }
       }
    }
}

foreach($codeTemplatesFolder in $updateFolders){
    $codeTemplatesFolderName = $codeTemplatesFolder.name
    if($codeTemplatesFolderName.toUpper() -eq 'CODETEMPLATES'){
        Write-Host "Finding all xml files in $codeTemplatesFolderName" -ForegroundColor Yellow
       $codeTemplatesXMLFiles = Get-ChildItem -path $codeTemplatesFolder.fullname -Filter *.xml -File
       if($codeTemplatesXMLFiles.count -gt 0){
            Write-Host "Importing Code Templates"
            foreach($codeTemplatesFile in $codeTemplatesXMLFiles){
                Write-Host "$codeTemplatesFile"
                $MirthCommand = "codetemplate library import `"$codeTemplatesFile`" force"
                Add-Content -path $MirthScriptPath -Value $MirthCommand
                # Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
            }
       }
    }
}

foreach($channelsFolder in $updateFolders){
    $channelsFolderName = $channelsFolder.Name
    if($channelsFolderName.toUpper() -eq 'CHANNELS'){
        Write-Host "Finding all xml files in $channelsFolderName" -ForegroundColor Yellow
       $channelsXMLFiles = Get-ChildItem -path $channelsFolder.fullname -Filter *.xml -File
       if($channelsXMLFiles.count -gt 0){
            Write-Host "Importing Channels"
            foreach ($channelsFile in $channelsXMLFiles){
                Write-Host "$channelsFile"
                $MirthCommand = "import `"$channelsFile`" force"
                Add-Content -path $MirthScriptPath -Value $MirthCommand
                # Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
            }
       }
    }
}

foreach($alertsFolder in $updateFolders){
    $alertsFolderName = $alertsFolder.Name
    if($alertsFolderName.toUpper() -eq 'ALERTS'){
        Write-Host "Finding all xml files in $alertsFolderName" -ForegroundColor Yellow
        $alertsXMLFiles = Get-ChildItem -path $alertsFolder.fullname -Filter *.xml -File
        if($alertsXMLFiles.count -gt 0){
            Write-Host "Importing Alerts"
            foreach($alertsFile in $alertsXMLFiles){
                Write-Host "$alertsFile"
                $MirthCommand = "importalert `"$alertsFile`" force"
                Add-Content -path $MirthScriptPath -Value $MirthCommand
                # Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
            }
        }
    }
}


#Perfomr import action for downloaded files from repo in a single session
Execute-MirthCommand -scriptPath $MirthScriptPath

# $MirthCommand = "deploy"
# Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
# Pop-Location
}
catch{

    $ErrorMessage = $($_.Exception.Message)
    $RollBackStatus = "None"
    Write-Host "ErrorMessage: Mirth Upgrade Failed due to: $ErrorMessage" -Foregroundcolor Red
    if($null -ne $backupXMLFile -and (Test-Path -path $backupXMLFile)){
        Write-Host "*********Initiating Roll Back Operation************" -Foregroundcolor Yellow
        $serviceStatus = Get-Service -Name "Mirth Connect Service"
        if($serviceStatus.status -ne "Running"){
            Start-Service -Name "Mirth Connect Personal"
            Start-Sleep -Seconds 30
            # $MirthCommand = "importcfg `"$backupXMLFile`" nodeploy overwriteconfigmap"
            # $MirthCommand = "importcfg `"$backupXMLFile`" overwriteconfigmap"
            try{
                #Import ConfigurationMap first
                $MirthCommand = "importmap `"$backUPConfigurationMapFile`""
                Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

                #Import Globa Scripts
                $MirthCommand = "importscripts `"$backUpGlobalScriptsFile`""
                Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

                #Import Code Templates
                $MirthCommand  = "codetemplate library import `"$backUpCodeTemplatesFile`" force"
                Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath

                #Import each individual channel
                #Get channel .xml file, except the channel that's running this script
                $channelsFiles = Get-ChildItem -path $backUpChannelsFolder -filter *.xml -File | Where-Object { $_.name -ne "AutoUpdater.xml"}
                foreach( $channel in $channelsFiles){
                    $MirthCommand = "import `"$($channel.fullname)`" force"
                    Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
                }

                #Import each individual Alert 
                #Get alert .xml file,
                $alertsFiles = Get-ChildItem -path $backUpAlertsFolder -filter *.xml -File
                foreach( $Alert in $alertsFiles){
                    $MirthCommand = "importalert `"$($Alert.fullname)`" force"
                    Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
                }  
            }
            catch{
                Write-Host "Failed to roll back by restoring the old config with below error" -ForegroundColor Red
                Write-Host "Error: $($_.Exception.Message)" -Foregroundcolor Red
                Write-Host "*********Check Mirth Connect Service*********" -Foregroundcolor Blue
                Write-Host "*********Restore the backup config Manually " -ForegroundColor Blue
                $RollBackStatus = "Failed"
                Write-Host "RollBackStatus: $($RollBackStatus)"
                exit 1
            }

            #roll back succeeded
            $RollBackStatus = "Success"
            Write-Host "RollBackStatus: $($RollBackStatus)"
            exit 1
        }else{
            try{
                # $MirthImportScriptPath = Make-Item -path "$executionLocation\AutoUpdater\MirthImportScript.txt" -type File 
                # $MirthImportScriptFile = Get-Item -Path $MirthImportScriptPath
                # if($MirthImportScriptFile.Length -gt 0){
                #     Write-Host "Mirth Import Script File has old commands. Clearing those" -ForegroundColor Yellow
                #     Clear-Content -path $MirthImportScriptPath
                # }

                #clear old commands from previous run
                Write-Host "Clearing the contents of Mirth Scrip File: $MirthScriptPath file" -ForegroundColor Yellow
                Clear-Content -path $MirthScriptPath

                #Import Configuraiton Map
                $MirthCommand = "importmap `"$backUPConfigurationMapFile`""
                # Add-Content -path $MirthImportScriptPath -value $MirthCommand
                Add-Content -path $MirthScriptPath -Value $MirthCommand
                
                #Import Global Scripts
                $MirthCommand = "importscripts `"$backUpGlobalScriptsFile`""
                # Add-Content -path $MirthImportScriptPath -Value $MirthCommand
                Add-Content -path $MirthScriptPath -Value $MirthCommand

                #Import Code Templates
                $MirthCommand  = "codetemplate library import `"$backUpCodeTemplatesFile`" force"
                # Add-Content -path $MirthImportScriptPath -Value $MirthCommand
                Add-Content -path $MirthScriptPath -Value $MirthCommand

                #Import channels
                $channelsFiles = Get-ChildItem -path $backUpChannelsFolder -filter *.xml -File | Where-Object { $_.name -ne "AutoUpdater.xml"}
                foreach( $channel in $channelsFiles){
                    # Write-Host "Importing channel: $($channel.name)" -ForegroundColor Yellow
                    $MirthCommand = "import `"$($channel.fullname)`" force"
                    # Add-Content -path $MirthImportScriptPath -Value $MirthCommand
                    Add-Content -path $MirthScriptPath -Value $MirthCommand
                }

                #Import alerts
                $alertsFiles = Get-ChildItem -path $backUpAlertsFolder -filter *.xml -File
                foreach( $Alert in $alertsFiles){
                    # Write-Host "Importing Alert: $($Alert.name)" -ForegroundColor Yellow
                    $MirthCommand = "importalert `"$($Alert.fullname)`" force"
                    # Add-Content -path $MirthImportScriptPath -Value $MirthCommand
                    Add-Content -path $MirthScriptPath -Value $MirthCommand
                    # Execute-MirthCommand -command $MirthCommand -scriptPath $MirthScriptPath
                }  



                #Execute the final script using mccommand.exe
                # .\mccommand.exe -u admin -p @dm!n -s $MirthImportScriptPath
                Execute-MirthCommand -scriptPath $MirthScriptPath
            }
            catch{
                Write-Host "Failed to roll back by restoring the old config with below error" -ForegroundColor Red
                Write-Host "Error: $($_.Exception.Message)" -Foregroundcolor Red
                Write-Host "*********Check Mirth Connect Service*********" -Foregroundcolor Blue
                Write-Host "*********Restore the backup config Manually " -ForegroundColor Blue
                $RollBackStatus = "Failed"
                Write-Host "RollBackStatus: $($RollBackStatus)"
                exit 1
            }
            #roll back succeeded
            $RollBackStatus = "Success"
            Write-Host "RollBackStatus: $($RollBackStatus)" 
            exit 1        
        }
    }else{
        Write-Host "Execution Failed Before Backup even started" -ForegroundColor Red
        Write-Host "Check the transcript for logs" -ForegroundColor Yellow
        Write-Host "RollBackStatus: $($RollBackStatus)"  
        exit 1
    }
}
finally{
    Pop-Location
    Stop-Transcript
}
