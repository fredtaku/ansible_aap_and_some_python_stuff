# Ansible Automation Platform 2.4 - PostgreSQL Database Configuration Guide

## Overview

This document describes the PostgreSQL database configuration used in the Ansible Automation Platform (AAP) 2.4 installation. It covers the current deployment architecture and explains the different database configuration options available.

---

## Current Deployment Configuration

### Environment Details

| Component | Host IP Address | Role |
|-----------|-----------------|------|
| Automation Controller | 192.168.1.115 | Primary controller node |
| Automation Hub | 192.168.1.223 | Private content management |
| EDA Controller | 192.168.1.246 | Event-Driven Ansible |

### Inventory File Location

```
/root/aap2.4/ansible-automation-platform-setup-bundle-2.4-7.5-x86_64/inventory
```

---

## Database Configuration Summary

This installation uses a **distributed managed PostgreSQL** architecture. Each component runs its own local PostgreSQL instance. There is no centralized database server.

### Database Details by Component

| Component | Database Host | Database Name | Username | Port |
|-----------|---------------|---------------|----------|------|
| Automation Controller | Local (on 192.168.1.115) | `awx` | `awx` | 5432 |
| Automation Hub | Local (on 192.168.1.223) | `hub1` | `awx` | 5432 |
| EDA Controller | Local (on 192.168.1.246) | `eda1` | `awx` | 5432 |

### Inventory Configuration Excerpt

```ini
[database]
# Empty - each component uses local managed PostgreSQL

[all:vars]
# Controller database settings
pg_host=''
pg_port=5432
pg_database='awx'
pg_username='awx'
pg_password='<password>'
pg_sslmode='prefer'

# Automation Hub database settings
automationhub_pg_host='192.168.1.223'
automationhub_pg_port=5432
automationhub_pg_database='hub1'
automationhub_pg_username='awx'
automationhub_pg_password='<password>'

# EDA Controller database settings
automationedacontroller_pg_host='192.168.1.246'
automationedacontroller_pg_port=5432
automationedacontroller_pg_database='eda1'
automationedacontroller_pg_username='awx'
automationedacontroller_pg_password='<password>'
```

---

## Understanding Database Configuration Options

The AAP 2.4 installer supports three database deployment models. The behavior depends on two settings: the `[database]` inventory group and the `pg_host` variable.

### Option 1: Local Managed PostgreSQL (Current Setup)

**Configuration:**
- `[database]` group: Empty
- `pg_host`: Empty (`''`)

**Behavior:**
- The installer installs PostgreSQL locally on the first controller node.
- Each component (Hub, EDA) manages its own local PostgreSQL instance.
- The installer handles all database setup and configuration automatically.

**Best for:** Simple deployments, lab environments, or small-scale production setups.

---

### Option 2: External Pre-Existing PostgreSQL

**Configuration:**
- `[database]` group: Empty
- `pg_host`: Set to an IP address (e.g., `'192.168.1.50'`)

**Behavior:**
- The installer does NOT install or manage PostgreSQL.
- The installer expects PostgreSQL to already exist at the specified IP address.
- You must manually create databases, users, and permissions before running the installer.

**Example Configuration:**

```ini
[database]
# Empty - database is external and pre-existing

[all:vars]
pg_host='192.168.1.50'
pg_port=5432
pg_database='awx'
pg_username='awx'
pg_password='<password>'

automationhub_pg_host='192.168.1.50'
automationhub_pg_database='hub'

automationedacontroller_pg_host='192.168.1.50'
automationedacontroller_pg_database='eda'
```

**Prerequisites:**
1. Install PostgreSQL on the external server.
2. Create the required databases (`awx`, `hub`, `eda`).
3. Create the database user with appropriate permissions.
4. Configure PostgreSQL to accept remote connections.

**Best for:** Organizations with existing database infrastructure or dedicated database teams.

---

### Option 3: Dedicated Managed Database Server

**Configuration:**
- `[database]` group: Contains a host entry
- `pg_host`: Set to the same IP address

**Behavior:**
- The installer SSH connects to the specified database host.
- The installer installs and configures PostgreSQL on that host.
- All database setup is handled automatically by the installer.

**Example Configuration:**

```ini
[database]
192.168.1.50

[all:vars]
pg_host='192.168.1.50'
pg_port=5432
pg_database='awx'
pg_username='awx'
pg_password='<password>'

automationhub_pg_host='192.168.1.50'
automationhub_pg_database='hub'

automationedacontroller_pg_host='192.168.1.50'
automationedacontroller_pg_database='eda'
```

**Best for:** Production environments requiring a dedicated database server with installer-managed configuration.

---

## Configuration Options Comparison

