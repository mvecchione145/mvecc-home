# mvecc-home

Personal site: a small React app served by nginx in a container, deployed to AWS
on **ECS Express Mode**, with everything — image build, ECR push, IAM, and the
service — managed by Terraform.

Express Mode is a single AWS resource that provisions the Fargate service, an
internet-facing load balancer with managed SSL/TLS, auto scaling, CloudWatch
logging, and a public HTTPS URL, so there's no VPC, ALB, or target group to
maintain here.

```
src/content.js  ──edit this──►  React app
                                     │
                    terraform apply  │  builds the image, pushes to ECR,
                                     ▼  rolls out the service
                              ECS Express Mode
                                     │
                     https://<service>.ecs.<region>.on.aws
```

## Filling in the site

Everything you'd want to write lives in **`src/content.js`** — name, tagline,
about paragraphs, a "Now" list, and links. Replace the `TODO:` strings. No JSX
required, and sections disappear on their own if you delete their key.

Layout and styling are in `src/App.jsx` and `src/styles.css`.

## Local development

The quickest way in, with hot reload:

```bash
docker compose --profile dev up      # http://localhost:5173
```

Your working tree is bind-mounted, so edits to `src/content.js` show up
immediately without a rebuild.

To run the exact image that gets deployed — same nginx config, SPA fallback,
cache headers, and `/healthz`:

```bash
docker compose up site               # http://localhost:8080
```

Compose builds for your native architecture, which is faster locally.
Terraform builds `linux/amd64` for Fargate.

If you'd rather not use Docker at all:

```bash
npm install
npm run dev                          # http://localhost:5173
```

## Deploying

There are no deploy scripts. Terraform builds the image, pushes it, and rolls
out the service in one dependency-ordered apply:

```bash
terraform -chdir=terraform init      # first time only
terraform -chdir=terraform apply
```

The URL is printed as the `site_url` output. The first apply takes several
minutes while the load balancer comes up; later ones are quick.

To deploy a change, edit the site and apply again. **The image tag is a hash of
your sources**, so Terraform notices the edit, builds a new image under a new
tag, and rolls the service forward. Nothing to remember and no `latest` tag to
chase.

```bash
terraform -chdir=terraform output site_url
terraform -chdir=terraform output deployed_image   # exact tag that is live
```

To roll back, pin the previous tag:

```bash
terraform -chdir=terraform apply -var 'image_tag=edddef3af708'
```

Images are built `--platform linux/amd64` to match Fargate's default
architecture. That matters on Apple Silicon: a native arm64 image will not
start on the service.

## Prerequisites

- AWS credentials configured (`aws sts get-caller-identity` should succeed).
- **Docker running locally.** Terraform's Docker provider drives your local
  daemon to build and push the image. Note that the provider does *not* read
  Docker CLI contexts: it assumes `/var/run/docker.sock`, which Docker Desktop
  on macOS does not create unless you enable "Allow the default Docker socket
  to be used". The `docker_host` variable defaults to Docker Desktop's real
  socket (`~/.docker/run/docker.sock`) instead. On Linux, or any other runtime,
  set it to whatever `docker context ls` shows as your endpoint.
- **A default VPC with public subnets in your region.** Express Mode puts its
  load balancer there unless you pass `network_configuration`. Verified present
  in `us-east-2`.
- **A Route 53 public hosted zone for the domain**, with the registrar
  delegated to its nameservers. Present and delegated for `mvecc.dev`.
- Terraform >= 1.5.

### Service-linked roles

Express Mode depends on three AWS-managed service-linked roles, for ECS,
Elastic Load Balancing, and Application Auto Scaling. Each service creates its
own on first use, but creation and the immediately following `AssumeRole` are
not atomic — the first `CreateExpressGatewayService` in a fresh account fails
with `InvalidParameterException: Unable to assume the service linked role`
because IAM has not propagated the role that call just created.

`terraform/iam.tf` creates the load balancing and auto scaling roles up front
and puts them behind the same propagation wait as the rest of the IAM, so the
first apply is deterministic rather than a race that needs a second run. The
ECS role is left out by default because it already exists in this account, and
declaring an existing service-linked role fails with `EntityAlreadyExists`. In
an account that has never run ECS, set `create_ecs_service_linked_role = true`.
Check with:

```bash
aws iam get-role --role-name AWSServiceRoleForECS
```

## Layout

