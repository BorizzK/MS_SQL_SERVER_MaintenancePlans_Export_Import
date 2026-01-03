# MS SQL Server Maintenance Plans Export / Import

## Overview

This repository contains a set of **CMD scripts** designed to **export and import SQL Server Maintenance Plans together with their linked SQL Agent jobs and schedules**.

The solution supports **Microsoft SQL Server 2012–2019** and allows reliable migration or restoration of maintenance plans between servers or environments.

## Exported Objects

During export, the following files are generated:

- `<MaintenancePlanName>.dtsx`  
  — Maintenance Plan package

- `<MaintenancePlanName>.<SubplanName>.sql`  
  — SQL Agent job definition, including:
  - schedules  
  - job steps  
  - parameters  
  - alerts  
  - related metadata  

- `SysOperators.sql`  
  — SQL Agent Operators definitions

The scripts are intended for administrators who need a **repeatable, automated, and deterministic** way to manage Maintenance Plans.

---

## Key Features

- Export Maintenance Plans from MS SQL Server  
- Export linked SQL Agent Jobs and Schedules  
- Import Maintenance Plans with restored bindings  
- Supports SQL Server 2012–2019  
- Works **with or without SSIS installed**  
- Fully script-based (no GUI required during export/import)  
- Suitable for automation and CI/CD usage  

---

## Supported Operation Modes

### 1. Using `dtutil.exe` (Preferred)

Used when:
- SSIS is installed
- SQL Server Integration Services is available

Provides native and reliable handling of `.dtsx` packages.

---

### 2. Using `sqlcmd.exe` and `bcp.exe`

Used when:
- SSIS is not installed
- Only SQL Server client tools are available

In this mode:
- DTSX packages are extracted from `msdb`
- Binary data is handled via `bcp`
- XML content is reconstructed automatically

---

## Requirements

- Windows 7 SP1 / Windows Server 2008 R2 or later
- Microsoft SQL Server 2012–2019

- One of the following toolsets:
  - SQL Server Integration Services (SSIS) installed (optional)
  - SQL Server client utilities compatible with the installed SQL Server:
    - `sqlcmd.exe` (required)
    - `bcp.exe` (required if SSIS is not installed)
    - `dtutil.exe` (required if SSIS is installed)

- SQL Server Management Studio (SSMS) version compatible with the installed SQL Server

- **Administrator privileges on the SQL Server host**

- Access to:
  - `msdb`
  - SQL Server Agent metadata
  - Local file system on the SQL Server host

---

## What Is Exported

- Maintenance Plans (`.dtsx`)
- Subplans
- SQL Agent Jobs
- Job Schedules
- Job–Subplan bindings
- All required metadata for full restoration

---

## What Is NOT Required

- Manual DTSX editing  
- Manual job creation  
- PowerShell  
- Registry access  

---

## Export

```
  ExportMaintenancePlans.cmd
```

Result:
- Maintenance Plans exported as `.dtsx`
- SQL Agent jobs exported as `.sql`
- All dependencies preserved

---

## Import

```
  ImportMaintenancePlans.cmd
```

The import process:
- Imports DTSX packages into MSDB
- Restores SQL Agent jobs
- Restores schedules
- Rebinds jobs to maintenance subplans

---

## Important Note (SSMS Requirement)

After import, **SQL Server Management Studio (SSMS) must be opened once**, and **each imported Maintenance Plan must be opened and saved manually**.

This is required because:

- Internal **Reporting / Logging tasks** are not fully registered during script-based import
- SQL Server finalizes internal metadata only after the plan is opened in SSMS
- Without this step, some reporting components may not function correctly

This operation is required **once per imported plan**.

---

## Permissions

⚠️ **Administrator privileges are required**

Because the scripts:
- Access SQL Agent system tables
- Import DTSX packages into `msdb`
- Create and modify jobs and schedules
- Write temporary files to protected locations

---

## Compatibility (Tested)

|--------------------|-----------|
| SQL Server Version | Supported |
|--------------------|-----------|
| 2012               | V         |
| 2014               | V         |
| 2016               | V         |
| 2017               | V         |
| 2019               | V         |
|--------------------|-----------|

---

## Use Cases

- SQL Server migration  
- Disaster recovery  
- Environment synchronization  
- Version control of maintenance plans  
- Automated deployment of maintenance tasks  

## Planned Features

- Export and import of standalone SQL Server Agent objects not linked to Maintenance Plans:
  - Jobs
  - Alerts
  - Proxies
  - Built-in (system) objects will be automatically detected and excluded

