output "aws_app_client_id" {
  description = "The aws app client id"
  value       = module.cost_forwarding.aws_app_client_id
}

output "focus_export_name" {
  description = "The name of the FOCUS cost export"
  value       = module.cost_forwarding.focus_export_name
}

output "utilization_export_name" {
  description = "The name of the cost utilization export"
  value       = module.cost_forwarding.utilization_export_name
}

output "carbon_export_name" {
  description = "The name of the carbon optimization export"
  value       = module.cost_forwarding.carbon_export_name
}
