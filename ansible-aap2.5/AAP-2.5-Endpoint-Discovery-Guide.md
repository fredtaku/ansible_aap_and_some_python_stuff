# AAP 2.5 Endpoint Discovery & Health Check Guide

**Purpose:** Systematic guide for discovering, understanding, and testing all endpoints in an Ansible Automation Platform 2.5 containerized installation.

**Last Updated:** December 2025  
**AAP Version:** 2.5 (Containerized / Growth Topology)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Environment Reference](#2-environment-reference)
3. [Container Discovery](#3-container-discovery)
4. [API Endpoint Map](#4-api-endpoint-map)
5. [Health Check Commands](#5-health-check-commands)
6. [Database Diagnostics](#6-database-diagnostics)
7. [Container Log Analysis](#7-container-log-analysis)
8. [Troubleshooting Decision Tree](#8-troubleshooting-decision-tree)
9. [Quick Reference Scripts](#9-quick-reference-scripts)
10. [Key Architectural Insights](#10-key-architectural-insights)

---

## 1. Architecture Overview

### Traffic Flow Model

All client requests flow through the Platform Gateway, which routes to backend services based on URL path:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           AAP 2.5 REQUEST FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Client Request                                                                │
│        │                                                                        │
│        ▼                                                                        │
│   ┌─────────────────────────────────────────────────────────────────────────┐  │
│   │                    PLATFORM GATEWAY (Envoy Proxy)                        │  │
│   │                                                                          │  │
│   │   Routes by URL path prefix:                                             │  │
│   │   ┌────────────────────┬──────────────────────────────────────────────┐ │  │
│   │   │ /api/gateway/*     │ → Gateway Service (auth, users, config)      │ │  │
│   │   │ /api/v2/*          │ → Automation Controller (jobs, inventories)  │ │  │
│   │   │ /api/galaxy/*      │ → Automation Hub / Pulp (collections)        │ │  │
│   │   │ /api/eda/*         │ → Event-Driven Ansible (activations, rules)  │ │  │
│   │   └────────────────────┴──────────────────────────────────────────────┘ │  │
│   └─────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                          │
│                    ┌─────────────────┼─────────────────┐                       │
│                    │                 │                 │                       │
│                    ▼                 ▼                 ▼                       │
│            ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                │
│            │ Controller  │   │     Hub     │   │     EDA     │                │
│            └──────┬──────┘   └──────┬──────┘   └──────┬──────┘                │
│                   │                 │                 │                        │
│                   └─────────────────┼─────────────────┘                        │
│                                     ▼                                          │
│                           ┌─────────────────┐                                  │
│                           │   PostgreSQL    │                                  │
│                           │  (All State)    │                                  │
│                           └─────────────────┘                                  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Primary Function | Key Containers |
|-----------|------------------|----------------|
| **Gateway** | Authentication, routing, SSO | gateway, gateway-proxy, redis-tcp |
| **Controller** | Job execution, inventories, credentials | controller-web, controller-task, receptor |
| **Hub** | Collection management, content sync | hub-api, hub-web, hub-content, hub-worker |
| **EDA** | Event processing, rulebook activations | eda-api, eda-web, eda-worker, eda-scheduler |
| **PostgreSQL** | All persistent state, task queues | systemd service (external) |

---

## 2. Environment Reference

### Node Inventory

| Node | Hostname | IP Address | Role | Key Containers |
|------|----------|------------|------|----------------|
| 1 | aap2.5-node1.example.com | 192.168.1.236 | Controller | controller-web, controller-task, receptor |
| 2 | aap2.5-node2.example.com | 192.168.1.231 | EDA | eda-api, eda-web, eda-worker |
| 3 | aap2.5-node3.example.com | 192.168.1.232 | EDA | eda-api, eda-web, eda-worker |
| 4 | aap2.5-node4.example.com | 192.168.1.234 | Hub | hub-api, hub-web, hub-worker-1/2 |
| 5 | aap2.5-node5.example.com | 192.168.1.235 | Hub | hub-api, hub-web, hub-worker-1/2 |
| 6 | aap2.5-node6.example.com | 192.168.1.228 | Database | PostgreSQL 15 (systemd) |
| 7 | aap2.5-node7.example.com | 192.168.1.177 | Gateway | gateway, gateway-proxy |
| 8 | aap2.5-node8.example.com | 192.168.1.233 | Gateway | gateway, gateway-proxy |
| 9 | aap2.5-node9.example.com | 192.168.1.237 | Execution | receptor |

### Connection Variables

```bash
# Set these for your environment
export GATEWAY_HOST="192.168.1.177"
export CONTROLLER_HOST="192.168.1.236"
export HUB_HOST="192.168.1.234"
export EDA_HOST="192.168.1.231"
export DB_HOST="192.168.1.228"
export AAP_USER="admin"
export AAP_PASS="<your-password>"
export SSH_USER="tfred"
```

---

## 3. Container Discovery

### Step 3.1: List Containers on Any Node

```bash
# Generic command - replace HOST with target IP
ssh ${SSH_USER}@<HOST> "podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
```

### Step 3.2: Expected Containers by Role

#### Controller Node

```bash
ssh ${SSH_USER}@${CONTROLLER_HOST} "podman ps --format '{{.Names}}'"
```

Expected output:

```
automation-controller-web      # API and Web UI
automation-controller-task     # Job execution engine
automation-controller-rsyslog  # Centralized logging
receptor                       # Mesh networking
redis-unix                     # Local cache
```

#### Hub Node

```bash
ssh ${SSH_USER}@${HUB_HOST} "podman ps --format '{{.Names}}'"
```

Expected output:

```
automation-hub-web       # Nginx reverse proxy
automation-hub-api       # Pulp API (Django/Gunicorn)
automation-hub-content   # Content serving
automation-hub-worker-1  # Background task worker
automation-hub-worker-2  # Background task worker
redis-unix               # Cache (Unix socket)
redis-tcp                # Cache (TCP)
```

#### EDA Node

```bash
ssh ${SSH_USER}@${EDA_HOST} "podman ps --format '{{.Names}}'"
```

Expected output:

```
eda-api              # API service
eda-web              # Web interface
eda-worker           # Event processing
eda-scheduler        # Task scheduler
eda-daphne           # WebSocket server
redis-tcp            # Message cache
```

#### Gateway Node

```bash
ssh ${SSH_USER}@${GATEWAY_HOST} "podman ps --format '{{.Names}}'"
```

Expected output:

```
automation-gateway        # Django application (auth, config)
automation-gateway-proxy  # Envoy proxy (routing)
redis-tcp                 # Session cache
```

### Step 3.3: Check Systemd Services

```bash
# List all AAP-related user services
ssh ${SSH_USER}@<HOST> "systemctl --user list-units -t service --all | grep -E '(controller|hub|eda|gateway|redis|receptor)'"
```

---

## 4. API Endpoint Map

### Base URL Pattern

All API calls go through the Gateway:

```
https://<GATEWAY_HOST>/api/<component>/<version>/<resource>/
```

### Endpoint Reference Table

| Component | Base Path | Auth Required | Example Endpoint |
|-----------|-----------|---------------|------------------|
| **Gateway** | `/api/gateway/v1/` | Varies | `/api/gateway/v1/ping/` |
| **Controller** | `/api/v2/` | Yes | `/api/v2/ping/` |
| **Hub (Pulp)** | `/api/galaxy/pulp/api/v3/` | Varies | `/api/galaxy/pulp/api/v3/status/` |
| **Hub (Galaxy)** | `/api/galaxy/v3/` | Yes | `/api/galaxy/v3/collections/` |
| **EDA** | `/api/eda/v1/` | Yes | `/api/eda/v1/status/` |

### Key Endpoints by Component

#### Gateway Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/gateway/v1/ping/` | GET | No | Basic health check |
| `/api/gateway/v1/me/` | GET | Yes | Current user info |
| `/api/gateway/v1/users/` | GET | Yes | List platform users |

#### Controller Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/v2/ping/` | GET | No | Health check |
| `/api/v2/config/` | GET | Yes | Version, license info |
| `/api/v2/instances/` | GET | Yes | Node capacity/health |
| `/api/v2/jobs/` | GET | Yes | Job history |
| `/api/v2/inventories/` | GET | Yes | Inventory list |
| `/api/v2/projects/` | GET | Yes | Project list |

#### Hub Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/galaxy/pulp/api/v3/status/` | GET | No | Pulp component status |
| `/api/galaxy/v3/collections/` | GET | Yes | List collections |
| `/api/galaxy/v3/plugin/ansible/content/published/collections/index/` | GET | Yes | Published collections |
| `/api/galaxy/_ui/v1/auth/token/` | POST | Yes | Generate API token |

#### EDA Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/eda/v1/status/` | GET | No | EDA health status |
| `/api/eda/v1/activations/` | GET | Yes | Rulebook activations |
| `/api/eda/v1/projects/` | GET | Yes | EDA projects |
| `/api/eda/v1/decision-environments/` | GET | Yes | Decision environments |

---

## 5. Health Check Commands

### Step 5.1: Gateway Health

```bash
# Unauthenticated ping (should always work if gateway is up)
curl -sk https://${GATEWAY_HOST}/api/gateway/v1/ping/

# Authenticated check
curl -sk https://${GATEWAY_HOST}/api/gateway/v1/me/ \
  -u ${AAP_USER}:${AAP_PASS}

# Expected: JSON response with user details
# Failure: "no healthy upstream" = backend connection issue
```

### Step 5.2: Controller Health

```bash
# Basic ping (no auth required)
curl -sk https://${GATEWAY_HOST}/api/v2/ping/

# Expected response:
# {"ha": false, "version": "4.x.x", "active_node": "...", ...}

# Instance capacity check (requires auth)
curl -sk https://${GATEWAY_HOST}/api/v2/instances/ \
  -u ${AAP_USER}:${AAP_PASS}

# Configuration and version
curl -sk https://${GATEWAY_HOST}/api/v2/config/ \
  -u ${AAP_USER}:${AAP_PASS}
```

### Step 5.3: Hub Health

```bash
# Pulp status (detailed component health)
curl -sk https://${GATEWAY_HOST}/api/galaxy/pulp/api/v3/status/

# Expected: JSON with database, redis, content-app, workers status

# List collections (requires auth)
curl -sk https://${GATEWAY_HOST}/api/galaxy/v3/collections/ \
  -u ${AAP_USER}:${AAP_PASS}
```

### Step 5.4: EDA Health

```bash
# EDA status
curl -sk https://${GATEWAY_HOST}/api/eda/v1/status/

# List activations (requires auth)
curl -sk https://${GATEWAY_HOST}/api/eda/v1/activations/ \
  -u ${AAP_USER}:${AAP_PASS}
```

### Step 5.5: Direct Backend Health (Bypass Gateway)

Use when gateway shows "no healthy upstream":

```bash
# Controller - direct to container
ssh ${SSH_USER}@${CONTROLLER_HOST} \
  "podman exec automation-controller-web curl -s http://localhost:8013/api/v2/ping/"

# Hub - direct to API container
ssh ${SSH_USER}@${HUB_HOST} \
  "podman exec automation-hub-api curl -s http://localhost:24817/api/galaxy/pulp/api/v3/status/"

# EDA - direct to API container
ssh ${SSH_USER}@${EDA_HOST} \
  "podman exec eda-api curl -s http://localhost:8000/api/eda/v1/status/"
```

---

## 6. Database Diagnostics

### Critical Insight

> **Hub uses PostgreSQL for task queuing, NOT Redis.**  
> Pulpcore implements its own task system using PostgreSQL LISTEN/NOTIFY and advisory locks.  
> Redis is only used for Django caching.

### Step 6.1: Connection Health

```bash
# Current connection count
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c 'SELECT count(*) AS active_connections FROM pg_stat_activity;'"

# Max connections setting
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c 'SHOW max_connections;'"

# Connections by database
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c 'SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname ORDER BY count DESC;'"
```

### Step 6.2: Connection State Analysis

```bash
# Connections by state
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c 'SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count DESC;'"

# Connections by client IP
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c 'SELECT client_addr, count(*) FROM pg_stat_activity GROUP BY client_addr ORDER BY count DESC;'"

# Long-running queries
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c \"SELECT pid, now() - query_start AS duration, left(query, 50) FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;\""
```

### Step 6.3: Hub Task Queue Status

```bash
# Task count by state
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d hub -c 'SELECT state, count(*) FROM core_task GROUP BY state ORDER BY count DESC;'"

# Stuck tasks (waiting > 5 minutes)
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d hub -c \"SELECT pulp_id, name, state, pulp_created FROM core_task WHERE state = 'waiting' AND pulp_created < NOW() - INTERVAL '5 minutes' ORDER BY pulp_created;\""

# Running tasks
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d hub -c \"SELECT pulp_id, name, worker, started_at FROM core_task WHERE state = 'running';\""

# Failed tasks (recent)
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d hub -c \"SELECT pulp_id, name, error->>'description' AS error FROM core_task WHERE state = 'failed' ORDER BY finished_at DESC LIMIT 5;\""
```

### Step 6.4: Hub Worker Registration

```bash
# Check registered workers
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d hub -c 'SELECT name, last_heartbeat, versions FROM core_worker ORDER BY last_heartbeat DESC;'"

# Check LISTEN connections (workers waiting for tasks)
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -c \"SELECT pid, client_addr, query FROM pg_stat_activity WHERE datname = 'hub' AND query LIKE 'LISTEN%';\""
```

### Step 6.5: Controller Job Status

```bash
# Recent jobs
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d awx -c 'SELECT id, name, status, started, finished FROM main_unifiedjob ORDER BY started DESC LIMIT 10;'"

# Failed jobs
ssh ${SSH_USER}@${DB_HOST} \
  "sudo -u postgres psql -d awx -c \"SELECT id, name, status, job_explanation FROM main_unifiedjob WHERE status = 'failed' ORDER BY finished DESC LIMIT 5;\""
```

---

## 7. Container Log Analysis

### Step 7.1: Gateway Logs

```bash
# Gateway application logs
ssh ${SSH_USER}@${GATEWAY_HOST} \
  "podman logs automation-gateway 2>&1 | tail -50"

# Envoy proxy logs (routing issues)
ssh ${SSH_USER}@${GATEWAY_HOST} \
  "podman logs automation-gateway-proxy 2>&1 | tail -50"

# Common error patterns to look for:
# - "no healthy upstream" = backend unreachable
# - "connection refused" = backend container down
# - "database connection failed" = PostgreSQL issue
```

### Step 7.2: Controller Logs

```bash
# Web container (API errors)
ssh ${SSH_USER}@${CONTROLLER_HOST} \
  "podman logs automation-controller-web 2>&1 | tail -50"

# Task container (job execution issues)
ssh ${SSH_USER}@${CONTROLLER_HOST} \
  "podman logs automation-controller-task 2>&1 | tail -50"

# Receptor (mesh networking)
ssh ${SSH_USER}@${CONTROLLER_HOST} \
  "podman logs receptor 2>&1 | tail -30"
```

### Step 7.3: Hub Logs

```bash
# API container
ssh ${SSH_USER}@${HUB_HOST} \
  "podman logs automation-hub-api 2>&1 | tail -50"

# Worker containers (task execution)
ssh ${SSH_USER}@${HUB_HOST} \
  "podman logs automation-hub-worker-1 2>&1 | tail -50"

ssh ${SSH_USER}@${HUB_HOST} \
  "podman logs automation-hub-worker-2 2>&1 | tail -50"

# Content container
ssh ${SSH_USER}@${HUB_HOST} \
  "podman logs automation-hub-content 2>&1 | tail -30"
```

### Step 7.4: EDA Logs

```bash
# API logs
ssh ${SSH_USER}@${EDA_HOST} \
  "podman logs eda-api 2>&1 | tail -50"

# Worker logs
ssh ${SSH_USER}@${EDA_HOST} \
  "podman logs eda-worker 2>&1 | tail -50"

# Scheduler logs
ssh ${SSH_USER}@${EDA_HOST} \
  "podman logs eda-scheduler 2>&1 | tail -30"
```

### Step 7.5: Follow Logs in Real-Time

```bash
# Follow any container logs
ssh ${SSH_USER}@<HOST> "podman logs -f <container-name>"

# Example: follow Hub worker
ssh ${SSH_USER}@${HUB_HOST} "podman logs -f automation-hub-worker-1"
```

---

## 8. Troubleshooting Decision Tree

### Symptom: "no healthy upstream"

```
Gateway returns "no healthy upstream"
         │
         ▼
    Check PostgreSQL connections
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 At limit?   Under limit?
    │         │
    ▼         ▼
 Increase    Check backend
 max_conn    containers
    │         │
    │         ▼
    │    Are containers running?
    │         │
    │    ┌────┴────┐
    │    │         │
    │    ▼         ▼
    │   Yes       No
    │    │         │
    │    ▼         ▼
    │   Check    Restart
    │   logs     service
    │    │
    │    ▼
    │   DB connectivity?
    │         │
    │    ┌────┴────┐
    │    │         │
    │    ▼         ▼
    │   Yes       No
    │    │         │
    │    ▼         ▼
    │  Check     Fix network/
    │  config    firewall
    │
    ▼
 Restart gateway containers
```

### Symptom: Hub Tasks Stuck

```
Hub tasks stuck in "waiting"
         │
         ▼
    Check PostgreSQL (NOT Redis)
         │
    ┌────┴────────────────┐
    │                     │
    ▼                     ▼
 Connection            Lock
 exhaustion?          contention?
    │                     │
    ▼                     ▼
 SELECT count(*)      SELECT * FROM
 FROM pg_stat_        pg_locks WHERE
 activity WHERE       granted = false
 datname='hub'
    │                     │
    ▼                     ▼
 If high:             If many waiting:
 Increase             Check long-
 max_connections      running tasks
```

### Symptom: API Returns 401/403

```
API returns authentication error
         │
         ▼
    Check user exists in Gateway
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  Exists    Missing
    │         │
    ▼         ▼
  Check     Create via
  password  gateway API
    │
    ▼
  Token expired?
    │
    ▼
  Regenerate token
```

---

## 9. Quick Reference Scripts

### Script 1: Complete Health Check

```bash
#!/bin/bash
# aap25_health_check.sh

GATEWAY="${GATEWAY_HOST:-192.168.1.177}"
USER="${AAP_USER:-admin}"
PASS="${AAP_PASS:-password}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            AAP 2.5 Health Check Report                     ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ Gateway: $GATEWAY"
echo "║ Time: $(date)"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "┌─── Gateway ───────────────────────────────────────────────┐"
printf "│ Ping:     "
curl -sk -o /dev/null -w "%{http_code}" https://${GATEWAY}/api/gateway/v1/ping/
echo ""
printf "│ Auth:     "
curl -sk -o /dev/null -w "%{http_code}" https://${GATEWAY}/api/gateway/v1/me/ -u ${USER}:${PASS}
echo ""
echo "└──────────────────────────────────────────────────────────────┘"

echo "┌─── Controller ───────────────────────────────────────────────┐"
printf "│ Ping:      "
curl -sk -o /dev/null -w "%{http_code}" https://${GATEWAY}/api/v2/ping/
echo ""
printf "│ Instances: "
curl -sk -o /dev/null -w "%{http_code}" https://${GATEWAY}/api/v2/instances/ -u ${USER}:${PASS}
echo ""
echo "└──────────────────────────────────────────────────────────────┘"

echo "┌─── Hub (Pulp) ───────────────────────────────────────────────┐"
printf "│ Status:    "
curl -sk -o /dev/null -w "%{http_code}" https://${GATEWAY}/api/galaxy/pulp/api/v3/status/
echo ""
echo "└──────────────────────────────────────────────────────────────┘"

echo "┌─── EDA ───────────────────────────────────────────────────────┐"
printf "│ Status:    "
curl -sk -o /dev/null -w "%{http_code}" https://${GATEWAY}/api/eda/v1/status/
echo ""
echo "└──────────────────────────────────────────────────────────────┘"

echo ""
echo "Legend: 200=OK, 401=Auth Required, 502/503=Backend Down, 000=Unreachable"
```

### Script 2: Database Connection Monitor

```bash
#!/bin/bash
# aap25_db_monitor.sh

DB_HOST="${DB_HOST:-192.168.1.228}"
SSH_USER="${SSH_USER:-tfred}"

echo "=== PostgreSQL Connection Monitor ==="
echo "Host: $DB_HOST"
echo "Time: $(date)"
echo ""

ssh ${SSH_USER}@${DB_HOST} << 'EOF'
echo "--- Connection Summary ---"
sudo -u postgres psql -c "
SELECT 
  count(*) as total,
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max,
  round(count(*) * 100.0 / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections'), 1) as pct_used
FROM pg_stat_activity;
"

echo "--- By Database ---"
sudo -u postgres psql -c "
SELECT datname, count(*) as connections 
FROM pg_stat_activity 
WHERE datname IS NOT NULL 
GROUP BY datname 
ORDER BY count DESC;
"

echo "--- By State ---"
sudo -u postgres psql -c "
SELECT state, count(*) 
FROM pg_stat_activity 
GROUP BY state 
ORDER BY count DESC;
"
EOF
```

### Script 3: Hub Task Queue Status

```bash
#!/bin/bash
# aap25_hub_tasks.sh

DB_HOST="${DB_HOST:-192.168.1.228}"
SSH_USER="${SSH_USER:-tfred}"

echo "=== Hub Task Queue Status ==="
echo ""

ssh ${SSH_USER}@${DB_HOST} << 'EOF'
echo "--- Task States ---"
sudo -u postgres psql -d hub -c "
SELECT state, count(*) 
FROM core_task 
GROUP BY state 
ORDER BY count DESC;
"

echo "--- Registered Workers ---"
sudo -u postgres psql -d hub -c "
SELECT name, last_heartbeat, 
       CASE WHEN last_heartbeat > NOW() - INTERVAL '2 minutes' 
            THEN 'HEALTHY' ELSE 'STALE' END as status
FROM core_worker 
ORDER BY last_heartbeat DESC;
"

echo "--- Recent Failed Tasks ---"
sudo -u postgres psql -d hub -c "
SELECT left(name, 40) as task, 
       finished_at,
       error->>'reason' as reason
FROM core_task 
WHERE state = 'failed' 
ORDER BY finished_at DESC 
LIMIT 5;
"
EOF
```

### Script 4: Container Status Across Cluster

```bash
#!/bin/bash
# aap25_container_status.sh

SSH_USER="${SSH_USER:-tfred}"

declare -A NODES=(
  ["Controller"]="192.168.1.236"
  ["Hub-1"]="192.168.1.234"
  ["Hub-2"]="192.168.1.235"
  ["EDA-1"]="192.168.1.231"
  ["EDA-2"]="192.168.1.232"
  ["Gateway-1"]="192.168.1.177"
  ["Gateway-2"]="192.168.1.233"
)

echo "=== AAP 2.5 Cluster Container Status ==="
echo ""

for role in "${!NODES[@]}"; do
  ip="${NODES[$role]}"
  echo "┌─── $role ($ip) ───"
  ssh -o ConnectTimeout=5 ${SSH_USER}@${ip} \
    "podman ps --format '│ {{.Names}}: {{.Status}}'" 2>/dev/null || \
    echo "│ ERROR: Cannot connect"
  echo "└────────────────────────────────────────"
  echo ""
done
```

---

## 10. Key Architectural Insights

### Insight 1: PostgreSQL is the Heart of AAP 2.5

Every component depends on PostgreSQL. If database connections are exhausted, the entire platform fails.

**Connection Formula:**

```
max_connections = (controllers × 50) + (hubs × 80) + (eda × 30) + (gateways × 20) + 50 buffer
```

**For Growth Topology (your environment):**

```
(1 × 50) + (2 × 80) + (2 × 30) + (2 × 20) + 50 = 360 connections
Recommended: 400 minimum
```

### Insight 2: Hub Does NOT Use Celery

Common misconception: Hub uses Celery + Redis for task queuing.

**Reality:**

| Function | Expected | Actual (AAP 2.5) |
|----------|----------|------------------|
| Task queue | Celery | PostgreSQL `core_task` table |
| Broker | Redis | PostgreSQL LISTEN/NOTIFY |
| Locking | Redis locks | PostgreSQL advisory locks |
| Cache | Redis | Redis (only this!) |

**Troubleshooting implication:** If Hub tasks are stuck, check PostgreSQL, not Redis.

### Insight 3: Gateway Proxy Routes by Path

The Envoy proxy in `automation-gateway-proxy` uses URL path to route:

| Path Prefix | Destination |
|-------------|-------------|
| `/api/gateway/` | Gateway Django app |
| `/api/v2/` | Controller |
| `/api/galaxy/` | Hub (Pulp) |
| `/api/eda/` | EDA Controller |

When gateway logs show "REST update for /v3/discovery failed", it means Envoy can't get routing config from the gateway Django app (usually a database issue).

### Insight 4: User Types Are Different

| User Type | Example | Purpose | Where Stored |
|-----------|---------|---------|--------------|
| OS User | tfred | SSH, container runtime | /etc/passwd |
| AAP User | admin | Platform login, API | PostgreSQL (gateway DB) |

The installer creates `admin` user with `gateway_admin_password`. The OS user that runs containers is separate.

### Insight 5: Redis Purpose Varies by Component

| Component | Redis Purpose |
|-----------|---------------|
| Controller | Cache, session storage |
| Hub | Django cache only (NOT task queue) |
| EDA | Cache, possibly pub/sub |
| Gateway | Session storage |

**Key point:** Redis failure degrades performance but doesn't stop task processing in Hub.

---

## Appendix A: Internal Container Ports

| Container | Internal Port | Protocol |
|-----------|---------------|----------|
| automation-controller-web | 8013 | HTTP |
| automation-hub-api | 24817 | HTTP |
| automation-hub-content | 24816 | HTTP |
| eda-api | 8000 | HTTP |
| automation-gateway | 8080 | HTTP |
| redis-tcp | 6379 | TCP |
| redis-unix | /run/redis/redis.sock | Unix socket |
| PostgreSQL | 5432 | TCP |

---

## Appendix B: Common Error Messages

| Error | Component | Likely Cause | First Check |
|-------|-----------|--------------|-------------|
| "no healthy upstream" | Gateway | Backend unreachable | PostgreSQL connections |
| "too many clients already" | PostgreSQL | Connection exhaustion | max_connections setting |
| "Worker has gone missing" | Hub | Worker crashed mid-task | Worker container logs |
| "connection refused" | Any | Container not running | podman ps |
| "SSL negotiation failed" | Gateway | Database SSL issue | pg_hba.conf, SSL certs |

---

## Document Information

| Field | Value |
|-------|-------|
| **Document Version** | 1.0 |
| **Created** | December 2025 |
| **AAP Version** | 2.5 (Containerized) |
| **Topology** | Enterprise Growth |
| **Author** | Generated with Claude |

---

## References

- [AAP 2.5 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/containerized_installation)
- [AAP 2.5 Troubleshooting Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/containerized_installation/troubleshooting-containerized-ansible-automation-platform)
- [PostgreSQL Connection Management](https://www.postgresql.org/docs/15/runtime-config-connection.html)
- [Pulpcore Tasking System](https://docs.pulpproject.org/pulpcore/components.html#tasking-system)