```
src/content.js            your copy — the file to edit
src/App.jsx               page structure
src/styles.css            styling, light + dark
docker-compose.yml        local only: prod-parity `site`, hot-reload `dev`
Dockerfile                build → dev → serve stages
nginx.conf                SPA fallback, /healthz, cache headers
terraform/image.tf        source hashing, image build, ECR push
terraform/ecr.tf          image repository + lifecycle expiry
terraform/iam.tf          task execution + Express Mode infrastructure roles
terraform/main.tf         the Express Mode service
terraform/outputs.tf      site URL, deployed image, service ARN
terraform/versions.tf     providers, ECR registry auth, optional S3 backend
```

## Configuration

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and
edit. `terraform.tfvars` is gitignored; the `.example` is not.

| Variable | Default | Notes |
| --- | --- | --- |
| `aws_region` | `us-east-2` | Matches your configured CLI region. |
| `project_name` | `mvecc-home` | Names the ECR repo, IAM roles, and service. |
| `image_tag` | `null` | Unset means "hash of the sources". Set it only to roll back. |
| `cpu` / `memory` | unset | Unset takes the AWS default of 1 vCPU / 2 GB. |
| `health_check_path` | `/healthz` | Must match a route nginx serves. |
| `ecr_force_delete` | `true` | Lets `terraform destroy` remove the repo and its images. |
| `docker_host` | `null` | Defaults to Docker Desktop's socket. Set it for other runtimes. |
| `create_ecs_service_linked_role` | `false` | Set true only in an account that has never run ECS. |
| `domain_name` | `mvecc.dev` | Apex domain. Needs a public hosted zone in the account. |
| `domain_aliases` | `["www.mvecc.dev"]` | Extra names on the certificate, CloudFront, and Route 53. |
| `hosted_zone_name` | `null` | Defaults to `domain_name`. Set it when serving a subdomain. |
| `cloudfront_price_class` | `PriceClass_100` | North America and Europe edges, the cheapest tier. |

Auto scaling bounds are left at the AWS defaults. To pin them, set
`scaling_target` on the service resource in `terraform/main.tf`.

## Cost

There's no charge for Express Mode itself — you pay for what it creates:
Fargate compute, the Application Load Balancer, CloudWatch logs, and data
transfer. The load balancer is the floor, roughly $16–18/month, and Express
Mode shares one ALB across services with the same networking config. Dropping
`cpu`/`memory` to `"0.5"` / `"1"` trims the compute side.

The custom domain adds CloudFront request and transfer charges, which are
pennies at personal-site traffic. ACM certificates and Route 53 alias queries
are free; the hosted zone itself is $0.50/month.

## State

Terraform state is local by default, which is fine for one machine. There's a
commented S3 backend block in `terraform/versions.tf` — fill in a bucket and
run `terraform init -migrate-state` to move it.

## Custom domain

The site is served from **https://mvecc.dev** (and `www.mvecc.dev`), on top of
the `https://<service-name>.ecs.<region>.on.aws` URL Express Mode generates.
`terraform/dns.tf` provisions the whole chain: an ACM certificate in
`us-east-1`, its DNS validation records, a CloudFront distribution in front of
the Express Mode endpoint, and Route 53 alias records for each name.

Nothing here needs to run separately — it is part of the same
`terraform -chdir=terraform apply`.

### Why CloudFront rather than a record straight at the load balancer

Pointing Route 53 directly at the Express Mode ALB looks simpler but does not
hold up:

- Its HTTPS listener routes on a **host-header rule that only matches the
  generated `*.on.aws` name**, so a request for `mvecc.dev` falls through to
  the listener's fixed response.
- Its certificate only covers `*.on.aws`, so TLS fails on a custom name until
  you attach your own certificate to the listener.
- Express Mode deploys with **canary rollouts that swap the service between a
  primary and an alternate target group**. A listener rule you wrote by hand
  keeps forwarding to whichever target group it captured, so it points at a
  drained one after a deploy.
- Express Mode also shares one ALB across up to 25 services in a VPC and
  deprovisions unused ones, so the load balancer is not a stable anchor.

CloudFront avoids every one of those. It sends the **origin's** hostname in the
`Host` header — the managed `CachingOptimized` policy does not forward the
viewer's — so Express Mode's own host-header rule keeps matching and keeps
working across deployments. Every resource in `dns.tf` is owned by this
configuration rather than borrowed from Express Mode, and static assets pick up
edge caching along the way.

### Changing the domain

Set `domain_name`, and `domain_aliases` for any extra names (`[]` for apex
only). The zone must already exist in Route 53 in the same account; the
delegation for `mvecc.dev` is already live. If the domain is not the zone apex,
set `hosted_zone_name` to the zone.

First apply takes a while: certificate validation and the CloudFront rollout
are each a few minutes. DNS propagation adds a few more before the name
resolves.

## Tearing down

```bash
terraform -chdir=terraform destroy
```
