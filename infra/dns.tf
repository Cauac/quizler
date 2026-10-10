resource "aws_route53_zone" "main" {
  name = "quizler.app"
}

output "name_servers" {
  description = "Set these as the custom nameservers of quizler.app at Namecheap"
  value       = aws_route53_zone.main.name_servers
}

output "hosted_zone_id" {
  value = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate" "main" {
  provider = aws.us_east_1

  domain_name               = "quizler.app"
  subject_alternative_names = ["www.quizler.app"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.main.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Completes once the nameservers are switched at the registrar.
resource "aws_acm_certificate_validation" "main" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

locals {
  site_names = toset(["quizler.app", "www.quizler.app"])
}

resource "aws_route53_record" "site_a" {
  for_each = local.site_names

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_aaaa" {
  for_each = local.site_names

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudFront's origin. The value is the public IP of the running task and is owned by
# infra/scripts/sync-origin-dns.sh; the placeholder is a documentation address (RFC 5737).
resource "aws_route53_record" "origin" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "origin.quizler.app"
  type    = "A"
  ttl     = 60
  records = ["192.0.2.1"]

  lifecycle {
    ignore_changes = [records]
  }
}
