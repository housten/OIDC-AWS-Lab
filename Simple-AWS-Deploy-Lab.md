# Create an S3 container using Github OIDC authentication

## Create AWS Resources
Log into your AWS where you have permissions to create a resource (S3 is what we use but you could use anything)

1. Add OpenID Connect (OIDC) Provider: 
    ◦ Navigate to Identity Providers in IAM. 
    ◦ Add a new provider: Select Open ID Connect. 
    ◦ Enter the GitHub OIDC Provider URL ([this information is available from GitHub](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws#adding-the-identity-provider-to-aws)). 
    ◦ Set the Audience to sts.amazon.com. 
    ◦ Click Add Provider (if there is one already you will get an error. Delete or use the existing provider). 

1. Create the IAM Role: GitHubActionsOIDC-S3-Deployer 
    ◦ Create a new IAM role and select Web Identity as the trusted entity type. 
    ◦ Select the OIDC provider you just created. 
    ◦ Set the audience to sts.amazon.com. 
    ◦ Specify the GitHub owner/organization (your username or organization). (Optional: You can further restrict it by repository name, e.g., nodejs app). 

1. Configure Role Permissions and Creation:  
    ◦ Assign necessary permissions (for this demo, permissions only for connection validation are used, not for services like S3 or ECR). 
    ◦ Name the role (e.g., Github-OIDC-actions) and click Create role. Github-OIDC-actions
    ◦ Navigate to the role 
    ◦ Copy the ARN (Amazon Resource Name) of this newly created role for use in th GitHub action workflow.

## Configure Github Workflow
Now we connect our pipeline to the AWS role.
1. Open the simple workflow yaml file
1. Add the following line to the `Permissions:` section.<br />
   `  id-token: write # CRITICAL: Required to request the OIDC JWT token`
1. Add the following action directly after the `steps:` tag.  This is the AWS login step that will connect the github token to the AWS Role.
``` yaml
      - name: "Configure AWS Credentials"
        id: awscreds
        uses: aws-actions/configure-aws-credentials@v5.1.0
        with:
          aws-region:  eu-central-1
          role-to-assume: << YOUR AWS ARN FROM STEP 3 ABOVE GOES HERE >>
          output-credentials: true
```
1. Add the following action directly after the `steps:` tag. This will just output some details from your AWS session to confirm your identity is set up.
```
      - name: Verify Assumed Role Identity (Optional Check)
        run: aws sts get-caller-identity
```
Notice that we don't have to add any references to the identity. The AWS actions and cli automatically pass along the authorization information.
1. Commit the workflow
1. Go to the actions tab and trigger it if it isn't already running.
