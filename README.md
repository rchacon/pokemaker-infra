# pokemaker-infra

Terraform for deploying **PokeMaker** to AWS. It only provisions infrastructure;
application code lives in [`pokemaker-api`](../pokemaker-api) and
[`pokemaker-app`](../pokemaker-app).

```text
                      https://app.pokemaker.fun   (DNS at Cloudflare)
                                     │
                              CloudFront (CDN)
                     ┌───────────────┴─────────────────┐
                 /* (static)                        /api/*  (+ secret X-Origin-Verify header)
                     │                                 │
           S3 site bucket (private, OAC)      api.pokemaker.fun:443 (Elastic IP)
                                                       │  security group: CloudFront only
                                          EC2 t4g.micro, Ubuntu 24.04 arm64
                                          Docker: ghcr.io/rchacon/pokemaker-api
                                          (one async Uvicorn process, TLS via Let's Encrypt)
                                   ┌──────────┬────────┴──────┬──────────────┐
                                DynamoDB   S3 artwork     SSM Parameter     OpenAI
                               (on-demand)  (private)    Store (secrets)  Images API
```

The API runs as **one long-lived async process**, so a single event loop
interleaves many requests that are mostly waiting on DynamoDB, S3 or OpenAI (see
`pokemaker-api`'s README). Serving the app and the API from **one CloudFront
distribution** means the frontend calls a relative `/api` path, the same as with
Vite's local proxy, so the API needs no CORS.

There is no load balancer, NAT Gateway, API Gateway or SSH. The server sits in
the default VPC with a public address that only CloudFront may reach.

## Layout

```text
modules/
├── storage/    DynamoDB table (on-demand, TTL, PITR) + private artwork bucket (CORS for exports)
├── server/     EC2 instance, instance role, CloudFront-only security group, Elastic IP,
│               log group, app settings in SSM, first-boot script (user_data.sh.tftpl)
├── frontend/   Private site bucket, CloudFront (OAC, redirect + SPA function, /api/* → server)
└── domain/     app.pokemaker.fun (ACM cert + CNAME) and api.pokemaker.fun (A record), at Cloudflare
envs/
└── prod/       Root module: wires the modules together, plus an optional AWS budget alert
tests/          Node tests for the CloudFront viewer-request function
```

To add another environment, copy `envs/prod` to `envs/dev` and change
`environment`, the SSM parameter names and the backend `key`.

## How the server works

- **Image:** `ghcr.io/rchacon/pokemaker-api:<version>`, an arm64 image built from
  `pokemaker-api` (public; nothing secret is in it), published by a tag-driven
  release pipeline (pokemaker-api#3).
- **First boot** (`modules/server/user_data.sh.tftpl`, run once by cloud-init):
  1. Installs Docker, certbot (with its Cloudflare DNS plugin) and the AWS CLI;
     adds swap; enables automatic security-update reboots at 10:00 UTC.
  2. Gets a Let's Encrypt certificate for `api.pokemaker.fun` using a Cloudflare
     DNS check, so port 80 never opens. Certbot renews it automatically, and a
     hook hands the new certificate to the container and restarts it.
  3. Installs `pokemaker-deploy` (below), then starts the last-deployed image, if
     there is one.
- **Deploys:** `pokemaker-api/scripts/deploy.sh` runs `pokemaker-deploy <image>`
  on the instance through **SSM Run Command**. That command:
  1. refreshes the app settings from SSM,
  2. pulls the image,
  3. replaces the container,
  4. health-checks `https://api.pokemaker.fun/api/health` the way CloudFront
     reaches it (same certificate and secret header).

  If the new container fails to start or isn't healthy, it rolls back to the
  previous image. Each successful deploy is recorded in SSM
  (`/pokemaker/prod/api-image`), so a replaced instance comes back on the same
  version by itself.
- **Logs:** the container's output goes to CloudWatch Logs
  (`/pokemaker/prod/api`, 14 days) through Docker's `awslogs` driver.
- **Credentials:** an **instance role** with the same least-privilege policy the
  app always had: its table, its family's artwork prefix, a handful of SSM
  parameters. There are no access keys anywhere.
- **Settings:** an env file stored in SSM (`/pokemaker/prod/api-config`) and
  written by Terraform. Change a setting with `terraform apply`, then redeploy.
- **The server holds no data.** Cards live in DynamoDB and artwork in S3, so the
  instance can be replaced at any time. Changing the bootstrap script replaces
  it automatically.

## Deploying

Prerequisites: Terraform ≥ 1.10, the AWS CLI with credentials, an S3 bucket for
Terraform state (an existing one is fine), and the `pokemaker.fun` zone in
Cloudflare.

### 1. Create the secrets (outside Terraform)

Secrets never appear in Terraform code, state or variables. Terraform only knows
the parameter *names* and grants the server permission to read them.

```bash
# OpenAI API key (paste it at the prompt; keeps it out of shell history)
read -rs OPENAI_KEY
aws ssm put-parameter --region us-east-1 --type SecureString \
  --name /pokemaker/prod/openai-api-key --value "$OPENAI_KEY"
unset OPENAI_KEY

# Secret that signs profile-unlock (PIN) tokens
aws ssm put-parameter --region us-east-1 --type SecureString \
  --name /pokemaker/prod/pin-token-secret \
  --value "$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

# Cloudflare token the server uses for its TLS certificate (DNS check).
# Create it from the "Edit zone DNS" template, limited to the pokemaker.fun zone.
read -rs CF_TOKEN
aws ssm put-parameter --region us-east-1 --type SecureString \
  --name /pokemaker/prod/cloudflare-dns-token --value "$CF_TOKEN"
unset CF_TOKEN
```

SecureString parameters in the Standard tier are free and use the AWS-managed
`aws/ssm` key. To rotate one, use `--overwrite`, then redeploy (or reboot, for
the Cloudflare token). To deploy without spending anything on images at first,
set `artwork_provider = "mock"`; the OpenAI parameter must still exist, but its
value is never used.

### 2. Apply

```bash
cd envs/prod
cp backend.hcl.example backend.hcl            # set your state bucket
cp terraform.tfvars.example terraform.tfvars  # Cloudflare zone ID + token, optional overrides
terraform init -backend-config=backend.hcl
terraform apply
```

The apply creates:
- the table, the buckets and CloudFront,
- the certificate for `app.pokemaker.fun`, validated through Cloudflare (usually
  a few minutes),
- the server, its Elastic IP and `api.pokemaker.fun`.

The server's first boot takes a few more minutes, mostly package installs and
the certificate; you can follow it in `/var/log/cloud-init-output.log` (see
Operations).

If the zone already has an `app` or `api` record, delete it first, or the create
fails with "record already exists". Records for the apex and `www` are never
touched; they belong to the marketing site.

### 3. Deploy the API

```bash
cd ../../../pokemaker-api
./scripts/deploy.sh           # the version in its pyproject.toml, or pass a tag
```

### 4. Seed the profiles

```bash
TABLE_NAME=pokemaker AWS_REGION=us-east-1 DYNAMODB_ENDPOINT_URL= S3_ENDPOINT_URL= \
  python scripts/seed_profiles.py --name kid1="Nickname 1" --name kid2="Nickname 2" \
    --name dad="Dad" --parent dad
```

(The empty endpoint variables override a local `.env`, so the script talks to AWS.)

### 5. Publish the frontend

```bash
cd ../pokemaker-app && ./scripts/deploy.sh    # reads the bucket and distribution from Terraform outputs
```

Then open https://app.pokemaker.fun.

## Operations

| Task | How |
| --- | --- |
| Ship a new API version | Publish `ghcr.io/rchacon/pokemaker-api:<version>`, then `./scripts/deploy.sh <version>` in pokemaker-api |
| Roll back | `./scripts/deploy.sh <older version>` |
| Change an app setting | Edit `terraform.tfvars`, `terraform apply`, then redeploy the current tag |
| Shell on the server | `aws ssm start-session --target "$(terraform output -raw instance_id)"` (no SSH) |
| Follow the API's logs | `aws logs tail /pokemaker/prod/api --follow` |
| First-boot log | in a session: `sudo tail -f /var/log/cloud-init-output.log` |
| Replace the server | `terraform apply -replace=module.server.aws_instance.server`; it redeploys the last image |

## Cost

At family scale, roughly **$10–11 a month** for AWS, plus OpenAI:

| Item | ≈ Monthly |
| --- | --- |
| EC2 `t4g.micro` (on-demand) | ~$6.10 |
| Public IPv4 (Elastic IP) | ~$3.65 |
| 10 GB gp3 root volume | ~$0.80 |
| DynamoDB on-demand, S3, CloudFront, CloudWatch Logs, SSM | cents (mostly free tiers) |

These are third-party estimates for us-east-1; check AWS's pricing pages. A
1-year Savings Plan or Spot (interruptions are tolerable here) can cut the
instance cost substantially.

**OpenAI image generation is the variable cost.** It's bounded by the API's
server-side daily quota (default 10 images per family per day). In the OpenAI
dashboard, give PokeMaker its own project with a monthly budget and email
alerts, and consider prepaid credits with auto-recharge off as a hard cap.

Set `budget_alert_email` to get an AWS Budgets email at 80% of actual and 100% of
forecast spend (default $20/month). The budget filters on the `app=pokemaker`
tag, so activate `app` as a **cost allocation tag** in the Billing console once
resources exist.

## Security: what this MVP does and does not protect

**There is no authentication.** https://app.pokemaker.fun is public:

- Anyone who learns the address can read every card and use up the daily
  artwork quota.
- Choosing a child's profile in the app is a convenience, **not authorization**.
- An unguessable URL is not a security mechanism.
- **Profile PINs** keep siblings from *changing* each other's cards. The API
  enforces them, with a lockout after 5 wrong tries, but they hide nothing.

What is in place:

- **The server only accepts CloudFront.** The security group allows port 443
  only from CloudFront's origin-facing address list. Those addresses are shared
  by every CloudFront distribution, so the app also requires a secret header
  that only *this* distribution sends (403 otherwise). Visiting
  `api.pokemaker.fun` directly doesn't work.
- **No SSH, no open ports besides 443.** Shell access is SSM Session Manager.
  IMDSv2 is required. Security updates install automatically, and the container
  runs as a non-root user.
- **No long-lived credentials:** an instance role, scoped to this app's table,
  its family's artwork prefix and a few SSM parameters.
- **Secrets in SSM Parameter Store:** created by hand, never in Terraform. The
  one exception is the CloudFront origin secret. Terraform generates it because
  CloudFront's configuration must contain it; it grants nothing beyond "this
  request came through our distribution".
- **Private S3:** the site goes through CloudFront OAC, and artwork only through
  short-lived presigned URLs.
- **Abuse limits:** a per-IP rate limit in the app (600 requests/min by default;
  a family shares one IP), request-size limits, and the daily artwork quota.

Before opening PokeMaker to other families, add Cognito (or another identity
provider), and have the API authorize every request against family membership.
For extra protection, consider AWS WAF on CloudFront (about $6 a month or
more). The data model already supports this without migrating card keys (see
`pokemaker-api/README.md`).

## Domain: app.pokemaker.fun and api.pokemaker.fun

`pokemaker.fun` is registered and DNS-hosted at Cloudflare. This repo manages
exactly two hostnames:

| Hostname | Record | Purpose |
| --- | --- | --- |
| `app.pokemaker.fun` | CNAME → CloudFront | The app. ACM certificate (us-east-1), validated via a Cloudflare DNS record |
| `api.pokemaker.fun` | A → the server's Elastic IP | CloudFront's origin for `/api/*`. Let's Encrypt certificate, issued on the server |

**The apex (`pokemaker.fun`) and `www.pokemaker.fun` are reserved for a separate
marketing site.** The domain module refuses them (a precondition, plus variable
validation on `app_subdomain` and `api_subdomain`).

All records are **DNS-only (grey cloud)**. CloudFront is already the CDN and
holds the app's certificate. For `api`, Cloudflare's proxy would hide
CloudFront's addresses from the server's firewall.

The raw `*.cloudfront.net` address 301-redirects to `https://app.pokemaker.fun`
(path and query kept), via the site's CloudFront Function
(`modules/frontend/viewer_request.js.tftpl`, tested in `tests/`).

The Cloudflare token for Terraform goes in the gitignored `terraform.tfvars`,
marked sensitive; provider credentials are not stored in state. The server's
copy (for certificate renewals) is the SSM parameter from step 1. It can be the
same token.

## CI

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:
`terraform fmt -check`, `terraform init -backend=false` + `validate` for
`envs/prod`, and the CloudFront function's Node tests. Nothing in CI touches AWS
or Cloudflare.
