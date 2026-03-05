# Migrating to Azure Managed Redis

Support for migrating Azure Cache for Redis workloads into Azure Managed Redis (AMR).

## Overview

This repository provides tooling to migrate an existing **Azure Cache for Redis** instance to **Azure Managed Redis** using the ARM REST API. The migration is a DNS-switchover-based, live migration that keeps your endpoint and credentials intact — clients reconnect automatically without needing configuration changes.

## Contents

| Path | Description |
| ---- | ----------- |
| [Scripts/Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1](Scripts/Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1) | PowerShell script for driving the full migration lifecycle via ARM REST APIs |

## Prerequisites

- [Az PowerShell module](https://learn.microsoft.com/powershell/azure/install-azps-windows) installed
- An existing **Azure Cache for Redis** instance (source)
- An existing **Azure Managed Redis** instance (target) in the same subscription
- Sufficient RBAC permissions on both resources

## Script: Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1

The script supports four actions that map to the migration lifecycle:

| Action | Description |
| ------ | ----------- |
| `Validate` | Checks whether the source and target caches are compatible for migration and reports any disparities |
| `Migrate` | Initiates the migration (DNS switchover; data migration is skipped by default) |
| `Status` | Retrieves the current state of an in-progress or completed migration |
| `Cancel` | Cancels an in-progress migration |

### Parameters

| Parameter | Required | Default | Description |
| --------- | -------- | ------- | ----------- |
| `-Action` | Yes | — | One of `Validate`, `Migrate`, `Status`, `Cancel` |
| `-TargetResourceId` | Yes | — | Full ARM resource ID of the target Azure Managed Redis cluster |
| `-SourceResourceId` | For `Validate` / `Migrate` | — | Full ARM resource ID of the source Azure Cache for Redis instance |
| `-ForceMigrate` | No | `$false` | When `$true`, proceeds with migration even if parity validation returns warnings |
| `-TrackMigration` | No | `$false` | When set, blocks until the long-running operation completes |
| `-Environment` | No | `AzureCloud` | Azure environment. Allowed values: `AzureCloud`, `AzureChinaCloud`, `AzureUSGovernment`, `AzureGermanCloud` |
| `-Help` | No | `$false` | Displays full help for the script |

### Usage Examples

**Validate compatibility before migrating:**

```powershell
.\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 `
    -Action Validate `
    -SourceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/Redis/<source>" `
    -TargetResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/redisEnterprise/<target>"
```

**Start migration and wait for completion:**

```powershell
.\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 `
    -Action Migrate `
    -SourceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/Redis/<source>" `
    -TargetResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/redisEnterprise/<target>" `
    -TrackMigration
```

**Start migration, ignoring parity warnings:**

```powershell
.\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 `
    -Action Migrate `
    -SourceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/Redis/<source>" `
    -TargetResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/redisEnterprise/<target>" `
    -ForceMigrate $true
```

**Check migration status:**

```powershell
.\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 `
    -Action Status `
    -TargetResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/redisEnterprise/<target>"
```

**Cancel an in-progress migration:**

```powershell
.\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 `
    -Action Cancel `
    -TargetResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cache/redisEnterprise/<target>"
```

## Migration Flow

```mermaid
flowchart LR
    Validate --> Migrate --> Status
    Status -.-> Cancel
    style Cancel stroke-dasharray: 5 5
```

1. **Validate** — confirm the source and target are compatible.
2. **Migrate** — triggers the ARM long-running operation. DNS is switched so the source hostname begins resolving to the AMR endpoint.
3. **Status** — poll until the migration reports a terminal state (`Succeeded` or `Failed`).
4. **Cancel** — available while migration is still in progress.
