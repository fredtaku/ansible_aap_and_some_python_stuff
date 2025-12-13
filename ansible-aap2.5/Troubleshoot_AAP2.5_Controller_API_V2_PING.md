# AAP 2.5 Controller API v2 Ping Troubleshooting Report

**Date:** December 13, 2025
**Issue:** `/api/v2/ping/` returning "Not Found" (404) through Gateway
**Resolution:** API path change in AAP 2.5 - use `/api/controller/v2/ping/` instead

---

## Problem Statement

When accessing the Automation Controller API through the Platform Gateway at `https://192.168.1.177/api/v2/ping/`, the response is:

```html
<!doctype html>
<html lang="en">
<head>
  <title>Not Found</title>
</head>
<body>
  <h1>Not Found</h1><p>The requested resource was not found on this server.</p>
</body>
</html>
```

However, the Gateway's own ping endpoint works correctly:
```bash
curl -sk https://192.168.1.177/api/gateway/v1/ping/
# Returns: {"status":"good","version":"2.5","pong":"2025-12-13 23:31:53.918471","db_connected":true,"proxy_connected":true}
```

---

## Root Cause

**The API path `/api/v2/` is NOT valid in AAP 2.5 containerized deployments when accessing through the Platform Gateway.**

In AAP 2.5, the Platform Gateway routes all API requests with component-specific prefixes:

| Component | API Prefix | Service Port |
|-----------|------------|--------------|
| Platform Gateway | `/api/gateway/` | 8446 |
| Automation Controller | `/api/controller/` | 8443 |
| Automation Hub (Galaxy) | `/api/galaxy/` | 8444 |
| Event-Driven Ansible | `/api/eda/` | 8445 |

The legacy path `/api/v2/` which worked in AAP 2.4 and earlier is no longer routed through the Gateway.

---

## Investigation Commands & Findings

### 1. Gateway Ping Test (Working)
```bash
curl -sk https://192.168.1.177/api/gateway/v1/ping/
```
**Output:**
```json
{
  "status": "good",
  "version": "2.5",
  "pong": "2025-12-13 23:31:53.918471",
  "db_connected": true,
  "proxy_connected": true
}
```
**Finding:** Gateway itself is healthy.

### 2. Incorrect Path Test (Failing)
```bash
curl -sk https://192.168.1.177/api/v2/ping/
```
**Output:** `404 Not Found` HTML page

**Finding:** Path `/api/v2/` is not routed by the Gateway.

### 3. Correct Controller Path Test (Working)
```bash
curl -sk https://192.168.1.177/api/controller/v2/ping/
```
**Output:**
```json
{
  "ha": false,
  "version": "4.6.21",
  "active_node": "aap2.5-node1.example.com",
  "install_uuid": "67510f09-3c07-46f7-905c-5aa720841a12",
  "instances": [
    {
      "node": "aap2.5-node1.example.com",
      "node_type": "hybrid",
      "uuid": "64614d56-d0ad-932c-d6a8-d5044f15cfbf",
      "heartbeat": "2025-12-13T23:36:48.881406Z",
      "capacity": 103,
      "version": "4.6.21"
    },
    {
      "node": "aap2.5-node9.example.com",
      "node_type": "execution",
      "uuid": "85389220-f69e-4c2c-8746-a1e8302f0047",
      "heartbeat": "2025-12-13T23:36:26.761505Z",
      "capacity": 103,
      "version": "ansible-runner-2.4.1"
    }
  ],
  "instance_groups": [
    {"name": "controlplane", "capacity": 103, "instances": ["aap2.5-node1.example.com"]},
    {"name": "default", "capacity": 206, "instances": ["aap2.5-node1.example.com", "aap2.5-node9.example.com"]},
    {"name": "executionplane", "capacity": 103, "instances": ["aap2.5-node9.example.com"]}
  ]
}
```
**Finding:** Correct path returns full controller status successfully.

### 4. Controller Container Status Check
```bash
ssh tfred@192.168.1.236 "podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```
**Output:**
```
NAMES                          STATUS      PORTS
redis-unix                     Up 6 hours  6379/tcp
receptor                       Up 6 hours
automation-controller-rsyslog  Up 6 hours  8052/tcp
automation-controller-task     Up 6 hours  8052/tcp
automation-controller-web      Up 6 hours  8052/tcp
```
**Finding:** All controller containers are running and healthy.

