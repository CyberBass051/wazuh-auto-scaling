# 1. THE CONTAINERS (Empty Security Groups)
resource "aws_security_group" "alb_sg" {
  name   = "wazuh-lab-alb-sg"
  vpc_id = var.vpc_id
  description = "ALB Public Traffic"
}

resource "aws_security_group" "wazuh_app_sg" {
  name   = "wazuh-app-instances-sg"
  vpc_id = var.vpc_id
  description = "Wazuh App Private Traffic"
}

# 2. ALB RULES
# ALB Inbound - This is a public entry point, so 0.0.0.0/0 is required.
# trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}


# In production we would attach a AWS WAF to prevent SQL injection, XSS and bot attacks
# trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# IMPORTANT: ALB must be able to talk to the App
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb_sg.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.wazuh_app_sg.id
}

# 3. APP RULES
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.wazuh_app_sg.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb_sg.id
}

# Allow Agent Communication (Event/Logs)
resource "aws_vpc_security_group_ingress_rule" "app_from_agent_1514" {
    security_group_id            = aws_security_group.wazuh_app_sg.id
    from_port                    = 1514
    to_port                      = 1514
    ip_protocol                  = "tcp"
    referenced_security_group_id = aws_security_group.wazuh_app_sg.id
}

# Allow Agent Enrollment
resource "aws_vpc_security_group_ingress_rule" "app_from_agent_1515" {
    security_group_id            = aws_security_group.wazuh_app_sg.id
    from_port                    = 1515
    to_port                      = 1515
    ip_protocol                  = "tcp"
    referenced_security_group_id = aws_security_group.wazuh_app_sg.id
}

# Allow Wazuh API
resource "aws_vpc_security_group_ingress_rule" "app_from_API" {
    security_group_id            = aws_security_group.wazuh_app_sg.id
    from_port                    = 55000
    to_port                      = 55000
    ip_protocol                  = "tcp"
    referenced_security_group_id = aws_security_group.wazuh_app_sg.id
}

# Standard Egress for updates via NAT Gateway
resource "aws_vpc_security_group_egress_rule" "app_to_proxy" {
  security_group_id = aws_security_group.wazuh_app_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.proxy_ip
}