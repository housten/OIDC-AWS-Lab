<#
.SYNOPSIS
    Automates AWS IAM and OIDC setup for GitHub Actions.
.NOTES
    This script performs the following:
    1. Creates a demo IAM User with Admin access.
    2. Creates/Updates the GitHub OIDC Provider.
    3. Creates an IAM Role with a Trust Policy for GitHub.
    4. Outputs the Role ARN.
#>

# --- CONFIGURATION VARIABLES (EDIT THESE) ---
$IamUserName = "github-action-user-demo"
$RoleName    = "github-action-role-demo"
$GitHubOrg   = "YourUsernameOrOrg"    # e.g., "octocat"
$GitHubRepo  = "YourRepoName"         # e.g., "my-node-app" (Set to "*" to allow all repos in org)

# --- CONSTANTS ---
$OidcUrl = "https://token.actions.githubusercontent.com"
$Audience = "sts.amazonaws.com"
# GitHub's thumbprints (Required for CLI creation, unlike Console)
# These are the known thumbprints for GitHub Actions. 
$Thumbprints = "6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"

# --- START SCRIPT ---
Write-Host "Starting AWS OIDC Setup for GitHub Actions..." -ForegroundColor Cyan

# 0. Get AWS Account ID
$AccountId = aws sts get-caller-identity --query "Account" --output text
if (-not $AccountId) {
    Write-Error "Could not retrieve AWS Account ID. Please ensure 'aws configure' is run."
    exit
}
Write-Host "Target AWS Account: $AccountId" -ForegroundColor Gray

# --- PART 1: Create IAM User (Initial Step) ---
Write-Host "`n[Step 1] Creating IAM User: $IamUserName..." -ForegroundColor Yellow
try {
    aws iam create-user --user-name $IamUserName 2>$null
    Write-Host "User '$IamUserName' created." -ForegroundColor Green
} catch {
    Write-Host "User '$IamUserName' likely already exists. Proceeding..." -ForegroundColor Gray
}

# Note for Demo: Attaching Admin Access
Write-Host "Attaching AdministratorAccess to $IamUserName (DEMO ONLY - NOT FOR PRODUCTION)..." -ForegroundColor Magenta
aws iam attach-user-policy --user-name $IamUserName --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

# --- PART 2: Add OpenID Connect (OIDC) Provider ---
Write-Host "`n[Step 2] Setting up OIDC Provider..." -ForegroundColor Yellow

# Check if provider exists
$ExistingProviders = aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[*].Arn" --output text
$ProviderArn = "arn:aws:iam::$($AccountId):oidc-provider/token.actions.githubusercontent.com"

if ($ExistingProviders -match "token.actions.githubusercontent.com") {
    Write-Host "GitHub OIDC Provider already exists. Skipping creation." -ForegroundColor Gray
} else {
    Write-Host "Creating new GitHub OIDC Provider..."
    aws iam create-open-id-connect-provider `
        --url $OidcUrl `
        --client-id-list $Audience `
        --thumbprint-list $Thumbprints
    Write-Host "OIDC Provider created successfully." -ForegroundColor Green
}

# --- PART 3: Create the IAM Role ---
Write-Host "`n[Step 3] Creating IAM Role: $RoleName..." -ForegroundColor Yellow

# Construct Trust Policy JSON
# This restricts the role to be assumed only by your specific GitHub Org/Repo
$TrustPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "$ProviderArn"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:$GitHubOrg/$($GitHubRepo):*"
                },
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
"@

# Save policy to temp file (CLI requires file path or correctly escaped JSON string)
$PolicyFile = New-TemporaryFile
Set-Content -Path $PolicyFile.Path -Value $TrustPolicy

# Create Role
try {
    # Check if role exists first to avoid error
    aws iam get-role --role-name $RoleName 2>$null > $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Role '$RoleName' already exists. Updating Trust Policy..." -ForegroundColor Gray
        aws iam update-assume-role-policy --role-name $RoleName --policy-document "file://$($PolicyFile.Path)"
    } else {
        Write-Host "Creating new role..."
        aws iam create-role --role-name $RoleName --assume-role-policy-document "file://$($PolicyFile.Path)"
    }
} finally {
    Remove-Item $PolicyFile.Path
}

# --- PART 4: Configure Role Permissions ---
Write-Host "`n[Step 4] Configuring Role Permissions..." -ForegroundColor Yellow
# For this demo, we attach ReadOnlyAccess to validate connection
# In a real scenario, use minimal permissions (e.g., only ECR push or S3 upload)
$DemoPolicyArn = "arn:aws:iam::aws:policy/ReadOnlyAccess" 

aws iam attach-role-policy --role-name $RoleName --policy-arn $DemoPolicyArn
Write-Host "Attached 'ReadOnlyAccess' to $RoleName for validation." -ForegroundColor Green

# --- FINAL OUTPUT ---
Write-Host "`n--------------------------------------------------------"
Write-Host "SETUP COMPLETE" -ForegroundColor Green
Write-Host "--------------------------------------------------------"
Write-Host "User Created: $IamUserName"
Write-Host "Role Created: $RoleName"
Write-Host "Role ARN:     arn:aws:iam::$($AccountId):role/$RoleName" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------"
Write-Host "Action: Copy the Role ARN above. You will use this in your GitHub Actions YAML."
Write-Host "        Example: role-to-assume: arn:aws:iam::$($AccountId):role/$RoleName"
