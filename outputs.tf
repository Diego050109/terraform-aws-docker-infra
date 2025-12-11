output "alb_dns_name" {
  description = "DNS público del Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group"
  value       = aws_autoscaling_group.asg.name
}

output "target_group_arn" {
  description = "ARN del Target Group"
  value       = aws_lb_target_group.tg.arn
}
