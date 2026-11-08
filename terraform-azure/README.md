# Assignment 2 – Azure Deployment Guide

**Course:** 2DV705 – Virtualization, Cloud, and Storage  
**Platform:** Microsoft Azure  
**Infrastructure as Code:** Terraform  
**Region:** Austria East (`austriaeast`)

## 1. Overview

This project deploys a notes application on Microsoft Azure using Terraform and cloud-init.

The infrastructure consists of:

- One public Ubuntu web VM running Flask and Gunicorn.
- One private Ubuntu database VM running MariaDB.
- An Azure Virtual Network with separate web and database subnets.
- Network Security Groups (NSGs) and an Application Security Group (ASG).
- A NAT Gateway for outbound connectivity from the database subnet.
- An Azure Storage Account with a private `images` blob container.
- Azure Key Vault for the database password.
- System-assigned Managed Identities with Azure RBAC permissions.

The web application is accessible on HTTP port 80. The database is reachable from the web tier on port 3306, but has no public IP address.

## 2. Prerequisites

Install:

- Git
- Azure CLI
- Terraform 1.6 or newer
- Python 3 on Windows, for the secret creation command
- An Azure subscription with permission to create the required resources

The tested environment used Azure for Students.

Log in and select the correct subscription:

```cmd
az login
az account show -o table
```

## 3. Clone the repository

```cmd
git clone https://github.com/AbdullahSallat/lnu-notes.git
cd lnu-notes\terraform-azure
terraform init
```

## 4. Configure Terraform variables

Create a local file called `terraform.tfvars` containing:

```hcl
subscription_id = "YOUR_AZURE_SUBSCRIPTION_ID"
admin_cidr      = "YOUR_PUBLIC_IP/32"
```

Find the subscription ID:

```cmd
az account show --query id -o tsv
```

Find the public IP address:

```cmd
curl -4 https://api.ipify.org
```

The `terraform.tfvars` file is excluded from Git. Never commit credentials, private SSH keys, or Terraform State.

A matching SSH public key is required at the path referenced in `main.tf`. The deployment configuration also contains Azure resource names that may need to be made unique for another subscription.

## 5. Prepare Azure Key Vault

The database password is intentionally not generated or stored by Terraform.

For the first deployment, create the Key Vault and the current user's RBAC assignment before creating the virtual machines:

```cmd
terraform apply -target=azurerm_role_assignment.current_user_keyvault
```

After the Key Vault exists and the account has permission to manage secrets, create a cryptographically random password. On Windows, using the Python launcher:

```cmd
py -c "import secrets,subprocess; p=secrets.token_hex(24); subprocess.run(['az.cmd','keyvault','secret','set','--vault-name','kv2dv705b10c3b57','--name','lnu-db-password','--value',p,'--output','none'],check=True); print('Secret created')"
```

The command does not print the password. Replace the Key Vault name if the deployment configuration uses a different name.

For an existing deployment or a recovered Key Vault, first verify that the secret is already present. Do not overwrite an existing database password unnecessarily.

```cmd
az keyvault secret show --vault-name kv2dv705b10c3b57 --name lnu-db-password --query "{Name:name,Enabled:attributes.enabled}" -o table
```

## 6. Deploy the complete infrastructure

```cmd
terraform validate
terraform plan
terraform apply
```

Review the plan and confirm it.

Terraform provisions the network, virtual machines, storage, identities, and access rules. Cloud-init installs and configures the application and MariaDB.

The Managed Identities may require a short period for their RBAC permissions to become effective.

## 7. Verify the application

Display the generated addresses:

```cmd
terraform output
```

The expected outputs include:

- `web_public_ip`
- `db_private_ip`

Check application health:

```cmd
curl -i http://WEB_PUBLIC_IP/healthz
```

A successful response returns HTTP 200 and reports that the application, database, and storage are working.

Open `http://WEB_PUBLIC_IP` in a browser. Create a test note, upload an image, and verify that both are displayed.

Do not use private information in this HTTP-only demonstration environment.

## 8. Security controls

The infrastructure uses the following protections:

- SSH to the web VM is restricted to the administrator's `/32` address.
- The database VM has no public IP address.
- MariaDB port 3306 permits connections from the web ASG.
- The storage account blocks anonymous public blob access.
- The web VM accesses Blob Storage through its Managed Identity.
- Both VMs can retrieve the database secret from Key Vault through their Managed Identities.
- The database password is not managed as a Terraform secret resource.

Verify storage configuration:

```cmd
az storage account show --resource-group rg-2dv705 --name st2dv705b10c3b57 --query "{AllowBlobPublicAccess:allowBlobPublicAccess,MinimumTLS:minimumTlsVersion}" -o table
```

## 9. Terraform drift and configuration changes

Terraform detects changes made outside its configuration.

```cmd
terraform plan
```

Review the differences before using:

```cmd
terraform apply
```

For example, changing the administrative IP in `terraform.tfvars` causes Terraform to propose an update to the SSH firewall rule.

## 10. Destroy and rebuild

Remove the Terraform-managed infrastructure:

```cmd
terraform destroy
```

Confirm the operation and verify that the managed resources are removed.

Rebuild the infrastructure using the same configuration:

```cmd
terraform apply
```

The AzureRM provider is configured to avoid purging a soft-deleted Key Vault and to attempt its recovery. Before deploying new VMs, ensure that the `lnu-db-password` secret exists and is enabled.

After rebuilding, verify the application again using the new public IP address from `terraform output`.

## 11. Final cleanup

After the report and demonstration are complete:

```cmd
terraform destroy
```

Verify that the assignment resource group and its resources have been removed. Check for resources that may remain outside Terraform State, including retained soft-deleted Key Vault data.

Azure services such as NAT Gateway and public IP addresses may incur costs even when VMs are deallocated.

## 12. Limitations and handover notes

- The initial Key Vault secret creation is an explicit external bootstrap step.
- A new subscription may require different globally unique resource names.
- The administrator must provide their own SSH key and current public IP address.
- The deployment is designed for a course laboratory, not a production application.
- The public web application uses HTTP rather than HTTPS.
- The database and application require operational monitoring and additional hardening for production use.

The Terraform configuration and cloud-init scripts are maintained in Git. Azure Key Vault stores the database password separately from the repository.