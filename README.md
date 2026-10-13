# pokemaker-infra

Terraform for deploying **PokeMaker** to AWS. It only provisions infrastructure;
application code lives in [`pokemaker-api`](../pokemaker-api) and
[`pokemaker-app`](../pokemaker-app).

```text
             https://pokemaker.fun   (www → 301 → apex; DNS at Cloudflare)
                                     │
                              CloudFront (CDN)
                     ┌───────────────┴────────────────┐
                 /* (static)                       /api/*
                     │                                │
           S3 site bucket (private, OAC)    API Gateway HTTP API (throttled)
                                                      │
                                             Lambda: FastAPI + Mangum
                                          (python3.12, arm64, no VPC)
                                   ┌──────────┬───────┴───────┬──────────────┐
                                DynamoDB   S3 artwork     SSM Parameter     OpenAI
                               (on-demand)  (private)    (OpenAI key)     Images API
```

Everything is pay-per-use. There are no EC2 instances, containers, NAT Gateways
or VPCs. Serving the app and the API from **one CloudFront origin** means the
frontend calls a relative `/api` path, the same as with Vite's local proxy, so
the API needs no CORS.

## Layout

```text
modules/
├── storage/    DynamoDB table (on-demand, TTL, PITR) + private artwork bucket (CORS for exports)
├── api/        Lambda, least-privilege IAM role, HTTP API with throttling, log groups
├── frontend/   Private site bucket, CloudFront (OAC, redirect + SPA function, /api/* behavior)
└── domain/     pokemaker.fun: ACM certificate (us-east-1) + Cloudflare DNS records
envs/
└── prod/       Root module: wires the modules together, plus an optional AWS budget alert
```

To add another environment, copy `envs/prod` to `envs/dev` and change
`environment` and the backend `key`.

## Deploying

Prerequisites: Terraform ≥ 1.10, the AWS CLI with credentials, an S3 bucket for
Terraform state (an existing one is fine), and Python 3.12 (to build the Lambda zip).

### 1. Build the Lambda package

```bash
cd ../pokemaker-api && ./scripts/build_lambda.sh   # → dist/lambda.zip
```

### 2. Store the OpenAI API key in SSM (outside Terraform)

The key never appears in Terraform code, state or variables. Terraform only knows
the parameter's *name* and grants the Lambda permission to read it.

```bash
read -rs OPENAI_KEY   # paste the key, press Enter (keeps it out of shell history)
aws ssm put-parameter --region us-east-1 \
  --name /pokemaker/prod/openai-api-key --type SecureString --value "$OPENAI_KEY"
unset OPENAI_KEY
```

Also create the secret that signs profile-unlock tokens (see "Profile PINs" below):

```bash
aws ssm put-parameter --region us-east-1 \
  --name /pokemaker/prod/pin-token-secret --type SecureString \
  --value "$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
```

A SecureString parameter in the Standard tier is free. It uses the AWS-managed
`aws/ssm` KMS key. Rotate the key with `--overwrite`. Warm Lambdas cache it for
their lifetime, so they pick up a new key on their next cold start.

> To deploy without spending anything on images first, set
> `artwork_provider = "mock"` and skip the OpenAI key (the PIN secret is still required).

### 3. Apply

```bash
cd envs/prod
cp backend.hcl.example backend.hcl            # set your state bucket
cp terraform.tfvars.example terraform.tfvars  # optional overrides (budget email, ...)
terraform init -backend-config=backend.hcl
terraform apply
```

### 4. Seed the profiles

```bash
cd ../../../pokemaker-api
TABLE_NAME=pokemaker AWS_REGION=us-east-1 DYNAMODB_ENDPOINT_URL= S3_ENDPOINT_URL= \
  python scripts/seed_profiles.py --name kid1="Nickname 1" --name kid2="Nickname 2" \
    --name dad="Dad" --parent dad
```

(The empty endpoint variables override a local `.env`, so the script talks to AWS.)

### 5. Publish the frontend

```bash
cd ../pokemaker-app && ./scripts/deploy.sh    # reads site_bucket + distribution id from Terraform outputs
```

