<#PSScriptInfo
.VERSION 1.0.0
.GUID b5e78940-5e2f-427d-87a1-c1630ed8c3da
.AUTHOR Julian Pawlowski
.COMPANYNAME Workoho GmbH
.COPYRIGHT (c) 2024 Workoho GmbH. All rights reserved.
.TAGS
.LICENSEURI https://github.com/Workoho/AzAuto-Project.tmpl/LICENSE.txt
.PROJECTURI https://github.com/Workoho/AzAuto-Project.tmpl
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
    2024-01-16 - Initial release.
#>

<#
.SYNOPSIS
    Clone the Azure Automation Common Runbook Framework repository and invoke its setup scripts.

.DESCRIPTION
    Make sure that a clone of the Azure Automation Common Runbook Framework repository
    exists in parallel to this project repository. For example:

        C:\Developer\AzAuto-Project.tmpl
        C:\Developer\AzAuto-Common-Runbook-FW

    After this, invoke this script from the setup folder of the parent repository:

        C:\Developer\AzAuto-Common-Runbook-FW\setup\AzAutoFWProject\Update-AzAutoFWProject.ps1

    You may run this script at any time to update the project setup.
    When opening the project in Visual Studio Code, a task to run this script is already
    configured in .vscode\tasks.json.

.EXAMPLE
    Update-AzAutoFWProject.ps1
#>

[CmdletBinding()]
param()

Write-Verbose "---START of $((Get-Item $PSCommandPath).Name), $((Test-ScriptFileInfo $PSCommandPath | Select-Object -Property Version, Guid | & { process{$_.PSObject.Properties | & { process{$_.Name + ': ' + $_.Value} }} }) -join ', ') ---"

$commonParameters = 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable'
$commonBoundParameters = $PSBoundParameters.Keys | Where-Object { $_ -in $commonParameters } | ForEach-Object { @{ $_ = $PSBoundParameters[$_] } }

#region Read Project Configuration
$projectDir = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$configDir = Join-Path $projectDir 'config' 'AzAutoFWProject'
$configName = 'AzAutoFWProject.psd1'
$config = $null
$configScriptPath = Join-Path $configDir 'Get-AzAutoFWConfig.ps1'
if (    (Test-Path $configScriptPath) -and (Test-Path (Resolve-Path $configScriptPath) -PathType Leaf)) {
    # Use the parent configuration script if its symlink exists.
    if ($commonBoundParameters) {
        $config = & $configScriptPath -ConfigDir $configDir -ConfigName $configName @commonBoundParameters
    }
    else {
        $config = & $configScriptPath -ConfigDir $configDir -ConfigName $configName        
    }
}
else {
    # This will only run when the project is not yet configured.
    $configPath = Join-Path $configDir $configName
    $config = Import-PowerShellDataFile -Path $configPath -ErrorAction Stop | & {
        process {
            $_.Keys | Where-Object { $_ -notin ('ModuleVersion', 'Author', 'Description', 'PrivateData') } | & {
                process {
                    $_.Remove($_)
                }
            }
            $_.PrivateData.Remove('PSData')
            $local:configData = $_
            $_.PrivateData.GetEnumerator() | & {
                process {
                    $configData.Add($_.Key, $_.Value)
                }
            }
            $_.Remove('PrivateData')
            $_    
        }
    }
    $config.Project = @{ Directory = $projectDir }
    $config.Config = @{ Directory = $configDir; Name = $configName; Path = $configPath }
    $config.IsAzAutoFWProject = $true
}

if (-not $config.GitRepositoryUrl) { Write-Error "config.GitRepositoryUrl is missing in $configPath"; exit }
if (-not $config.GitReference) { Write-Error "config.GitReference is missing in $configPath"; exit }
#endregion

#region Clone repository if not exists
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is not installed on this system."
    exit
}

$AzAutoFWDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName (
    Split-Path (Split-Path $config.GitRepositoryUrl -Leaf) -LeafBase
).TrimEnd('.git')

if (-Not (Test-Path (Join-Path $AzAutoFWDir '.git') -PathType Container)) {
    try {
        Write-Output "Cloning $config.GitRepositoryUrl to $AzAutoFWDir"
        $output = git clone --quiet $config.GitRepositoryUrl $AzAutoFWDir 2>&1
        if ($LASTEXITCODE -ne 0) { Throw "Failed to clone repository: $output" }
    }
    catch {
        Write-Error $_
        exit
    }
}
#endregion

#region Invoke sibling script from parent repository
try {
    Join-Path $AzAutoFWDir 'setup' 'AzAutoFWProject' (Split-Path $PSCommandPath -Leaf) | & {
        process {
            if (Test-Path $_ -PathType Leaf) {
                if ($commonBoundParameters) {
                    & $_ -ChildConfig $config @commonBoundParameters
                }
                else {
                    & $_ -ChildConfig $config
                }
            }
            else {
                Write-Error "Could not find $_"
                exit
            }
        }
    }
}
catch {
    Write-Error $_
    exit
}
#endregion

Write-Verbose "-----END of $((Get-Item $PSCommandPath).Name) ---"
