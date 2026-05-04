resource "aws_autoscaling_group" "wazuh_asg" {
    desired_capacity     = 2
    max_size             = 4
    min_size             = 1
    vpc_zone_identifier  = [var.private_subnet_1, var.private_subnet_2]

    launch_template {
        id      = aws_launch_template.wazuh_lt.id
        version = "$Latest"
    }

    target_group_arns = [aws_lb_target_group.wazuh_tg.arn]
    health_check_type = "ELB"
    tag {
        key                 = "Name"
        value               = "wazuh-asg"
        propagate_at_launch = true
    }
}