Open the `site_url` output (https://pokemaker.fun once the custom domain is on). To ship a new API version, rebuild the zip and run
`terraform apply` again: the zip's hash changes, so Lambda updates.

## Cost

At family scale, AWS should cost cents per month, often nothing beyond free tiers:

| Service | Pricing model | Expected |
| --- | --- | --- |
| Lambda (arm64, 512 MB) | per request + GB-second | Free tier covers it |
| API Gateway HTTP API | $1 per million requests | ≈ $0 |
| DynamoDB on-demand (+PITR) | per request, per GB stored | Pennies |
| S3 (site + artwork) | per GB stored, per request | Pennies |
| CloudFront | per GB out, per request | Free tier covers it |
| CloudWatch Logs (14-day retention) | per GB ingested | Pennies |

**OpenAI image generation is the real cost.** It's bounded by the API's
server-side daily quota (default 10 images per family per day). Also, in the
**OpenAI dashboard**, create a dedicated project for PokeMaker with a low monthly
budget and email alerts. Treat those as alerts, not a guaranteed hard cap.

Set `budget_alert_email` to get an AWS Budgets email at 80% of actual and 100% of
forecast spend (default $10/month). The budget filters on the `app=pokemaker` tag,
so activate `app` as a **cost allocation tag** in the Billing console once
resources exist.

## Cost and abuse controls in this repo

- **API Gateway throttling**: 10 req/s steady, burst 20, across the whole API.
- **Lambda timeout** of 120 s, and optional `lambda_reserved_concurrency` (for
  example 5) to cap parallel invocations. New AWS accounts often have a total
  concurrency limit of 10 and can't reserve any; leave it `null` there.
- **Image parameters** (model, quality, size) are fixed in Lambda environment
  variables and validated against allowlists by the API.
- **Logs**: API Gateway access logs record metadata only, never request bodies
  (they contain the kids' card text). 14-day retention.

## Security: what this MVP does and does not protect

**There is no authentication.** Both the CloudFront URL and the raw
`api_endpoint` output are public:

- Anyone who learns either URL can read, change or delete cards and use up the
  daily artwork quota.
- Choosing a child's profile in the app is a convenience, **not authorization**.
- An unguessable URL is not a security mechanism.
- Throttling and quotas limit cost and abuse; they provide **no privacy**.

**Profile PINs** keep siblings out of each other's collections: changes to a
PIN-protected profile need a short-lived unlock token, checked by the API. They
are a household-level guard, not real security. Without accounts, anyone with
the address can still *read* every card, and a 4-digit PIN only resists
guessing because the API locks a profile for 5 minutes after 5 wrong tries.
Rotating the PIN secret parameter signs everyone out.

What is in place: private S3 buckets (site via CloudFront OAC; artwork only via
short-lived presigned URLs), least-privilege IAM (the Lambda can touch only its
table, this family's artwork prefix and one SSM parameter), encryption at rest,
HTTPS only, and no secrets in Terraform state.

Before opening PokeMaker to other families, add Cognito (or another identity
provider), have the API authorize every request against family membership, and
consider AWS WAF rate-based rules. The data model already supports this without
migrating card keys (see `pokemaker-api/README.md`).

## Custom domain: pokemaker.fun

The site is served at **https://pokemaker.fun**; `www.pokemaker.fun` and the raw
`*.cloudfront.net` address 301-redirect there (path and query kept), so there
is one canonical URL. The domain is registered and DNS-hosted at Cloudflare.

`modules/domain` creates:

- an ACM certificate for `pokemaker.fun` + `www.pokemaker.fun` in **us-east-1**
  (CloudFront's requirement, whatever `aws_region` is), validated via DNS;
- the validation records and the site's records in Cloudflare: the apex and
  `www` are CNAMEs to the distribution (Cloudflare flattens the apex CNAME).
  All are **DNS-only (grey cloud)**: CloudFront is already the CDN and holds the
  certificate, and a proxied record in front would be a second CDN.

The redirect is done by the site's CloudFront Function
(`modules/frontend/viewer_request.js.tftpl`), not a Cloudflare rule, so nothing
needs Cloudflare's proxy.

It's gated behind `enable_custom_domain` so the first apply needs no Cloudflare
access:

1. **Pass 1:** apply as described above and check the site on the
   `*.cloudfront.net` URL.
2. Create a Cloudflare API token from the **"Edit zone DNS"** template, limited
   to the `pokemaker.fun` zone only (never the Global API Key). Copy the
   **Zone ID** from the domain's Overview page.
3. **Pass 2:** add to `terraform.tfvars`:

   ```hcl
   enable_custom_domain = true
   cloudflare_zone_id   = "<zone id>"
   cloudflare_api_token = "<scoped token>"
   ```

   then `terraform apply`. The apply waits for ACM to issue the certificate
   (usually a few minutes once the validation records exist), attaches it to
   CloudFront, and points the apex and `www` at the distribution. CloudFront can
   take another ~5–15 minutes to roll out the aliases.

If the zone already has apex or `www` records (Cloudflare often adds parking
records for new domains), delete them first, or the create fails with a
"record already exists" error.

The Cloudflare token sits in the gitignored `terraform.tfvars` and is marked
sensitive, but like any provider credential it is not stored in state.
Treat `terraform.tfvars` as a secret file.
