output "billing_role_assignment_manual_action_required" {
  description = "Populated when the function app's managed identity is missing a billing role assignment. For EA customers this always requires manual action; for MCA customers it appears only when the billing_reader_assignments check detects a gap."
  value       = module.example.billing_role_assignment_manual_action_required
}

output "entra_app_role_assignment_manual_action_required" {
  description = "Populated only when bringing your own app registration (existing_entra_application_client_id) with manage_entra_app_role_assignment = false, for strict separation of duties: the 'AssumeRoleWithWebIdentity' app role must be assigned to the function app's managed identity MANUALLY by your Entra team. Empty when the module manages the binding."
  value       = module.example.entra_app_role_assignment_manual_action_required
}
