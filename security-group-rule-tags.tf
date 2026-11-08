# Existing installations import the exact physical rules in the caller before
# applying this revision. These blocks transfer state ownership without revoking
# the legacy permissions; they never destroy remote security-group rules.
removed {
  from = aws_security_group_rule.nat_instance_egress
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.nat_instance_ip_range_ingress
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.nat_instance_ipv6_range_ingress
  lifecycle {
    destroy = false
  }
}

resource "aws_vpc_security_group_egress_rule" "nat_instance" {
  for_each = {
    ipv4 = { ipv4 = "0.0.0.0/0", ipv6 = null }
    ipv6 = { ipv4 = null, ipv6 = "::/0" }
  }

  security_group_id = aws_security_group.nat_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = each.value.ipv4
  cidr_ipv6         = each.value.ipv6
  tags              = var.tags
}

# Index keys retain first-create support when a caller's CIDR values are computed
# from a newly created VPC. The list lengths and tag keys are known at plan time.
resource "aws_vpc_security_group_ingress_rule" "nat_instance_ipv4" {
  for_each = { for index, cidr in var.ingress_security_group_cidr_blocks : tostring(index) => cidr }

  security_group_id = aws_security_group.nat_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nat_instance_ipv6" {
  for_each = { for index, cidr in var.ingress_security_group_ipv6_cidr_blocks : tostring(index) => cidr }

  security_group_id = aws_security_group.nat_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = each.value
  tags              = var.tags
}

locals {
  # Match native SG resource tags: explicit tags override provider defaults.
  security_group_rule_tags = merge(data.aws_default_tags.current.tags, var.tags)
  nat_instance_ingress_rule_tags = {
    for pair in setproduct(range(length(local.nat_instance_ingress_sgs)), keys(local.security_group_rule_tags)) :
    "${pair[0]}/${pair[1]}" => {
      rule_index = pair[0]
      tag_key    = pair[1]
    }
  }
}

# Single-peer legacy rules already expose one physical ID. Keep their lifecycle
# and use it directly so replacement rules receive tags without discovery scans.
resource "aws_ec2_tag" "nat_instance_ingress" {
  for_each = local.nat_instance_ingress_rule_tags

  resource_id = aws_security_group_rule.nat_instance_ingress[each.value.rule_index].security_group_rule_id
  key         = each.value.tag_key
  value       = local.security_group_rule_tags[each.value.tag_key]
}

resource "aws_ec2_tag" "nat_lambda_egress" {
  for_each = local.security_group_rule_tags

  resource_id = aws_security_group_rule.nat_lambda_egress.security_group_rule_id
  key         = each.key
  value       = each.value
}
