# 🔐 IAM vs JWT Authorization for APIs

When you expose APIs on AWS (for example through API Gateway), you can secure them in two common ways:
- Using **IAM (SigV4)** authentication
- Using **JWT (Bearer token)** authentication via OIDC

Both are secure, secretless, and valid for modern CI/CD workflows—but they serve slightly different purposes.

---

## ⚙️ Overview

| Concern | **JWT Authorizer (Bearer Token)** | **IAM Auth (SigV4)** |
|----------|----------------------------------|----------------------|
| **Authentication** | API Gateway validates JWT signature, issuer, and audience. | API Gateway validates AWS SigV4 signature using temporary AWS credentials. |
| **Authorization** | Done via route **scopes** (defined in API Gateway) or claims. | Done via **IAM policy** (attached to caller’s role). |
| **Identity Source** | OIDC provider (e.g., GitHub Actions, Auth0, Azure AD). | AWS IAM Role assumed via OIDC → STS. |
| **API Gateway Route Type** | `AuthorizationType = JWT` | `AuthorizationType = AWS_IAM` |
| **Credential Lifetime** | Short-lived JWT (~10 minutes for GitHub). | Temporary AWS credentials (STS, ~1 hour). |
| **Scopes / Claims** | JWT can include scopes, repo, owner, sub, etc. | IAM can use tags or condition keys on principals. |
| **App-Level Checks** | Optional (check claims for tenant/owner). | Optional (check headers or context if needed). |
| **Typical Use** | APIs for CI/CD or external systems without AWS credentials. | APIs used by workloads already authenticated into AWS. |

---

## 🧩 JWT Authorizer (Bearer Token)

**Pattern:** The workflow requests a signed JWT directly from its OIDC provider and includes it in the API call.

```bash
RESP=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN"        "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=lab-api")
TOKEN=$(echo "$RESP" | jq -r '.value')

curl -s -X POST "$API_BASE/lab/results-secure"   -H "authorization: Bearer $TOKEN"   -H "content-type: application/json"   -d '{"status":"pass","suite":"secure"}'
```

**API Gateway setup:**
- `AuthorizationType = JWT`
- `Issuer = https://token.actions.githubusercontent.com`
- `Audience = lab-api`

**Use this when:**
- You want to trust external identities (e.g., GitHub, Azure AD) **without giving AWS access**.
- You want fine-grained per-route authorization based on OIDC scopes.
- Your API is public-facing or multi-tenant.

**Example use cases:**
- CI/CD pipelines sending test results.
- Partner systems posting data securely.
- Developer tools authenticating via federated login.

---

## 🧭 IAM Auth (SigV4)

**Pattern:** The workflow exchanges its OIDC identity for temporary AWS credentials via STS using the `configure-aws-credentials` GitHub Action. The workflow then signs API calls with those credentials.

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v5.1.0
  with:
    role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/github-actions-role
    aws-region: eu-north-1

- name: Call IAM-protected route
  run: |
    awscurl --service execute-api --region eu-north-1       -X POST       -H 'content-type: application/json'       --data '{"status":"pass","suite":"ci"}'       "$API_BASE/lab/results-ci"
```

**API Gateway setup:**
- `AuthorizationType = AWS_IAM`

**Use this when:**
- The workflow **already needs AWS access** (e.g., to deploy, read S3, invoke Lambda).
- You want centralized access control via **IAM policies**.
- You don’t need OAuth scopes.

**Example use cases:**
- Internal automation or infra-deploy pipelines.
- AWS service integrations that sign requests with SigV4.

---

## 🧠 Choosing Between JWT and IAM

| Goal | Recommended Approach |
|------|-----------------------|
| Allow external systems to call your API without AWS credentials | ✅ **JWT authorizer** |
| CI/CD workflow already needs AWS access (deploy infra, update S3) | ✅ **IAM auth** |
| Enforce OAuth-like scopes (`read`, `write`, etc.) | ✅ **JWT authorizer** |
| Centralized, auditable IAM permission control | ✅ **IAM auth** |
| Want to mix both for flexibility | Combine routes: `/secure` (JWT) and `/ci` (IAM) |

---

## 💬 Hybrid Pattern (used in the lab)

This lab demonstrates **both**:

| Route | Auth Type | Caller | Notes |
|--------|------------|---------|-------|
| `/lab/results` | None | Anyone | Open route for initial testing |
| `/lab/results-secure` | JWT | GitHub OIDC | No AWS credentials required |
| `/lab/results-ci` | IAM | AWS OIDC role | Uses AWS SigV4 with temporary creds **NOT IMPLEMENTED YET** |

This mirrors a realistic environment: external systems use JWTs, internal workloads use IAM.

---

## ✅ Summary

- **JWT Authorizer:** External, federated, fine-grained, “bring your own identity.”  
- **IAM Auth:** Internal, AWS-native, managed by policies.

Both are **best practice**, depending on who’s calling the API.  
Use **JWT** when you want to trust an *identity provider*.  
Use **IAM** when you want to trust an *AWS role*.

---

Happy building! ☁️
