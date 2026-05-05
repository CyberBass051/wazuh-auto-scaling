# trivy:ignore:avd-aws-0053
resource "aws_lb" "wazuh_alb" {
  name               = "wazuh-lab-alb"
  internal           = false # Intentional: Public facing ALB for user access
    load_balancer_type = "application"
    security_groups    = [aws_security_group.alb_sg.id]
    subnets            = [var.alb_subnet_1, var.alb_subnet_2]

    drop_invalid_header_fields = true

    enable_deletion_protection = false # Set to true for production!
}

  # Target Group: Instances listen on Port 80
  resource "aws_lb_target_group" "wazuh_tg" {
    name     = "wazuh-target-group"
    port     = 80
    protocol = "HTTP"
    vpc_id   = var.vpc_id

    health_check {
        path = "/"
        interval = 30
    }
}

# Listener 1: Redirect HTTP (80) to HTTPS (443)
resource "aws_lb_listener" "http_redirect" {
    load_balancer_arn = aws_lb.wazuh_alb.arn
    port              = 80
    protocol          = "HTTP"

    default_action {
        type = "redirect"
        redirect {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301" 
        }
    }
}

# Listener 2: The Secure Entry Point
resource "aws_lb_listener" "http_actual" {
    load_balancer_arn = aws_lb.wazuh_alb.arn
    port              = "443"
    protocol          = "HTTPS"
    ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

    certificate_arn   = var.my_acm_certificate_arn

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.wazuh_tg.arn
    }

}