[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$PAT,
    
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)] # New parameter for project name
    [string]$ProjectName,
    
    [Parameter(Mandatory = $false)]
    [string]$CsvFileName # Optional: Just the file name, path will be handled by the script
)

# --- Script Setup ---
# Get the directory where the script is located (assuming it's the project root)
$ProjectRoot = $PSScriptRoot # $PSScriptRoot is the modern way to get the script directory

# Define the reports directory relative to the project root
$ReportsDirectory = Join-Path -Path $ProjectRoot -ChildPath "reports"

# Create the reports directory if it doesn't exist
if (-not (Test-Path $ReportsDirectory)) {
    try {
        New-Item -ItemType Directory -Path $ReportsDirectory -Force | Out-Null
        Write-Host "Created reports directory: $ReportsDirectory" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create reports directory: $ReportsDirectory. Error: $($_.Exception.Message)"
        exit 1
    }
}

# Determine the output CSV path
$DefaultCsvFileName = "AzureDevOpsEnvironments_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
if (-not [string]::IsNullOrWhiteSpace($CsvFileName)) {
    # Validate CsvFileName - ensure it's just a name, not a path
    if ($CsvFileName -match '[\/:]') {
        Write-Error "CsvFileName parameter should only be a file name, not a path (e.g., 'my_report.csv')."
        exit 1
    }
    if (-not ($CsvFileName.EndsWith('.csv'))) {
        $CsvFileName += ".csv"
    }
    $OutputCsvPath = Join-Path -Path $ReportsDirectory -ChildPath $CsvFileName
}
else {
    $OutputCsvPath = Join-Path -Path $ReportsDirectory -ChildPath $DefaultCsvFileName
}

Write-Host "Report will be saved to: $OutputCsvPath" -ForegroundColor Cyan
# --- End Script Setup ---

# Create authentication header
$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
$UriOrganization = "https://dev.azure.com/$($Organization)/"

Write-Host "Starting to collect Azure DevOps environments and approvers information for project: $ProjectName..." -ForegroundColor Cyan

# Initialize results array
$results = @()
$totalEnvironments = 0
$pageSize = 100
$maxRetries = 3