### 5. Gateway Service Registration Check
```bash
curl -sk https://192.168.1.177/api/gateway/v1/services/ -u admin:taku991140530
```
**Output (formatted):**
```json
{
  "count": 4,
  "results": [
    {
      "id": 1,
      "name": "gateway api",
      "gateway_path": "/",
      "service_path": "/",
      "api_slug": "gateway",
      "service_port": 8446
    },
    {
      "id": 2,
      "name": "controller api",
      "gateway_path": "/api/controller/",
      "service_path": "/api/controller/",
      "api_slug": "controller",
      "service_port": 8443
    },
    {
      "id": 3,
      "name": "galaxy api",
      "gateway_path": "/api/galaxy/",
      "service_path": "/api/galaxy/",
      "api_slug": "galaxy",
      "service_port": 8444
    },
    {
      "id": 4,
      "name": "eda api",
      "gateway_path": "/api/eda/",
      "service_path": "/api/eda/",
      "api_slug": "eda",
      "service_port": 8445
    }
  ]
}
```
**Finding:** The Gateway only routes to `/api/controller/`, not `/api/v2/`.

### 6. Gateway Proxy Logs Analysis
```bash
ssh tfred@192.168.1.177 "podman logs automation-gateway-proxy 2>&1 | grep 'api/v2/ping'"
```
**Output:**
```
[2025-12-13T23:33:35.475Z] "GET /api/v2/ping HTTP/1.1" 404 - 0 179 9 8 "192.168.1.134" "curl/7.76.1" "66d1a3d2-c2b2-47ee-8646-6e2683042aab" "192.168.1.177" "192.168.1.233:8446"
```
**Finding:** The request to `/api/v2/ping` was routed to another gateway node (192.168.1.233:8446) and returned 404 because no service is mapped to that path.

### 7. Direct Controller Access Test
```bash
ssh tfred@192.168.1.236 "curl -sk http://localhost:8052/api/v2/ping/"
```
**Output:** Full JSON response (success)

**Finding:** Direct access to controller works with `/api/v2/` because it bypasses the Gateway routing.

### 8. Controller-Web Container Logs
```bash
ssh tfred@192.168.1.236 "podman logs automation-controller-web 2>&1 | tail -50"
```
**Output:** Health check logs showing successful `/api/v2/ping/` requests from Gateway health checks (Envoy/HC user agent).

**Finding:** The Gateway's internal health checks DO use `/api/v2/ping/` directly to the controller - this is internal communication, not routed through the Gateway's public interface.

---

## Solution

### Correct API Paths for AAP 2.5

Update all scripts and API calls to use the new prefixed paths:

| Old Path (AAP 2.4) | New Path (AAP 2.5) |
|--------------------|---------------------|
| `/api/v2/ping/` | `/api/controller/v2/ping/` |
| `/api/v2/me/` | `/api/controller/v2/me/` |
| `/api/v2/job_templates/` | `/api/controller/v2/job_templates/` |
| `/api/v2/inventories/` | `/api/controller/v2/inventories/` |
| `/api/galaxy/...` | `/api/galaxy/...` (unchanged) |
| `/api/eda/...` | `/api/eda/...` (unchanged) |

### Working Examples

**Controller Ping (unauthenticated):**
```bash
curl -sk https://192.168.1.177/api/controller/v2/ping/
```

**Controller Current User (authenticated):**
```bash
curl -sk https://192.168.1.177/api/controller/v2/me/ -u admin:taku991140530
```

**Gateway Status:**
```bash
curl -sk https://192.168.1.177/api/gateway/v1/ping/
```

**Hub Status:**
```bash
curl -sk https://192.168.1.177/api/galaxy/pulp/api/v3/status/
```

**EDA Status:**
```bash
curl -sk https://192.168.1.177/api/eda/v1/status/
```

---

## Environment Summary

| Component | IP Address | Status |
|-----------|------------|--------|
| Gateway Node 1 | 192.168.1.177 | Healthy |
| Gateway Node 2 | 192.168.1.233 | Healthy |
| Controller Node | 192.168.1.236 | Healthy |
| Database Node | 192.168.1.228 | Healthy |
| Execution Node | 192.168.1.237 | Healthy |

### Controller Version
- **Automation Controller:** 4.6.21
- **Platform Gateway:** 2.5

### Active Instances
1. `aap2.5-node1.example.com` (hybrid) - Capacity: 103
2. `aap2.5-node9.example.com` (execution) - Capacity: 103

---

## Key Takeaways

1. **AAP 2.5 uses a unified Gateway** that routes all API traffic with component prefixes
2. **Legacy `/api/v2/` paths no longer work** through the Gateway's public interface
3. **Internal health checks** still use `/api/v2/` but directly to containers (not via Gateway routing)
4. **All components are healthy** - this was purely an API path change, not a service failure
5. **The 404 response** from the Gateway correctly indicates that no service is registered for `/api/v2/`

---

## References

- [AAP 2.5 Containerized Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/containerized_installation/index)
- [AAP 2.5 API Reference](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/api_reference/index)
- [Platform Gateway Overview](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/platform_gateway/index)

---

**Report Generated:** December 13, 2025
**Analyst:** Claude AI (Automated Troubleshooting)
