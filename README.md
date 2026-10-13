# mvecc-home

Personal site: a few static pages and a plain-text blog in a private S3 bucket, served through
CloudFront at **https://mvecc.dev** and `www.mvecc.dev`. Terraform manages all
of it, including uploading the files.

```
site/index.html  ──edit this──►  terraform apply
                                      │  uploads changed files to S3
                                      ▼
                    S3 (private) ◄── CloudFront (OAC, ACM cert) ◄── Route 53
```

## Editing the site

The home page is **`site/index.html`**, and the styles every page shares
(light and dark) are in **`site/style.css`**. There's no build step. Open the file in a browser to preview it, or
serve the folder if you want absolute paths like `/favicon.svg` to resolve:

```bash
python3 -m http.server -d site 8000   # http://localhost:8000
```

Any other file you drop into `site/` is uploaded at the same path. S3 serves
the `Content-Type` each object was uploaded with, and `terraform/site.tf` maps
extensions to types. Add an entry there before adding a new kind of file.

## Writing a blog post

Add a `.txt` file to **`site/blogs/`**:

```
Title of the post
2026-10-13

First paragraph. Lines that wrap are joined back together.

Second paragraph. Links like https://example.com become clickable.
```

- Line 1 is the title, and line 2 is the date (`YYYY-MM-DD`).
- After a blank line comes the body. Separate paragraphs with a blank line.
- The file name becomes the URL: `my-first-post.txt` → `/blog/my-first-post/`.
  Use lowercase letters, digits and dashes. Plan fails with a message if you
  don't.

`terraform apply` renders each post into its own page and rebuilds `/blog/`,
newest first. The `.txt` files aren't uploaded. Delete a file and apply to
take the post down. To change how posts look, edit
`terraform/templates/post.html.tftpl`, `terraform/templates/blog.html.tftpl`,
or `site/style.css`.

To check a rendered page without deploying:

```bash
echo 'local.blog_rendered["blog/my-first-post/index.html"]' | terraform -chdir=terraform console
```

## Adding a page

Drop `site/about/index.html` in and it's served at `/about/`. A CloudFront
Function maps any URL ending in `/` to its `index.html`, and redirects `/about`
to `/about/`. Link to `/style.css` to get the shared look.

## Deploying

```bash
terraform -chdir=terraform init      # first time only
terraform -chdir=terraform apply
```

Terraform re-uploads any file whose contents changed. Objects are sent with
`Cache-Control: public, max-age=300`, so an edit is live everywhere within
five minutes, with no CloudFront invalidation needed.

The first apply takes a while: certificate validation and the CloudFront
rollout each take a few minutes, and DNS adds a few more. The
`cloudfront_domain` output works before the custom domain resolves.

## Prerequisites

- AWS credentials configured (`aws sts get-caller-identity` should succeed).
- **A Route 53 public hosted zone for the domain**, with the registrar
  delegated to its nameservers and the domain not on hold. Check with
  `dig NS mvecc.dev`.
- Terraform >= 1.5.

## Layout

```
site/index.html           home page
site/style.css            styles shared by every page
site/404.html             not-found page
site/blogs/*.txt          blog posts (rendered by Terraform, not uploaded as-is)
site/favicon.svg          tab icon
terraform/site.tf         S3 bucket, file uploads, CloudFront origin access
terraform/blog.tf         turns site/blogs/*.txt into /blog/ pages
terraform/templates/      HTML templates for the blog list and posts
terraform/functions/      CloudFront Function for /path/ → /path/index.html
terraform/dns.tf          ACM certificate, CloudFront distribution, Route 53
terraform/outputs.tf      URLs, bucket name, certificate
terraform/versions.tf     providers, optional S3 backend
```

## Configuration

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and
edit. `terraform.tfvars` is gitignored; the `.example` is not.

| Variable | Default | Notes |
| --- | --- | --- |
| `aws_region` | `us-east-2` | Where the bucket lives. The certificate is always in `us-east-1`. |
| `project_name` | `mvecc-home` | Prefixes the bucket and CloudFront resources. |
| `domain_name` | `mvecc.dev` | Apex domain. Needs a public hosted zone in the account. |
| `domain_aliases` | `["www.mvecc.dev"]` | Extra names on the certificate, CloudFront, and Route 53. |
| `hosted_zone_name` | `null` | Defaults to `domain_name`. Set it when serving a subdomain. |
| `cloudfront_price_class` | `PriceClass_100` | North America and Europe edges, the cheapest tier. |

## How it's wired

- **The bucket is private.** All public access is blocked. CloudFront reads it
  through an Origin Access Control, and the bucket policy only admits this
  one distribution.
- **Missing pages.** Without `s3:ListBucket`, S3 answers a missing key with
  403. CloudFront turns that into `404.html` with a 404 status.
- **DNS.** The apex and each alias get A and AAAA alias records to the
  distribution. A CNAME isn't allowed at the zone apex, and alias queries are
  free.

## Cost

Well under a dollar a month at personal-site traffic:

- **Route 53 hosted zone:** $0.50/month, the largest line item.
- **S3 storage and requests:** fractions of a cent.
- **CloudFront:** within the always-free tier (1 TB and 10M requests a month).
- **ACM certificate:** free.

## State

Terraform state is local by default. There's a commented S3 backend block in
`terraform/versions.tf`. Fill in a bucket and run
`terraform init -migrate-state` to move it.

## Tearing down

```bash
terraform -chdir=terraform destroy
```

The bucket has `force_destroy` set, so destroy empties it first.
