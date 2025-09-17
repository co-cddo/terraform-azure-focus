output "aws_app_client_id" {
  description = "The aws app client id"
  value       = module.cost_forwarding.aws_app_client_id
}

output "recommendations_export_name" {
  description = "The name of the Azure Advisor recommendations export"
  value       = module.cost_forwarding.recommendations_export_name
}

output "carbon_export_name" {
  description = "The name of the carbon optimization export"
  value       = module.cost_forwarding.carbon_export_name
}
