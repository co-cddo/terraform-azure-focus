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

output "billing_role_assignment_manual_action_required" {
  description = "Populated when the function app's managed identity is missing a billing role assignment. For EA customers this always requires manual action; for MCA customers it appears only when the billing_reader_assignments check detects a gap."
  value       = module.cost_forwarding.billing_role_assignment_manual_action_required
}
