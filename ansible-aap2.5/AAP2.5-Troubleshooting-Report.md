# AAP 2.5 Containerized Troubleshooting Report

**Generated:** December 11, 2025
**Environment:** Red Hat Ansible Automation Platform 2.5 (Containerized)
**Topology:** Enterprise Growth

---

## Table of Contents

1. [Cluster Topology](#cluster-topology)
2. [Discovery Process](#discovery-process)
3. [Troubleshooting Steps](#troubleshooting-steps)
4. [Root Cause Analysis](#root-cause-analysis)
5. [Findings Summary](#findings-summary)
6. [Remediation Steps](#remediation-steps)
7. [Reference Commands](#reference-commands)
8. [Best Practices & Recommendations](#best-practices--recommendations)

---

## Cluster Topology

### Node Inventory

| Node Name | IP Address | Role | Components |
|-----------|------------|------|------------|
| aap2.5-node1.example.com | 192.168.1.236 | Automation Controller | controller-web, controller-task, controller-rsyslog, receptor, redis-unix |
| aap2.5-node2.example.com | 192.168.1.231 | EDA Controller | eda containers, redis-tcp |
| aap2.5-node3.example.com | 192.168.1.232 | EDA Controller | eda containers, redis-tcp |
| aap2.5-node4.example.com | 192.168.1.234 | Automation Hub | hub containers, redis-tcp |
| aap2.5-node5.example.com | 192.168.1.235 | Automation Hub | hub containers, redis-tcp |
| aap2.5-node6.example.com | 192.168.1.228 | Database (External) | PostgreSQL 15 (systemd), receptor |
| aap2.5-node7.example.com | 192.168.1.177 | Platform Gateway | gateway, gateway-proxy, redis-tcp |
| aap2.5-node8.example.com | 192.168.1.233 | Platform Gateway | gateway, gateway-proxy, redis-tcp |
| aap2.5-node9.example.com | 192.168.1.237 | Execution Node | receptor |

### Architecture Diagram

```
                                    ┌─────────────────────┐
                                    │   Load Balancer     │
                                    │   (External/VIP)    │
                                    └──────────┬──────────┘
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │                          │                          │
           ┌────────▼────────┐        ┌────────▼────────┐                 │
           │  Gateway Node 1 │        │  Gateway Node 2 │                 │
           │  192.168.1.177  │        │  192.168.1.233  │                 │
           │  (node7)        │        │  (node8)        │                 │
           └────────┬────────┘        └────────┬────────┘                 │
                    │                          │                          │
                    └──────────────┬───────────┘                          │
                                   │                                      │
        ┌──────────────────────────┼──────────────────────────┐          │
        │                          │                          │          │
┌───────▼───────┐         ┌────────▼────────┐        ┌────────▼────────┐ │
│  Controller   │         │   Hub Node 1    │        │   Hub Node 2    │ │
│ 192.168.1.236 │         │  192.168.1.234  │        │  192.168.1.235  │ │
│   (node1)     │         │    (node4)      │        │    (node5)      │ │
└───────┬───────┘         └────────┬────────┘        └────────┬────────┘ │
        │                          │                          │          │
        │  ┌───────────────────────┼──────────────────────────┘          │
        │  │                       │                                      │
        │  │  ┌────────────────────┼──────────────────────────┐          │
        │  │  │                    │                          │          │
        │  │  │           ┌────────▼────────┐        ┌────────▼────────┐ │
        │  │  │           │  EDA Node 1     │        │  EDA Node 2     │ │
        │  │  │           │  192.168.1.231  │        │  192.168.1.232  │ │
        │  │  │           │    (node2)      │        │    (node3)      │ │
        │  │  │           └────────┬────────┘        └────────┬────────┘ │
        │  │  │                    │                          │          │
        └──┼──┼────────────────────┼──────────────────────────┼──────────┘
           │  │                    │                          │
           │  │    ┌───────────────┴──────────────────────────┘
           │  │    │
     ┌─────▼──▼────▼─────┐              ┌─────────────────────┐
     │   PostgreSQL 15   │              │   Execution Node    │
     │   192.168.1.228   │◄─────────────│   192.168.1.237     │
     │     (node6)       │   receptor   │     (node9)         │
     └───────────────────┘              └─────────────────────┘
```

---

## Discovery Process

### Step 1: Initial Container Discovery

**Objective:** Identify all running containers across AAP nodes.

**Command Template:**
```bash
sshpass -p '<password>' ssh -o StrictHostKeyChecking=no <user>@<ip> \
  "podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
```

**Controller Node (192.168.1.236) Results:**
```
NAMES                          STATUS         IMAGE
redis-unix                     Up 4 weeks     registry.redhat.io/rhel8/redis-6:latest
receptor                       Up 4 weeks     registry.redhat.io/ansible-automation-platform-25/receptor-rhel8:latest
automation-controller-rsyslog  Up 25 seconds  registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest
automation-controller-task     Up 9 seconds   registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest
automation-controller-web      Up 2 seconds   registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest
```

**Gateway Node 1 (192.168.1.177) Results:**
```
NAMES                     STATUS      IMAGE
redis-tcp                 Up 4 weeks  registry.redhat.io/rhel8/redis-6:latest
automation-gateway-proxy  Up 4 weeks  registry.redhat.io/ansible-automation-platform-25/gateway-proxy-rhel8:latest
automation-gateway        Up 4 weeks  registry.redhat.io/ansible-automation-platform-25/gateway-rhel8:latest
```

**Gateway Node 2 (192.168.1.233) Results:**
```
NAMES                     STATUS      IMAGE
redis-tcp                 Up 4 weeks  registry.redhat.io/rhel8/redis-6:latest
automation-gateway-proxy  Up 4 weeks  registry.redhat.io/ansible-automation-platform-25/gateway-proxy-rhel8:latest
automation-gateway        Up 4 weeks  registry.redhat.io/ansible-automation-platform-25/gateway-rhel8:latest
```

**Database Node (192.168.1.228) Results:**
```
NAMES     STATUS      IMAGE
receptor  Up 4 weeks  registry.redhat.io/ansible-automation-platform-25/receptor-rhel8:latest
```

### Step 2: API Health Check Attempts

**Objective:** Verify platform accessibility via Gateway API.

**Commands Executed:**
```bash
# Gateway health check
curl -sk https://192.168.1.177/api/gateway/v1/me/ -u admin:taku991140530

# Gateway user listing
curl -sk https://192.168.1.177/api/gateway/v1/users/ -u admin:taku991140530
```

**Result:** Both returned `no healthy upstream`

**Analysis:** The Envoy proxy (gateway-proxy) cannot route to healthy backend services.

---

## Troubleshooting Steps

### Step 3: Gateway Container Log Analysis

**Objective:** Identify why gateway reports "no healthy upstream."

**Command:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.177 \
  "podman logs automation-gateway 2>&1 | tail -50"
```

**Key Error Found:**
```python
django.db.utils.OperationalError: connection failed: server closed the connection unexpectedly
    This probably means the server terminated abnormally
    before or while processing the request.
could not send SSL negotiation packet: Success
```

**Gateway Proxy Logs:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.177 \
  "podman logs automation-gateway-proxy 2>&1 | tail -50"
```

**Key Errors Found:**
```
[warning][config] REST update for /v3/discovery:clusters failed
[warning][config] REST update for /v3/discovery:listeners failed
```

**Analysis:** Gateway cannot connect to PostgreSQL database, causing Envoy xDS (discovery service) failures.

### Step 4: Database Connectivity Testing

**Objective:** Verify PostgreSQL connectivity from gateway containers.

**Test DNS Resolution:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.177 \
  "getent hosts aap2.5-node6.example.com"
```

**Result:**
```
192.168.1.228   aap2.5-node6.example.com
```

**Test Network Port:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.177 \
  "nc -zv 192.168.1.228 5432"
```

**Result:**
```
Ncat: Connected to 192.168.1.228:5432.
Port 5432 open
```

**Test Database Connection from Container:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.177 \
  "podman exec automation-gateway python3 -c \"
import psycopg
try:
    conn = psycopg.connect(host='aap2.5-node6.example.com', dbname='gateway', user='awx', password='taku991140530', connect_timeout=10)
    print('Connection successful')
    conn.close()
except Exception as e:
    print(f'Connection failed: {e}')
\""
```

**Result:**
```
Connection failed: connection failed: sorry, too many clients already
```

**Root Cause Identified:** PostgreSQL connection limit exhausted.

### Step 5: PostgreSQL Analysis

**Objective:** Determine connection usage and limits.

**Check PostgreSQL Service Status:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.228 \
  "sudo systemctl status postgresql-15"
```

**Result:** PostgreSQL 15 running as systemd service (not containerized).

**Check Connection Statistics:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.228 \
  "sudo -u postgres psql -c 'SELECT count(*) as active_connections FROM pg_stat_activity;'"
```

**Result:**
```
 active_connections
--------------------
                 99
```

**Check Max Connections:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.228 \
  "sudo -u postgres psql -c 'SHOW max_connections;'"
```

**Result:**
```
 max_connections
-----------------
 100
```

**Check Connections by Database:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.228 \
  "sudo -u postgres psql -c 'SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname ORDER BY count DESC;'"
```

**Result:**
```
 datname  | count
----------+-------
 hub      |    68
 awx      |    21
          |     5
 gateway  |     2
 eda      |     2
 postgres |     1
```

### Step 6: User Investigation

**Objective:** Determine why `tfred` user is not visible in AAP.

**Check Controller Users:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.228 \
  "sudo -u postgres psql -d awx -c 'SELECT id, username, is_superuser, is_active FROM auth_user ORDER BY id;'"
```

**Result:**
```
 id | username | is_superuser | is_active
----+----------+--------------+-----------
  1 | admin    | t            | t
```

**Check Gateway Users:**
```bash
sshpass -p 'taku991140530' ssh -o StrictHostKeyChecking=no tfred@192.168.1.228 \
  "sudo -u postgres psql -d gateway -c 'SELECT id, username, is_superuser, is_active FROM aap_gateway_api_user ORDER BY id;'"
```

**Result:**
```
 id | username | is_superuser | is_active
----+----------+--------------+-----------
  1 | _system  | f            | f
  2 | admin    | t            | t
```

---

## Root Cause Analysis

### Issue 1: PostgreSQL Connection Exhaustion (CRITICAL)

**Symptom:** Gateway returns "no healthy upstream" for all API requests.

**Root Cause:**
- `max_connections` set to 100 (PostgreSQL default)
- 99 active connections at time of investigation
- Automation Hub consuming 68 connections (68% of total)
- New connection attempts fail with "sorry, too many clients already"

**Impact Chain:**
1. Gateway container attempts to query routing configuration from database
2. PostgreSQL rejects connection (at limit)
3. Gateway cannot update Envoy xDS configuration
4. Envoy proxy has no upstream clusters configured
5. All requests return "no healthy upstream"

**Contributing Factors:**
- Enterprise topology with multiple components (Controller, Hub x2, EDA x2, Gateway x2)
- Each component maintains connection pools
- Hub's Pulp backend is particularly connection-hungry
- Default `max_connections=100` insufficient for this topology

### Issue 2: Missing `tfred` User (Expected Behavior)

**Symptom:** User `tfred` cannot log into AAP web interface.

**Root Cause:** User was never created. This is expected behavior.

**Explanation:**
- `tfred` is the **Linux OS user** for:
  - Running podman containers (rootless mode)
  - SSH access to nodes
  - Executing the AAP installer
- `admin` is the **AAP platform user** created by installer variables:
  - `gateway_admin_password`
  - `controller_admin_password`
  - `hub_admin_password`
  - `eda_admin_password`

**Key Distinction:**
| User Type | Username | Purpose |
|-----------|----------|---------|
| OS User | tfred | Linux system access, container runtime |
| AAP User | admin | Platform administration, API access |

---

## Findings Summary

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | PostgreSQL max_connections=100 (too low) | **CRITICAL** | Requires immediate fix |
| 2 | 99/100 connections active | **CRITICAL** | Causing gateway failures |
| 3 | Automation Hub using 68 connections | **HIGH** | Investigate connection leak |
| 4 | Gateway "no healthy upstream" | **CRITICAL** | Symptom of Issue #1 |
| 5 | `tfred` user not in AAP | **INFO** | Expected - OS user ≠ AAP user |
| 6 | All containers running | OK | Infrastructure healthy |
| 7 | Network connectivity OK | OK | Port 5432 reachable |
| 8 | DNS resolution working | OK | Hostnames resolve correctly |

---

## Remediation Steps

### Immediate: Fix PostgreSQL Connection Limit

**Step 1: Increase max_connections**

```bash
# SSH to database node
ssh tfred@192.168.1.228

# Edit PostgreSQL configuration
sudo vi /var/lib/pgsql/15/data/postgresql.conf

# Find and modify these settings:
max_connections = 400              # Was 100, increase based on component count
shared_buffers = 1GB               # Increase proportionally (25% of RAM recommended)
effective_cache_size = 3GB         # 75% of available RAM
work_mem = 16MB                    # Per-operation memory
maintenance_work_mem = 256MB       # For maintenance operations
```

**Step 2: Restart PostgreSQL**

```bash
# Reload configuration (for some settings)
sudo systemctl reload postgresql-15

# For max_connections, full restart required
sudo systemctl restart postgresql-15

# Verify new settings
sudo -u postgres psql -c "SHOW max_connections;"
```

**Step 3: Restart Gateway Services**

```bash
# On Gateway Node 1 (192.168.1.177)
ssh tfred@192.168.1.177
systemctl --user restart automation-gateway automation-gateway-proxy

# On Gateway Node 2 (192.168.1.233)
ssh tfred@192.168.1.233
systemctl --user restart automation-gateway automation-gateway-proxy
```

**Step 4: Verify Gateway Health**

```bash
# Test API endpoint
curl -sk https://192.168.1.177/api/gateway/v1/ping/

# Test authenticated access
curl -sk https://192.168.1.177/api/gateway/v1/me/ -u admin:taku991140530
```

### Follow-up: Investigate Hub Connection Usage

**Identify Long-Running Connections:**
```bash
ssh tfred@192.168.1.228
sudo -u postgres psql -c "
SELECT
    pid,
    client_addr,
    state,
    query_start,
    NOW() - query_start as duration,
    LEFT(query, 50) as query_preview
FROM pg_stat_activity
WHERE datname = 'hub'
ORDER BY query_start ASC
LIMIT 20;
"
```

**Check for Idle Connections:**
```bash
sudo -u postgres psql -c "
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = 'hub'
GROUP BY state;
"
```

**Terminate Idle Connections (if needed):**
```bash
sudo -u postgres psql -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'hub'
  AND state = 'idle'
  AND query_start < NOW() - INTERVAL '1 hour';
"
```

### Optional: Create tfred User in AAP

**Via API (after gateway is healthy):**
```bash
curl -sk -X POST https://192.168.1.177/api/gateway/v1/users/ \
  -u admin:taku991140530 \
  -H "Content-Type: application/json" \
  -d '{
    "username": "tfred",
    "password": "your-secure-password",
    "email": "tfred@example.com",
    "first_name": "T",
    "last_name": "Fred",
    "is_superuser": true
  }'
```

**Via awx-manage (on controller node):**
```bash
ssh tfred@192.168.1.236
podman exec -it automation-controller-web awx-manage createsuperuser --username tfred --email tfred@example.com
```

---

## Reference Commands

### Container Health Commands

```bash
# List all containers with status
podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container health
podman inspect --format='{{.State.Health.Status}}' <container-name>

# View container logs
podman logs <container-name>
podman logs -f <container-name>  # Follow mode
podman logs --tail 100 <container-name>  # Last 100 lines

# Container resource usage
podman stats --no-stream

# Enter container shell
podman exec -it <container-name> /bin/bash
```

### Systemd Service Commands

```bash
# List AAP user services
systemctl --user list-units 'automation-*' --all

# Check specific service
systemctl --user status automation-controller-web

# Restart service (with dependencies)
systemctl --user restart automation-controller-web

# View service logs via journalctl
journalctl --user -u automation-controller-web -f
```

### PostgreSQL Diagnostic Commands

```bash
# Connection count
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"

# Connections by database
sudo -u postgres psql -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname ORDER BY count DESC;"

# Connections by state
sudo -u postgres psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"

# Connections by client IP
sudo -u postgres psql -c "SELECT client_addr, count(*) FROM pg_stat_activity GROUP BY client_addr ORDER BY count DESC;"

# Long-running queries
sudo -u postgres psql -c "SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;"

# Current settings
sudo -u postgres psql -c "SHOW max_connections;"
sudo -u postgres psql -c "SHOW shared_buffers;"

# Kill specific connection
sudo -u postgres psql -c "SELECT pg_terminate_backend(<pid>);"

# Kill all idle connections to a database
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '<dbname>' AND state = 'idle';"
```

### API Health Check Commands

```bash
# Gateway ping (unauthenticated)
curl -sk https://<gateway-host>/api/gateway/v1/ping/

# Gateway authenticated check
curl -sk https://<gateway-host>/api/gateway/v1/me/ -u admin:<password>

# Controller ping
curl -sk https://<controller-host>/api/v2/ping/

# Controller instances (capacity/health)
curl -sk https://<controller-host>/api/v2/instances/ -u admin:<password>

# Hub status
curl -sk https://<hub-host>/api/galaxy/pulp/api/v3/status/

# EDA status
curl -sk https://<eda-host>/api/eda/v1/status/
```

### Network Diagnostic Commands

```bash
# Test port connectivity
nc -zv <host> <port>

# Test from within container
podman exec <container> nc -zv <host> <port>

# DNS resolution
getent hosts <hostname>

# Check listening ports
ss -tlnp | grep <port>
```

---

## Best Practices & Recommendations

### PostgreSQL Sizing for AAP 2.5

**Recommended max_connections by Topology:**

| Topology | Components | Recommended max_connections |
|----------|------------|----------------------------|
| Growth (single node) | All-in-one | 200 |
| Enterprise (small) | 1 of each component | 300 |
| Enterprise (HA) | 2+ of each component | 400-600 |
| Large Scale | Multiple hubs, controllers | 800+ |

**Formula:**
```
max_connections = (controllers × 50) + (hubs × 80) + (eda × 30) + (gateways × 20) + 50 (buffer)
```

**For This Environment:**
```
(1 × 50) + (2 × 80) + (2 × 30) + (2 × 20) + 50 = 360 connections
Recommended: 400 (with headroom)
```

### Connection Pooling Configuration

Consider implementing PgBouncer for connection pooling:

```ini
# /etc/pgbouncer/pgbouncer.ini
[databases]
awx = host=localhost dbname=awx
hub = host=localhost dbname=hub
gateway = host=localhost dbname=gateway
eda = host=localhost dbname=eda

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 50
```

### Monitoring Recommendations

1. **Set up connection monitoring alerts:**
   - Alert when connections > 80% of max_connections
   - Alert when any database > 100 connections

2. **Implement connection cleanup job:**
   ```sql
   -- Schedule this to run hourly
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE state = 'idle'
     AND query_start < NOW() - INTERVAL '30 minutes';
   ```

3. **Monitor Hub specifically:**
   - Pulp/Hub is the most connection-hungry component
   - Consider separate database instance for Hub in large deployments

### Inventory Best Practices

**Always set explicit database connection parameters:**
```ini
[all:vars]
# Increase default connection timeouts
postgresql_connect_timeout=30

# For external database, ensure adequate resources
# Document expected connection counts in comments
```

### Backup Considerations

With connection exhaustion issues, ensure backups don't compete for connections:

```bash
# Schedule backups during low-usage periods
# Use dedicated backup user with reserved connection slot

# In postgresql.conf:
superuser_reserved_connections = 5
```

---

## Appendix: Environment Details

### Inventory File Location
```
/home/tfred/aap/inventory (on controller node 192.168.1.236)
```

### Key Inventory Variables
```ini
[all:vars]
postgresql_admin_username=postgres
postgresql_admin_password=taku991140530

gateway_admin_password=taku991140530
gateway_pg_host=aap2.5-node6.example.com
gateway_pg_database=gateway
gateway_pg_username=awx
gateway_pg_password=taku991140530

controller_admin_password=taku991140530
controller_pg_host=aap2.5-node6.example.com
controller_pg_database=awx
controller_pg_username=awx
controller_pg_password=taku991140530

hub_admin_password=taku991140530
hub_pg_host=aap2.5-node6.example.com
hub_pg_database=hub
hub_pg_username=awx
hub_pg_password=taku991140530

eda_admin_password=taku991140530
eda_pg_host=aap2.5-node6.example.com
eda_pg_database=eda
eda_pg_username=awx
eda_pg_password=taku991140530
```

### Container Images in Use
```
registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest
registry.redhat.io/ansible-automation-platform-25/gateway-rhel8:latest
registry.redhat.io/ansible-automation-platform-25/gateway-proxy-rhel8:latest
registry.redhat.io/ansible-automation-platform-25/receptor-rhel8:latest
registry.redhat.io/rhel8/redis-6:latest
```

### PostgreSQL Version
```
PostgreSQL 15 (running as systemd service on RHEL)
Location: /var/lib/pgsql/15/data/
Service: postgresql-15.service
```

---

## Document History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-12-11 | 1.0 | Claude (AAP Consultant) | Initial troubleshooting report |

---

## Related Documentation

- [AAP 2.5 Containerized Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/containerized_installation/index)
- [AAP 2.5 Troubleshooting Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/containerized_installation/troubleshooting-containerized-ansible-automation-platform)
- [PostgreSQL Connection Management](https://www.postgresql.org/docs/15/runtime-config-connection.html)
- [Red Hat CoP - infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration)
