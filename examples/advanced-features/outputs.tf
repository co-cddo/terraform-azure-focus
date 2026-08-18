output "billing_role_assignment_manual_action_required" {
  description = "Populated when the function app's managed identity is missing a billing role assignment. For EA customers this always requires manual action; for MCA customers it appears only when the billing_reader_assignments check detects a gap."
  value       = module.example.billing_role_assignment_manual_action_required
}

output "entra_app_role_assignment_manual_action_required" {
  description = "Populated when bringing your own app registration (existing_entra_application_client_id). Instructs your Entra team to run ConfigureExistingAppRegistration.ps1 to ensure the app role, identifier URI, and app role assignment are configured. Empty when the module creates the app registration itself."
  value       = module.example.entra_app_role_assignment_manual_action_required
}
