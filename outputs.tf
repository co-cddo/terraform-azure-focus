output "aws_app_client_id" {
  description = "The aws app client id"
  value       = azuread_application.aws_app.client_id
}