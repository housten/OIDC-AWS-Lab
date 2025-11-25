
# 🧪 OIDC + AWS API Gateway Lab

This lab shows how to add authentication to an AWS API Gateway endpoint **without long-lived secrets** by using OIDC.

You’ll do it in **two phases**:

- **Phase 1:** Call an unsecured route — anyone can post.
- **Phase 2:** Change to a secure route — only trusted GitHub workflows with an OIDC token can post.

---

## 🔧 Prerequisites

- A GitHub repository you can edit and run workflows in.
- `jq` pre-installed in the GitHub runner (already true for hosted runners).
- an aws role with OIDC trust established as per [the main README](../README.md).

---

## 🌐 API Endpoints

| Type | Method | Path | Description |
|------|---------|------|-------------|
| Open | POST/GET | `/lab/results` | No authentication required |
| Secure | POST/GET | `/lab/results-secure` | Requires GitHub OIDC token (aud = `metrics-lab-api`) |

Base URL:  
`https://7jxbevu329.execute-api.eu-north-1.amazonaws.com/prod`

---

## 🚀 Phase 1 – Call the open route

1. Look at the workflow: `.github/workflows/call-api.yml`

```yaml
name: Call to AWS API-Gateway

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  call-open-api:
    runs-on: ubuntu-latest
    env:
      API_BASE: https://7jxbevu329.execute-api.eu-north-1.amazonaws.com/prod
    steps:
      - name: POST to open route (no auth)
        run: |
          curl -s -X POST "$API_BASE/lab/results" \
            -H "content-type: application/json" \
            -d "{\"owner\":\"${{ github.repository_owner }}\",\"repo\":\"${{ github.repository }}\",\"status\":\"pass\",\"suite\":\"open\"}" \
            | tee post.json

      - name: Read back (no auth)
        run: |
          TEST_ID=$(jq -r '.item.testId // .TestId // empty' post.json)
          echo "testId=$TEST_ID"
          curl -s \
          "$API_BASE/lab/results?owner=${{ github.repository_owner }}&repo=${{ github.repository }}&testId=$TEST_ID" | jq .
```
See how there is **no authentication** in the requests. No headers, no tokens.


2. Run the workflow from the **Actions** tab.  
   Click on `Call to AWS API-Gateway` to view the details. Click on the Run Workflow button to trigger the workflow.
   When it completes, look at the logs for the two steps.  
   The first step does a POST to the open route, the second step reads back the result. You can see the JSON response in both cases.
   You should see a `201` response and a JSON object returned from the API.

---

## 🔐 Phase 2 – Make it secure

1. update your workflow: `.github/workflows/call-api.yml` or make a copy of it if you want to keep both versions.

```yaml
name: Lab Phase 2 — use secure route
on: workflow_dispatch:

permissions:
  id-token: write  # <--- 1. Add this so GitHub can issue OIDC tokens
  contents: read

jobs:
  call-secure-api:
    runs-on: ubuntu-latest
    env:
      API_BASE: https://7jxbevu329.execute-api.eu-north-1.amazonaws.com/prod
    steps:
    # 2. Add this step to Request OIDC token and use it to call secure route
    steps:
      - name: Request GitHub OIDC token (audience=metrics-lab-api)
        id: oidc
        shell: bash
        run: |
          set -e
          RESP=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
                 "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=metrics-lab-api")
          TOKEN=$(echo "$RESP" | jq -r '.value')
          echo "$TOKEN"
          echo "token=$TOKEN" >> "$GITHUB_OUTPUT"
      
      - name: Call secure API route
        run: |
          curl -v -s -X POST "$API_BASE/lab/results-secure" \   # <-- 3. Change to secure route
            -H "authorization: Bearer ${{ steps.oidc.outputs.token }}" \
            -H "content-type: application/json" \               # <-- 4. Add the token in Authorization header
            -d '{"status":"pass","suite":"secure"}' | tee post.json

      - name: Read back stored result
        run: |
          TEST_ID=$(jq -r '.item.testId // .TestId // empty' post.json)
          echo "testId=$TEST_ID"
          curl -s \
            -H "authorization: Bearer ${{ steps.oidc.outputs.token }}" \ # <-- 5. Add the token in Authorization header
            "$API_BASE/lab/results-secure?testId=$TEST_ID" | jq . #   <-- 6. Change to secure route
```

2. Run it.  
   This time the request is **authorized via OIDC**.  

## 🔐 Phase 3 – Investigate the token

1. update your workflow: `.github/workflows/call-api.yml` or make a copy of it if you want to keep both versions.

```yaml
name: Lab Phase 2 — use secure route
on: workflow_dispatch:

permissions:
  id-token: write  
  contents: read

jobs:
  call-secure-api:
    runs-on: ubuntu-latest
    env:
      API_BASE: https://7jxbevu329.execute-api.eu-north-1.amazonaws.com/prod
    steps:
    steps:
      - name: Request GitHub OIDC token 
        id: oidc
        shell: bash
        run: |
          set -e
          RESP=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
                 "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=metrics-lab-api")
          TOKEN=$(echo "$RESP" | jq -r '.value')
          echo "$TOKEN"
          echo "token=$TOKEN" >> "$GITHUB_OUTPUT"
# 1. add this to save the token for inspection    
      - name: Show JWT header and payload (for learning)
        run: |
          HP=$(echo "${{ steps.oidc.outputs.token }}" | awk -F. '{print $1"."$2}')
          echo "JWT header.payload: $HP"
          printf "%s" "${{ steps.oidc.outputs.token }}" > oidc_token.txt
          chmod 600 oidc_token.txt
# 2. add this to upload the token as an artifact
      - name: Upload token for manual jwt.ms inspection (optional)
        uses: actions/upload-artifact@v4
        with:
          name: github-oidc-token
          path: oidc_token.txt
          
      - name: Call secure API route
        run: |
          curl -v -s -X POST "$API_BASE/lab/results-secure" \
            -H "authorization: Bearer ${{ steps.oidc.outputs.token }}" \
            -H "content-type: application/json" \
            -d '{"status":"pass","suite":"secure"}' | tee post.json

      - name: Read back stored result
        run: |
          TEST_ID=$(jq -r '.item.testId // .TestId // empty' post.json)
          echo "testId=$TEST_ID"
          curl -s \
            -H "authorization: Bearer ${{ steps.oidc.outputs.token }}" \
            "$API_BASE/lab/results-secure?testId=$TEST_ID" | jq .
```

2. Run it.  
    After the workflow completes, go to the **Artifacts** section of the workflow run and download the `github-oidc-token` artifact. Open it to see the OIDC token issued by GitHub.

   You can paste the token into [https://jwt.ms](https://jwt.ms) to inspect the claims.

---

## 🧩 What you’ve learned

| Feature | Phase 1 | Phase 2 |
|----------|----------|---------|
| Requires AWS creds | ❌ | ❌ |
| Requires OIDC token | ❌ | ✅ |
| Protected by | None | API Gateway JWT authorizer |
| Typical use | Smoke-tests, open pings | Trusted CI/CD workflows |

---

✅ **Next:**  
Try to break it! Remove the `id-token: write` permission and see how the secure route rejects the call.  
Try changing the audience in the token request to something else and see how the secure route rejects it.
---

Happy experimenting! 🎉

