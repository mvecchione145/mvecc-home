# Build and push the site image as part of `terraform apply`. This is what
# removes the usual chicken-and-egg problem: the ECR repository, the image
# inside it, and the service that runs it are one ordered graph.

locals {
  app_root = abspath("${path.module}/..")

  # Everything that can change the contents of the image.
  source_files = sort(tolist(setunion(
    fileset(local.app_root, "src/**"),
    # Static files Vite copies to the site root verbatim, e.g. the favicon.
    fileset(local.app_root, "public/**"),
    toset([
      "Dockerfile",
      "nginx.conf",
      "index.html",
      "package.json",
      "package-lock.json",
      "vite.config.js",
    ]),
  )))

  # A content hash of the sources, used as the image tag. When you edit the
  # site the tag changes, which is what makes Terraform roll out a new
  # revision — no `latest` tag chasing, and no forced redeploys.
  source_hash = substr(
    sha256(join("", [for f in local.source_files : filesha256("${local.app_root}/${f}")])),
    0, 12,
  )

  image_tag = coalesce(var.image_tag, local.source_hash)
  image_ref = "${aws_ecr_repository.site.repository_url}:${local.image_tag}"
}

resource "docker_image" "site" {
  name = local.image_ref

  build {
    context    = local.app_root
    dockerfile = "Dockerfile"

    # Fargate runs X86_64 by default. Without this an Apple Silicon machine
    # would build an arm64 image that cannot start on the service.
    platform = "linux/amd64"
  }

  # Keep the built image in the local Docker cache on destroy.
  keep_locally = true
}

resource "docker_registry_image" "site" {
  name = docker_image.site.name

  # `terraform destroy` should not delete the pushed image out from under a
  # rollback; the ECR repository lifecycle policy handles cleanup instead.
  keep_remotely = true
}