| Setting | Local Managed | External Pre-Existing | Dedicated Managed |
|---------|---------------|----------------------|-------------------|
| `[database]` group | Empty | Empty | Contains host |
| `pg_host` value | Empty (`''`) | IP address | IP address |
| PostgreSQL installed by | Installer (on controller) | You (manually) | Installer (on DB host) |
| Database created by | Installer | You (manually) | Installer |
| Maintenance responsibility | Installer/You | You | Installer/You |

---

## Component Database Variable Reference

Each AAP component uses specific variables to define its database connection.

### Automation Controller

| Variable | Description |
|----------|-------------|
| `pg_host` | Database server hostname or IP. Empty for local. |
| `pg_port` | Database port. Default: `5432` |
| `pg_database` | Database name. Default: `awx` |
| `pg_username` | Database username. Default: `awx` |
| `pg_password` | Database password. |
| `pg_sslmode` | SSL connection mode. Options: `prefer`, `verify-full` |

### Automation Hub

| Variable | Description |
|----------|-------------|
| `automationhub_pg_host` | Database server hostname or IP. |
| `automationhub_pg_port` | Database port. Default: `5432` |
| `automationhub_pg_database` | Database name. |
| `automationhub_pg_username` | Database username. |
| `automationhub_pg_password` | Database password. |
| `automationhub_pg_sslmode` | SSL connection mode. |

### EDA Controller

| Variable | Description |
|----------|-------------|
| `automationedacontroller_pg_host` | Database server hostname or IP. |
| `automationedacontroller_pg_port` | Database port. Default: `5432` |
| `automationedacontroller_pg_database` | Database name. |
| `automationedacontroller_pg_username` | Database username. |
| `automationedacontroller_pg_password` | Database password. |
| `automationedacontroller_pg_sslmode` | SSL connection mode. |

---

## Architecture Diagrams

### Current Setup: Distributed Local Databases

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AAP 2.4 Current Architecture                         │
└─────────────────────────────────────────────────────────────────────────────┘

   ┌───────────────────┐    ┌───────────────────┐    ┌───────────────────┐
   │  192.168.1.115    │    │  192.168.1.223    │    │  192.168.1.246    │
   │                   │    │                   │    │                   │
   │  ┌─────────────┐  │    │  ┌─────────────┐  │    │  ┌─────────────┐  │
   │  │ Controller  │  │    │  │ Automation  │  │    │  │    EDA      │  │
   │  │             │  │    │  │    Hub      │  │    │  │ Controller  │  │
   │  └──────┬──────┘  │    │  └──────┬──────┘  │    │  └──────┬──────┘  │
   │         │         │    │         │         │    │         │         │
   │  ┌──────▼──────┐  │    │  ┌──────▼──────┐  │    │  ┌──────▼──────┐  │
   │  │ PostgreSQL  │  │    │  │ PostgreSQL  │  │    │  │ PostgreSQL  │  │
   │  │   (awx)     │  │    │  │   (hub1)    │  │    │  │   (eda1)    │  │
   │  └─────────────┘  │    │  └─────────────┘  │    │  └─────────────┘  │
   │                   │    │                   │    │                   │
   └───────────────────┘    └───────────────────┘    └───────────────────┘
```

### Alternative: Centralized Database Server

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     AAP 2.4 Centralized Database Architecture               │
└─────────────────────────────────────────────────────────────────────────────┘

   ┌───────────────────┐    ┌───────────────────┐    ┌───────────────────┐
   │  192.168.1.115    │    │  192.168.1.223    │    │  192.168.1.246    │
   │                   │    │                   │    │                   │
   │  ┌─────────────┐  │    │  ┌─────────────┐  │    │  ┌─────────────┐  │
   │  │ Controller  │  │    │  │ Automation  │  │    │  │    EDA      │  │
   │  │             │  │    │  │    Hub      │  │    │  │ Controller  │  │
   │  └──────┬──────┘  │    │  └──────┬──────┘  │    │  └──────┬──────┘  │
   │         │         │    │         │         │    │         │         │
   └─────────┼─────────┘    └─────────┼─────────┘    └─────────┼─────────┘
             │                        │                        │
             └────────────────────────┼────────────────────────┘
                                      │
                                      ▼
                          ┌───────────────────┐
                          │  192.168.1.50     │
                          │                   │
                          │  ┌─────────────┐  │
                          │  │ PostgreSQL  │  │
                          │  │             │  │
                          │  │ ┌─────────┐ │  │
                          │  │ │   awx   │ │  │
                          │  │ ├─────────┤ │  │
                          │  │ │   hub   │ │  │
                          │  │ ├─────────┤ │  │
                          │  │ │   eda   │ │  │
                          │  │ └─────────┘ │  │
                          │  └─────────────┘  │
                          │                   │
                          └───────────────────┘
```

---

## Document Information

| Field | Value |
|-------|-------|
| Created | December 2025 |
| AAP Version | 2.4.7.5 |
| Bundle | ansible-automation-platform-setup-bundle-2.4-7.5-x86_64 |
