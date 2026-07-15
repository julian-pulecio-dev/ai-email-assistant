# Google Social Login App

Users sign in **only** via Google, and the app can then call Gmail on their
behalf. React frontend + a serverless Python backend (API Gateway + Lambda +
DynamoDB) provisioned entirely with Terraform.

## Architecture

```
React (Vite) --Google auth code--> POST /auth/google (Lambda, public)
                                       exchanges the code for a Google access_token
                                       + refresh_token, verifies the id_token,
                                       upserts the user in DynamoDB, returns
                                       our own session JWT

React --Authorization: Bearer <session JWT>--> GET /auth/me (Lambda, protected
                                       by a Lambda authorizer that validates
                                       the session JWT)

React --Authorization: Bearer <session JWT>--> GET /gmail/messages (Lambda, protected)
                                       refreshes the user's Google access_token
                                       if needed, calls the Gmail API, returns
                                       their most recent messages
```

- **DynamoDB** table `users`: Google `sub` as primary key, plus email/name/picture
  and the user's Google `access_token`/`refresh_token`/granted scopes.
- **Secrets Manager**: your Google OAuth credentials live in a secret you create
  yourself (Terraform only reads its ARN by name); the session-JWT signing key
  is generated and stored by Terraform automatically.
- **Terraform layout**: `backend/terraform/main.tf` orchestrates four child
  modules (`modules/dynamodb`, `modules/secrets`, `modules/lambda`,
  `modules/api_gateway`).

## 1. Create a Google OAuth Client

1. Go to [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials).
2. Create an **OAuth 2.0 Client ID** of type **Web application**.
3. Add your frontend origin(s) to **Authorized JavaScript origins**, e.g.
   `http://localhost:5173` for local dev. (No redirect URI needs to be
   registered - the frontend uses the popup/postMessage auth-code flow.)
4. Copy the generated **Client ID** and **Client Secret**.
5. Go to **APIs & Services → Library**, search for **Gmail API**, and enable it
   for this project.
6. Go to **APIs & Services → OAuth consent screen** and add the scope
   `https://www.googleapis.com/auth/gmail.modify` (read + mark-read/archive,
   no delete or settings changes). This is a **sensitive/restricted** scope:
   - While the app is in **Testing** publishing status, only users you
     explicitly add as **test users** on the consent screen can sign in.
   - Moving to **Production** with this scope requires Google's app
     verification review.

## 2. Create the Secrets Manager secret (before running Terraform)

Terraform does **not** create this secret - it only reads it by name. Create it
yourself, e.g.:

```sh
aws secretsmanager create-secret \
  --name google-oauth/credentials \
  --secret-string '{"client_id":"YOUR_CLIENT_ID.apps.googleusercontent.com","client_secret":"YOUR_CLIENT_SECRET"}'
```

Use that same name for the `google_oauth_secret_name` Terraform variable. Note
`client_secret` is now actually used (to exchange the authorization code and to
refresh access tokens), unlike in the identity-only version of this app.

## 3. Deploy the backend

```sh
cd backend
./build_layer.ps1          # installs google-auth/PyJWT/requests + common.py into terraform/build/layer
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit google_oauth_secret_name, allowed_origins, etc.
terraform init
terraform apply
```

Note the `api_endpoint` output - you'll need it for the frontend `.env`.

Re-run `build_layer.ps1` (from `backend/`) whenever
`lambdas/layer_requirements.txt` or `lambdas/common/common.py` changes, then
`terraform apply` again.

## 4. Run the frontend

```sh
cd frontend
cp .env.example .env.local   # set VITE_GOOGLE_CLIENT_ID and VITE_API_BASE_URL (the api_endpoint output)
npm install
npm run dev
```

Open the printed local URL and sign in with Google - you'll be asked to grant
Gmail access in the same consent step. You should land on `/dashboard` with
your profile pulled from `GET /auth/me`; click **Load recent emails** to
exercise `GET /gmail/messages`.

## Notes / limitations

- The frontend uses the OAuth **Authorization Code** flow (`useGoogleLogin({ flow: "auth-code" })`
  in popup/postMessage mode, no redirect URI to register). The backend
  exchanges the code for a Google `access_token` (short-lived, ~1h) and
  `refresh_token` (long-lived), which it uses to call Gmail on the user's
  behalf and to silently refresh the access token when it expires -
  `common.get_valid_google_access_token()` in
  `backend/lambdas/common/common.py`.
- This is separate from **our own session JWT** (default 60 min TTL, see
  `session_jwt_ttl_minutes`), which is what the frontend uses to authenticate
  to *our* API. When it expires the user has to sign in again - but that
  doesn't affect the stored Google refresh token, which keeps working across
  sessions until the user revokes access from their Google Account.
- If a user revokes the app's access from their Google Account permissions
  page, the stored `refresh_token` stops working; `GET /gmail/messages` then
  returns `401 { "error": "google_access_revoked" }` and the user needs to
  sign in again to re-consent.
- `google_refresh_token` in DynamoDB is a long-lived, sensitive credential.
  DynamoDB's default encryption-at-rest (AWS-owned key) applies; a
  customer-managed KMS key would be a reasonable hardening step before
  handling real user data in production.
- `terraform.tfvars` and `frontend/.env*` are gitignored - never commit real
  Google credentials or deployed API URLs you consider sensitive.