# Get project details using the provided ProjectName
$uriProjectLookup = $UriOrganization + "_apis/projects/$($ProjectName)?api-version=6.0"
try {
    $projectDetails = Invoke-RestMethod -Uri $uriProjectLookup -Method get -Headers $AzureDevOpsAuthenicationHeader
    if (-not $projectDetails.id) {
        Write-Error "Could not retrieve Project ID for '$($ProjectName)'. Please check organization and project name."
        exit 1
    }
    $projectId = $projectDetails.id
    # ProjectName is obtained from parameter, but we confirm it with the response for consistency
    $fetchedProjectName = $projectDetails.name 
    Write-Host "`nSuccessfully fetched details for project: $fetchedProjectName (ID: $projectId)" -ForegroundColor Green
    
    # Get all environments with pagination using the official API
    $allEnvironments = @()
    $continuationToken = $null
    
    do {
        $retryCount = 0
        $success = $false
        
        do {
            try {
                # Build the environments URL with pagination
                $uriEnvironments = $UriOrganization + "$projectId/_apis/distributedtask/environments?api-version=7.1&`$top=$pageSize"
                if ($continuationToken) {
                    $uriEnvironments += "&continuationToken=$continuationToken"
                }
                
                Write-Host "Fetching environments page with URL: $uriEnvironments" -ForegroundColor Gray
                
                # Use Invoke-WebRequest to get access to response headers
                $response = Invoke-WebRequest -Uri $uriEnvironments -Headers $AzureDevOpsAuthenicationHeader -UseBasicParsing
                $responseContent = $response.Content | ConvertFrom-Json
                $success = $true
                
                if ($responseContent.value) {
                    $batchCount = $responseContent.value.Count
                    $totalEnvironments += $batchCount
                    Write-Host "Processing batch of $batchCount environments (Total so far: $totalEnvironments)" -ForegroundColor Yellow
                    
                    $allEnvironments += $responseContent.value
                    
                    # Check for continuation token in response headers
                    $continuationToken = $null
                    if ($response.Headers.ContainsKey('x-ms-continuationtoken')) {
                        $continuationToken = $response.Headers['x-ms-continuationtoken']
                        Write-Host "Found continuation token in headers: $continuationToken" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "No more environments found" -ForegroundColor Yellow
                    $continuationToken = $null
                }
            }
            catch {
                $retryCount++
                Write-Warning "Error fetching environments page (Attempt $retryCount of $maxRetries):"
                Write-Warning $_.Exception.Message
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Waiting 5 seconds before retry..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                }
                else {
                    Write-Warning "Max retries reached, stopping pagination for environments."
                    $continuationToken = $null # Stop trying to paginate
                    $success = $true # Allow processing of already fetched environments
                }
            }
        } while (-not $success -and $retryCount -lt $maxRetries)
        
        # Add a small delay between pages to avoid rate limiting
        if ($continuationToken) {
            Start-Sleep -Milliseconds 1000
        }
        
    } while ($continuationToken)
    
    Write-Host "`nProcessing $($allEnvironments.Count) environments for project $fetchedProjectName..." -ForegroundColor Cyan
    
    # Process all collected environments
    foreach ($environment in $allEnvironments) {
        Write-Host "  Processing environment: $($environment.name)" -ForegroundColor Yellow
        
        # Extract ApplicationID from environment name
        $applicationId = "N/A"
        if ($environment.name -match '(^\d+)-') {
            $applicationId = $Matches[1]
        }

        # Get additional environment details
        $createdBy = if ($environment.createdBy -and $environment.createdBy.displayName) { $environment.createdBy.displayName } else { "N/A" }
        $createdOnFormatted = if ($environment.createdOn) { (Get-Date $environment.createdOn).ToString('M/d/yyyy h:mm:ss tt', [System.Globalization.CultureInfo]::InvariantCulture) } else { "N/A" }
        $lastModifiedBy = if ($environment.lastModifiedBy -and $environment.lastModifiedBy.displayName) { $environment.lastModifiedBy.displayName } else { "N/A" }
        $lastModifiedOnFormatted = if ($environment.lastModifiedOn) { (Get-Date $environment.lastModifiedOn).ToString('M/d/yyyy h:mm:ss tt', [System.Globalization.CultureInfo]::InvariantCulture) } else { "N/A" }
        $description = if ($environment.description) { $environment.description } else { "N/A" }

        $approverNamesList = [System.Collections.Generic.List[string]]::new()
        $approverEmailsList = [System.Collections.Generic.List[string]]::new()

        try {
            # Get environment checks using the new API version
            $uriEnvironmentChecks = $UriOrganization + "$projectId/_apis/pipelines/checks/queryconfigurations?`$expand=settings&api-version=7.2-preview.1"
            $body = @(
                @{
                    type = "queue"
                    id = "1"
                    name = "Default"
                },
                @{
                    type = "environment"
                    id = "$($environment.id)"
                    name = "$($environment.name)"
                }
            ) | ConvertTo-Json

            $EnvironmentChecksResult = Invoke-RestMethod -Uri $uriEnvironmentChecks -Method Post -Body $body -Headers $AzureDevOpsAuthenicationHeader -ContentType application/json
            
            if ($EnvironmentChecksResult.value) {
                Foreach ($envcheck in $EnvironmentChecksResult.value) {
                    if ($envcheck.type.name -eq 'Approval') {
                        try {
                            $ApproversResult = Invoke-RestMethod -Uri $envcheck.url -Method get -Headers $AzureDevOpsAuthenicationHeader
                            if ($ApproversResult.settings.approvers) {
                                Foreach ($approver in $ApproversResult.settings.approvers) {
                                    if ($approver.displayName) { $approverNamesList.Add($approver.displayName) }
                                    if ($approver.uniqueName) { $approverEmailsList.Add($approver.uniqueName) }
                                }
                            }
                        }
                        catch {
                            Write-Warning "  Error getting approvers for environment $($environment.name):"
                            Write-Warning "  $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "  Error processing checks for environment $($environment.name):"
            Write-Warning "  $($_.Exception.Message)"
        }

        $approverNamesString = if ($approverNamesList.Count -gt 0) { $approverNamesList -join "; " } else { "No approvers" }
        $approverEmailsString = if ($approverEmailsList.Count -gt 0) { $approverEmailsList -join "; " } else { "No approvers" }

        $results += [PSCustomObject]@{
            TeamProjectName = $fetchedProjectName # Using fetched project name
            EnvironmentId = $environment.id
            EnvironmentName = $environment.name
            ApplicationID = $applicationId
            ApproverNames = $approverNamesString
            ApproverEmails = $approverEmailsString
            CreatedBy = $createdBy
            CreatedOn = $createdOnFormatted
            LastModifiedBy = $lastModifiedBy
            LastModifiedOn = $lastModifiedOnFormatted
            Description = $description
        }
    }
}
catch {
    Write-Warning "Error processing project $($ProjectName): $($_.Exception.Message)"
}

# Export results to CSV
if ($results.Count -gt 0) {
    Write-Host "`nExporting results to CSV: $OutputCsvPath" -ForegroundColor Cyan
    $results | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "CSV export completed successfully" -ForegroundColor Green
    Write-Host "Total environments found in API: $totalEnvironments" -ForegroundColor Green
    Write-Host "Total records in CSV: $($results.Count)" -ForegroundColor Green 
}
else {
    Write-Warning "No results found to export for project $ProjectName"
}

Write-Host "`nScript execution completed" -ForegroundColor Cyan 