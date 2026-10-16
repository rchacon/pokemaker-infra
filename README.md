# pokemaker-infra

Terraform for deploying **PokeMaker** to AWS. It only provisions infrastructure;
application code lives in [`pokemaker-api`](../pokemaker-api) and
[`pokemaker-app`](../pokemaker-app).

```text
        https://app.pokemaker.fun   (DNS at Cloudflare)
                       │
                CloudFront (CDN)
                       │
          S3 site bucket (private, OAC)

        DynamoDB (on-demand)      S3 artwork bucket (private)
```

This first part provisions the site and the data stores the API will use. The
API server, and CloudFront's `/api/*` route to it, come next.

## Layout

```text
modules/
├── storage/    DynamoDB table (on-demand, TTL, PITR) + private artwork bucket (CORS for exports)
├── frontend/   Private site bucket, CloudFront (OAC, redirect + SPA function)
└── domain/     app.pokemaker.fun (ACM cert + CNAME), at Cloudflare
envs/
└── prod/       Root module: wires the modules together, plus an optional AWS budget alert
tests/          Node tests for the CloudFront viewer-request function
```

To add another environment, copy `envs/prod` to `envs/dev` and change
`environment` and the backend `key`.

## Deploying

Prerequisites: Terraform ≥ 1.10, the AWS CLI with credentials, an S3 bucket for
Terraform state (an existing one is fine), and the `pokemaker.fun` zone in
Cloudflare.

### 1. Apply

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
  a few minutes).

If the zone already has an `app` record, delete it first, or the create
fails with "record already exists". Records for the apex and `www` are never
touched; they belong to the marketing site.

### 2. Publish the frontend

```bash
cd ../../../pokemaker-app && ./scripts/deploy.sh    # reads the bucket and distribution from Terraform outputs
```

Then open https://app.pokemaker.fun.

## Cost

At family scale, DynamoDB on-demand, S3 and CloudFront cost cents a month
(mostly free tiers).

Set `budget_alert_email` to get an AWS Budgets email at 80% of actual and 100% of
forecast spend (default $20/month). The budget filters on the `app=pokemaker`
tag, so activate `app` as a **cost allocation tag** in the Billing console once
resources exist.

## Security: what this MVP does and does not protect

**There is no authentication.** https://app.pokemaker.fun is public:

- Choosing a child's profile in the app is a convenience, **not authorization**.
- An unguessable URL is not a security mechanism.

What is in place:

- **Private S3:** the site goes through CloudFront OAC, and artwork only through
  short-lived presigned URLs.

Before opening PokeMaker to other families, add Cognito (or another identity
provider), and have the API authorize every request against family membership.
For extra protection, consider AWS WAF on CloudFront (about $6 a month or
more). The data model already supports this without migrating card keys (see
`pokemaker-api/README.md`).

## Domain: app.pokemaker.fun

`pokemaker.fun` is registered and DNS-hosted at Cloudflare. This repo manages
one hostname:

| Hostname | Record | Purpose |
| --- | --- | --- |
| `app.pokemaker.fun` | CNAME → CloudFront | The app. ACM certificate (us-east-1), validated via a Cloudflare DNS record |

**The apex (`pokemaker.fun`) and `www.pokemaker.fun` are reserved for a separate
marketing site.** The domain module refuses them (a precondition, plus variable
validation on `app_subdomain`).

All records are **DNS-only (grey cloud)**. CloudFront is already the CDN and
holds the app's certificate.

The raw `*.cloudfront.net` address 301-redirects to `https://app.pokemaker.fun`
(path and query kept), via the site's CloudFront Function
(`modules/frontend/viewer_request.js.tftpl`, tested in `tests/`).

The Cloudflare token for Terraform goes in the gitignored `terraform.tfvars`,
marked sensitive; provider credentials are not stored in state.

## CI

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:
`terraform fmt -check`, `terraform init -backend=false` + `validate` for
`envs/prod`, and the CloudFront function's Node tests. Nothing in CI touches AWS
or Cloudflare.
