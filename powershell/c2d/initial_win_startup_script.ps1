#
#  Copyright 2019 Google Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

Set-StrictMode -Version Latest

$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine\sysprep'

# Import Modules
try {
    Import-Module $script:gce_install_dir\gce_base.psm1 -ErrorAction Stop
}
catch [System.Management.Automation.ActionPreferenceStopException] {
    Write-Host $_.Exception.GetBaseException().Message
    Write-Host ("Unable to import GCE module from $script:gce_install_dir. " +
        'Check error message, or ensure module is present.')
    exit 2
}

# Default Values
$Script:c2d_scripts_bucket = 'c2d-windows/scripts'
$Script:install_path="C:\C2D" # Folder for downloads
$script:show_msgs = $false
$script:write_to_serial = $false


# Functions
function DownloadScript {
    <#
    .SYNOPSIS
        Downloads a script to the localmachine from GCS.
    .DESCRIPTION
        Uses WebClient to download a script file.
    .EXAMPLE
         DownloadScript -path bucket/.. -filename <name>
    #>
    param (
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        $path,
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        $filename,
    [Switch] $overwrite
    )
    $storage_url = 'http://storage.googleapis.com'
    $download_url = "$storage_url/$path"


    # Check if file already exists and act accordingly.
    if ((Test-path -path $filename)){
      if ($overwrite){
        Write-Log "$filename already exists. Overwrite flag set."
        _DeleteFiles -files $filename
      }
      else {
        Write-Log "$filename already exists. Overwrite flag notset."
        return $true
      }
    }
    # Download the file
    Write-Log "Original download url: $download_url"
    # To avoid cache issues
    $url = $download_url + "?random=" + (Get-Random).ToString()

    Write-Log "Downloading $url to $filename"
    try {
      Invoke-WebRequest -Uri $url -OutFile $filename -Headers @{"Cache-Control"="private"}
    }
    catch [System.Net.WebException] {
      $response = $_.Exception.Response
      if ($response) {
        _PrintError
        Write-Log $response.StatusCode -error # This is a System.Net.HttpStatusCode enum value
        Write-Log $response.StatusCode.value__ -error # This is the numeric version.
      }
      else {
        $type = $_.Exception.GetType().FullName
        $message = $_.Exception.Message
        Write-Log "$type $message"
      }
      return $false
    }

    # Check if download successfull
    if ((Test-path -path $filename)){
      return $true
    }
    else {
      Write-Log "File not found."
      return $false
    }
}


## Main
# Instance specific variables
$script_name = 'sql_install.ps1'
$script_subpath = 'sqlserver'
$task_name = "SQLInstall"

# Create the C:\C2D folder
if (!(Test-path -path $Script:install_path )) {
  try {
    New-Item -ItemType directory -Path $Script:install_path
  }
  catch {
    _PrintError
    exit 1
  }
}

# Download the scripts
# Base Script
$base_script_path = "$Script:c2d_scripts_bucket/c2d_base.psm1"
$base_script = "$Script:install_path\c2d_base.psm1"
if (DownloadScript -path $base_script_path -filename $base_script) {
  Write-Log "File downloaded successfully."
}
else {
  Write-Log "File not found."
  exit 2
}
# Run Script
$run_script = "$Script:install_path\$script_name"
$run_script_path = "$Script:c2d_scripts_bucket/$script_subpath/$script_name"
if (DownloadScript -path $run_script_path -filename $run_script) {
  Write-Log "File downloaded successfully."
}
else {
  Write-Log "File not found."
  exit 2
}


# Execute the script
Write-Log "Checking if $task_name sctask exists?"
$sc_task = Get-ScheduledTask -TaskName $task_name -ErrorAction SilentlyContinue
if ($sc_task) {
  Write-Log "$task_name schtask exists."
  try {
    Write-Log "-- Executing sctask $task_name. --"
    $response = Start-ScheduledTask -TaskName $task_name
    Write-Log $response

  }
  catch {
    $type = $_.Exception.GetType().FullName
    $message = $_.Exception.Message
    Write-Log "$type $message"
    exit 1
  }
}
else {
  Write-Log "schtask $task_name does not exists."
  Write-Log "Executing: $run_script"
  try {
    & $run_script -task_name $task_name
  }
  catch {
    $type = $_.Exception.GetType().FullName
    $message = $_.Exception.Message
    Write-Log "$type $message"
    exit 1
  }
}