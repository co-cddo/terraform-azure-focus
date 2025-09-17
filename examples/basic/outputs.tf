output "aws_app_client_id" {
  description = "The aws app client id"
  value       = module.example.aws_app_client_id
}

output "recommendations_export_name" {
  description = "The name of the Azure Advisor recommendations export"
  value       = module.example.recommendations_export_name
}

output "carbon_export_name" {
  description = "The name of the carbon optimization export"
  value       = module.example.carbon_export_name
}
