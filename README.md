# Azure DevOps Environments and Approvers Analyzer

## 1. Description

This PowerShell script (`List-AzDevOpsEnvironmentsAndApprovers.ps1`) is designed to connect to Azure DevOps Services and extract a detailed list of environments within a specific project, along with their configured approvers and other relevant metadata.

The script generates a CSV report that includes:
- Project Name
- Environment ID
- Environment Name
- Application ID (extracted from environment name if it follows the pattern `NNN-...`)
- Approver Names (semicolon-separated)
- Approver Emails (semicolon-separated)
- Environment Creator
- Environment Creation Date
- Last Environment Modifier
- Last Environment Modification Date
- Environment Description

## 2. Prerequisites

Before running the script, ensure you have the following:

*   **PowerShell**:
    *   Version 5.1 or higher (PowerShell 7.x recommended for better compatibility).
    *   You can verify your version with `$PSVersionTable.PSVersion`.
*   **Azure DevOps Permissions**:
    *   An Azure DevOps **Personal Access Token (PAT)**.
    *   The PAT must have the following minimum scopes:
        *   **Environments**: `Read` (To read environment information).
        *   **Project and Team**: `Read` (To read project information).
        *   **Graph**: `Read` (Often needed to resolve user identities, although the current script gets names directly from environment and approval objects).
        *   **Build**: `Read` (If environments are linked to build/pipeline resources).
        *   **Release**: `Read` (If environments are linked to releases).
    *   *Note*: A PAT with "Full access" will also work, but limiting scopes is recommended for security.
    *   You must be a member of the Azure DevOps project you want to analyze or have sufficient permissions to access its information.

## 3. Project Setup

1.  **Clone the Repository** (if applicable):
    ```bash
    git clone <repository-url>
    cd <repository-name>
    ```

2.  **Folder Structure**:
    The script is designed to be run from the repository root.
    ```
    <repo-root>/
    ├── List-AzDevOpsEnvironmentsAndApprovers.ps1
    ├── reports/  <-- This folder will be created automatically by the script
    └── README.md <-- This file
    ```

## 4. Script Usage

Navigate to the repository root directory and run it from a PowerShell terminal.

```powershell
cd path/to/your/project

.\List-AzDevOpsEnvironmentsAndApprovers.ps1 -PAT "YOUR_PERSONAL_ACCESS_TOKEN" -Organization "YourAzDOOrganization"
```

### Script Parameters:

*   **`-PAT`** (Required):
    *   Your Azure DevOps Personal Access Token.
    *   Example: `"abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmn"`

*   **`-Organization`** (Required):
    *   Your Azure DevOps organization name. (E.g., if your URL is `https://dev.azure.com/MyCompany`, the name is `MyCompany`).
    *   Example: `"MyOrganization"`

*   **`-CsvFileName`** (Optional):
    *   Custom name for the output CSV file.
    *   **Important**: Provide only the filename (e.g., `environments_report.csv`), not the full path. The script will automatically save it in the `reports/` folder.
    *   If not specified, the file will be named `AzureDevOpsEnvironments_YYYYMMDD_HHMMSS.csv`.
    *   Example: `.\List-AzDevOpsEnvironmentsAndApprovers.ps1 -PAT "..." -Organization "..." -CsvFileName "tech_environments_q3.csv"`

### Complete Execution Example:

```powershell
# Navigate to the repository root folder
cd path/to/your/project

# Run with required parameters
.\List-AzDevOpsEnvironmentsAndApprovers.ps1 -PAT "xxxxPATxxxx" -Organization "MyOrganization"

# Run with a custom CSV filename
.\List-AzDevOpsEnvironmentsAndApprovers.ps1 -PAT "xxxxPATxxxx" -Organization "MyOrganization" -CsvFileName "Technology_Environments_Q3.csv"
```

## 5. Script Output

*   **Console**:
    *   The script will show progress, including the project being processed, environment pages being retrieved, and individual environments.
    *   It will also display any warnings or errors that occur during execution.
    *   At the end, it will confirm the path where the CSV file was saved and a summary of processed environments.

*   **CSV File**:
    *   A CSV file is generated in the `reports/` folder at the repository root.
    *   **CSV Columns**:
        *   `TeamProjectName`: Azure DevOps project name being analyzed (currently fixed to "Gerencia_Tecnologia" in the script).
        *   `EnvironmentId`: Numeric environment ID.
        *   `EnvironmentName`: Environment name.
        *   `ApplicationID`: Application ID extracted from `EnvironmentName` (if applicable, otherwise "N/A").
        *   `ApproverNames`: List of approver full names, separated by "; ". If none, "No approvers".
        *   `ApproverEmails`: List of approver emails (uniqueName), separated by "; ". If none, "No approvers".
        *   `CreatedBy`: Name of the user who created the environment.
        *   `CreatedOn`: Environment creation date and time (format: `M/d/yyyy h:mm:ss tt`).
        *   `LastModifiedBy`: Name of the user who last modified the environment.
        *   `LastModifiedOn`: Last modification date and time (format: `M/d/yyyy h:mm:ss tt`).
        *   `Description`: Environment description (if exists, otherwise "N/A").

## 6. Common Troubleshooting

*   **Error 401 (Unauthorized)**:
    *   Verify that your PAT is correct and hasn't expired.
    *   Ensure the PAT has the necessary scopes (see Prerequisites section).

*   **Error 404 (Not Found)**:
    *   Verify that the `-Organization` name is correct.
    *   The script is currently set to look for the "Gerencia_Tecnologia" project. If this project doesn't exist or is misspelled in the script, it could cause errors (although the script now gets the project ID dynamically, an incorrect name will fail at this initial step).

*   **"Could not retrieve Project ID for Gerencia_Tecnologia..."**:
    *   Ensure that the project name "Gerencia_Tecnologia" is correct and exists in the specified organization. The script depends on this name to start.

*   **Script doesn't create `reports/` folder or doesn't save CSV**:
    *   Verify that the script has write permissions in the repository root folder.
    *   Ensure there are no previous errors preventing the script from reaching the export part.

*   **Few or no environments listed**:
    *   Confirm that the PAT has permissions to read environments from the specified project.
    *   Verify that the "Gerencia_Tecnologia" project actually has configured environments.

## 7. Additional Considerations

*   **Fixed Project**: Currently, the script is configured to analyze only the project named "Gerencia_Tecnologia". To analyze a different project, you'll need to modify the `$uriProjectLookup` variable within the script.
    ```powershell
    # Around line 18
    $uriProjectLookup = $UriOrganization + "_apis/projects/YOUR_OTHER_PROJECT?api-version=6.0"
    ```
*   **Rate Limiting**: For organizations with a large number of environments or approvers, Azure DevOps might apply rate limiting. The script includes small delays (`Start-Sleep`) to mitigate this, but for very large volumes, you might need to adjust these delays or implement more sophisticated retry logic for HTTP 429 (Too Many Requests) error codes.

---

This README should provide a complete guide for team members to use and understand the script. 