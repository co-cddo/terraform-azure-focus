# advanced-features

This example combines some of the newer features for customers who require more customisation:

- The cost/FOCUS feed is scoped at the top of a Platform Landing Zone management group hierarchy, rather than at the root management group level (avoids role assignments here too)
- An existing app registration is used (Azure RBAC/Entra ID separation)
- Existing private DNS zones are specified (must be resolvable from the target spoke network)
- Custom resource naming

> [!IMPORTANT]
> When specifying an existing app registration, you must add the 'AssumeRoleWithWebIdentity' app role and identifier URI 'api://<tenant-id>/GDS-AWS-Cost-Forwarding' yourself. If `manage_entra_app_role_assignment = false`, you will also need to assign the role to the function app managed identity.

<!-- BEGIN_TF_DOCS -->
## Providers

No providers.

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_billing_role_assignment_manual_action_required"></a> [billing\_role\_assignment\_manual\_action\_required](#output\_billing\_role\_assignment\_manual\_action\_required) | Populated when the function app's managed identity is missing a billing role assignment. For EA customers this always requires manual action; for MCA customers it appears only when the billing\_reader\_assignments check detects a gap. |
| <a name="output_entra_app_role_assignment_manual_action_required"></a> [entra\_app\_role\_assignment\_manual\_action\_required](#output\_entra\_app\_role\_assignment\_manual\_action\_required) | Populated only when bringing your own app registration (existing\_entra\_application\_client\_id) with manage\_entra\_app\_role\_assignment = false, for strict separation of duties: the 'AssumeRoleWithWebIdentity' app role must be assigned to the function app's managed identity MANUALLY by your Entra team. Empty when the module manages the binding. |
<!-- END_TF_DOCS -->
