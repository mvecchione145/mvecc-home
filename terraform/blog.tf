# Blog posts are plain text files in site/blogs/. Terraform renders each one
# into a page at /blog/<file name>/ and lists them all, newest first, at
# /blog/. The .txt files themselves are not uploaded.
#
# A post looks like this:
#
#   Title of the post
#   2026-10-13
#
#   First paragraph. Lines that wrap are joined back together.
#
#   Second paragraph. Links like https://example.com become clickable.

locals {
  blog_source = "${local.site_root}/blogs"

  # File name without .txt => its lines, with Windows line endings normalized.
  blog_lines = {
    for name in fileset(local.blog_source, "*.txt") :
    trimsuffix(name, ".txt") => split("\n", trimspace(replace(file("${local.blog_source}/${name}"), "\r\n", "\n")))
  }

  blog_posts = {
    for slug, lines in local.blog_lines : slug => {
      title = trimspace(lines[0])
      date  = trimspace(try(lines[1], ""))

      # Everything after the date, split on blank lines.
      paragraphs = [
        for p in split("\n\n", replace(join("\n", slice(lines, min(2, length(lines)), length(lines))), "/\\n[ \\t]*\\n\\s*/", "\n\n")) :
        trimspace(p) if trimspace(p) != ""
      ]
    }
  }

  # The values the post template is rendered with. Text is HTML-escaped here,
  # because templatefile does no escaping of its own.
  blog_pages = {
    for slug, post in local.blog_posts : slug => {
      slug       = slug
      date       = post.date
      date_human = try(formatdate("MMMM D, YYYY", "${post.date}T00:00:00Z"), post.date)

      title = replace(replace(replace(replace(post.title, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;")

      # The first paragraph, flattened and cut to search-snippet length.
      description = replace(replace(replace(replace(
        substr(replace(try(post.paragraphs[0], ""), "\n", " "), 0, 160),
      "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;")

      # Escape, then turn bare http(s) URLs into links. Trailing punctuation
      # is left out of the link so "see https://example.com." works.
      paragraphs = [
        for p in post.paragraphs : replace(
          replace(replace(replace(p, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"),
          "/(https?://[^\\s<>\"]*[^\\s<>\".,;:!?)])/",
          "<a href=\"$1\">$1</a>",
        )
      ]
    }
  }

  # Newest first; posts sharing a date fall back to file name order.
  blog_sort_keys = { for slug, post in local.blog_posts : "${post.date} ${slug}" => slug }
  blog_order     = [for key in reverse(sort(keys(local.blog_sort_keys))) : local.blog_sort_keys[key]]

  # S3 key => rendered HTML.
  blog_rendered = merge(
    {
      "blog/index.html" = templatefile("${path.module}/templates/blog.html.tftpl", {
        posts = [for slug in local.blog_order : local.blog_pages[slug]]
      })
    },
    {
      for slug, page in local.blog_pages :
      "blog/${slug}/index.html" => templatefile("${path.module}/templates/post.html.tftpl", page)
    },
  )

  blog_bad_names = [for slug in keys(local.blog_posts) : "${slug}.txt" if !can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", slug))]
  blog_bad_dates = [for slug, post in local.blog_posts : "${slug}.txt" if !can(formatdate("YYYY", "${post.date}T00:00:00Z"))]
}

resource "aws_s3_object" "blog" {
  for_each = local.blog_rendered

  bucket        = aws_s3_bucket.site.id
  key           = each.key
  content       = each.value
  etag          = md5(each.value)
  content_type  = local.content_types.html
  cache_control = "public, max-age=300"

  lifecycle {
    # The file name becomes the URL, so keep it to lowercase-and-dashes.
    precondition {
      condition     = length(local.blog_bad_names) == 0
      error_message = "Rename these posts to lowercase letters, digits and dashes (e.g. my-first-post.txt): ${join(", ", local.blog_bad_names)}"
    }

    precondition {
      condition     = length(local.blog_bad_dates) == 0
      error_message = "The second line of each post must be a date like 2026-10-13. Check: ${join(", ", local.blog_bad_dates)}"
    }
  }
}
