#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# K9s SRE & AI-Infra Troubleshooting Lab (Scenarios s01 - s26)
# =============================================================

log()  { echo -e "\033[1;32m[+] $1\033[0m"; }
warn() { echo -e "\033[1;33m[!] $1\033[0m"; }
info() { echo -e "\033[1;36m[*] $1\033[0m"; }
err()  { echo -e "\033[1;31m[-] $1\033[0m"; }

usage() {
  cat <<USAGE
Usage: $0 [OPTION] [SCENARIO_NUMBER]

Options:
  --deploy, -d           Deploy all 26 labeled scenarios (Default if no args passed)
  --list, -l             List all 26 scenarios with their labels, categories, and namespaces
  --solve, -s <1-26>     Print step-by-step diagnosis & remediation guide for Scenario #
  --auto-fix, -f <1-26>  Automatically apply the fix for Scenario # in the cluster
  --reset, -r            Delete lab namespaces and clean up node labels/taints
  --help, -h             Show this help menu

Examples:
  $0 --deploy
  $0 --list
  $0 --solve 22
  $0 --auto-fix 22
USAGE
}

# -------------------------------------------------------------
# Scenario Metadata & Step-by-Step Solver Engine
# -------------------------------------------------------------
list_scenarios() {
  echo -e "\033[1;36m========================================================================================\033[0m"
  printf "\033[1;33m%-6s | %-18s | %-15s | %-40s\033[0m\n" "LABEL" "CATEGORY" "NAMESPACE" "SCENARIO NAME"
  echo -e "\033[1;36m========================================================================================\033[0m"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s01" "resources" "k9s-lab" "Heavy CPU Load (CFS Quota Throttling)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s02" "resources" "k9s-lab" "OOMKilled Trigger (Exit Code 137)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s03" "crashloop" "k9s-lab" "Application CrashLoop (Storage Journal Err)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s04" "config" "k9s-lab" "CreateContainerConfigError (Missing Secret)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s05" "baseline" "k9s-lab" "Healthy Baseline Frontend (2 Replicas)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s06" "imagepull" "k9s-lab" "ImagePullBackOff #1: Nonexistent Tag (404)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s07" "imagepull" "k9s-lab" "ImagePullBackOff #2: Unresolvable Registry"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s08" "imagepull" "k9s-lab" "ImagePullBackOff #3: Registry 401 Unauth"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s09" "imagepull" "k9s-lab" "ImagePullBackOff #4: Arch Mismatch (s390x)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s10" "crashloop" "k9s-lab" "CrashLoopBackOff (Exit 1): Missing Env Var"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s11" "crashloop" "k9s-lab" "CrashLoopBackOff (Exit 126): chmod -x Script"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s12" "probes" "k9s-lab" "Liveness Probe Failing (HTTP 404)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s13" "probes" "k9s-lab" "Liveness Probe Timeout (Init Delay Too Short)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s14" "scheduling" "k9s-lab" "Pending: Insufficient CPU (Requests 128 Cores)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s15" "scheduling" "k9s-lab" "Pending: NodeSelector Mismatch (NVMe Label)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s16" "scheduling" "k9s-lab" "Pending: Untolerated Node Taint (dedicated=gpu)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s17" "governance" "k9s-lab-quota" "Missing Pods: Blocked by Namespace Quota"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s18" "rbac-sa" "k9s-lab" "Missing Pods: ServiceAccount Not Found"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s19" "storage" "k9s-lab" "Pending Pod: PVC Unbound (Missing StorageClass)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s20" "init-deps" "k9s-lab" "Init:Error / CrashLoop (Unresolvable DB Host)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s21" "scheduling" "k9s-lab" "Pending/Pressure: High Memory Request (1.5Gi)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s22" "net-dns" "k9s-lab" "DNS ndots:5 Amplification & Dead Nameserver"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s23" "net-service" "k9s-lab" "Service Blackhole: Empty EndpointSlice"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s24" "net-service" "k9s-lab" "Service TCP RST: TargetPort 8080 vs Port 80"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s25" "net-policy" "k9s-lab-netpol" "Zero-Trust Egress Lockout (CoreDNS Blocked)"
  printf "%-6s | %-18s | %-15s | %-40s\n" "s26" "ai-networking" "k9s-lab" "NCCL Worker Crash: Missing Secondary RDMA NIC"
  echo -e "\033[1;36m========================================================================================\033[0m"
  echo -e "Tip: In k9s, press \033[1;32m/\033[0m and type \033[1;33m-l scenario=s22\033[0m or \033[1;33m-l category=net-service\033[0m to filter!"
}

solve_scenario() {
  local num="${1#s}"
  num=$((10#$num))
  local s_label
  s_label=$(printf "s%02d" "$num")

  echo -e "\n\033[1;36m========================================================================\033[0m"
  echo -e "\033[1;33m STEP-BY-STEP RUNBOOK: SCENARIO #${num} (Label: scenario=${s_label})\033[0m"
  echo -e "\033[1;36m========================================================================\033[0m"

  case "$num" in
    1)
      cat <<'GUIDE'
[ Workload ]   Deployment/load-cpu-hog (Namespace: k9s-lab)
[ Symptom ]    Pod consumes high CPU and hits CFS throttling limits.
[ Step 1: Isolate in k9s ]
  Open k9s (`k9s -n k9s-lab`), press `/` and filter with `-l scenario=s01`.
[ Step 2: Diagnose ]
  kubectl top pod -l scenario=s01 -n k9s-lab
  kubectl describe pod -l scenario=s01 -n k9s-lab
[ Step 3: Root Cause ]
  Container runs `vish/stress -cpus 2` while throttled at `limits.cpu: 600m`.
[ Step 4: Remediate (k9s or CLI) ]
  - In k9s: Select deployment `load-cpu-hog`, press `e` (Edit), change args `["-cpus", "2"]` to `["-cpus", "1"]` and reduce CPU usage or scale down replicas.
  - CLI Fix:
    kubectl patch deployment load-cpu-hog -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:alpine"},{"op":"remove","path":"/spec/template/spec/containers/0/args"}]'
[ Step 5: Verify ]
  kubectl rollout status deployment/load-cpu-hog -n k9s-lab
GUIDE
      ;;
    2)
      cat <<'GUIDE'
[ Workload ]   Deployment/memory-leak-app (Namespace: k9s-lab)
[ Symptom ]    Pod repeatedly crashes with `OOMKilled` (Exit Code 137).
[ Step 1: Isolate in k9s ]
  Filter in k9s: `-l scenario=s02` -> Press `d` (Describe) on the pod.
[ Step 2: Diagnose ]
  kubectl get pod -l scenario=s02 -n k9s-lab
  kubectl describe pod -l scenario=s02 -n k9s-lab | grep -A 5 "Last State:"
[ Step 3: Root Cause ]
  Process allocates `-mem-total 256Mi`, exceeding cgroup `limits.memory: 64Mi`. Kernel OOM killer sends SIGKILL (128 + 9 = 137).
[ Step 4: Remediate ]
  Either lower the allocation argument to `32Mi` or raise `limits.memory` to `300Mi` (avoid raising on 2GB nodes; lower the app allocation instead):
  kubectl patch deployment memory-leak-app -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["-mem-total","32Mi","-mem-alloc-size","8Mi","-mem-alloc-time","1s"]}]'
[ Step 5: Verify ]
  kubectl get pod -l scenario=s02 -n k9s-lab -w
GUIDE
      ;;
    3)
      cat <<'GUIDE'
[ Workload ]   Deployment/crashing-service (Namespace: k9s-lab)
[ Symptom ]    Pod enters `CrashLoopBackOff` after 4 seconds.
[ Step 1: Isolate in k9s ]
  Filter `-l scenario=s03`, select pod, press `l` (Logs) and `p` (Previous logs).
[ Step 2: Diagnose ]
  kubectl logs -l scenario=s03 -n k9s-lab --previous
[ Step 3: Root Cause ]
  Startup shell command simulates a corrupted storage journal and executes `exit 1`.
[ Step 4: Remediate ]
  Patch the container command to run cleanly without `exit 1`:
  kubectl patch deployment crashing-service -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["echo \"Storage journal recovered.\"; sleep 3600"]}]'
[ Step 5: Verify ]
  kubectl get pod -l scenario=s03 -n k9s-lab
GUIDE
      ;;
    4)
      cat <<'GUIDE'
[ Workload ]   Deployment/missing-secret-worker (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `CreateContainerConfigError`.
[ Step 1: Isolate in k9s ]
  Filter `-l scenario=s04`, press `d` on the pod and inspect bottom `Events`.
[ Step 2: Diagnose ]
  kubectl describe pod -l scenario=s04 -n k9s-lab | tail -n 10
[ Step 3: Root Cause ]
  Container env `API_AUTH_KEY` references Secret `non-existent-prod-secret` (key: `token`), which does not exist in `k9s-lab`.
[ Step 4: Remediate ]
  Create the missing Secret in `k9s-lab`:
  kubectl create secret generic non-existent-prod-secret --from-literal=token=prod-sre-secret-123 -n k9s-lab
  kubectl rollout restart deployment/missing-secret-worker -n k9s-lab
[ Step 5: Verify ]
  kubectl get pod -l scenario=s04 -n k9s-lab
GUIDE
      ;;
    5)
      cat <<'GUIDE'
[ Workload ]   Deployment/healthy-frontend (Namespace: k9s-lab)
[ Symptom ]    None (Healthy reference workload with 2 replicas).
[ Step 1: Verify ]
  kubectl get pods -l scenario=s05 -n k9s-lab
GUIDE
      ;;
    6)
      cat <<'GUIDE'
[ Workload ]   Pod/err-image-nonexistent-tag (Namespace: k9s-lab)
[ Symptom ]    `ErrImagePull` / `ImagePullBackOff`.
[ Step 1: Diagnose ]
  kubectl describe pod err-image-nonexistent-tag -n k9s-lab | grep -E "Failed|Back-off"
[ Step 2: Root Cause ]
  Image tag `alpine:99.99.99-nonexistent` does not exist on Docker Hub (manifest not found).
[ Step 3: Remediate ]
  Update the pod image to a valid tag (`alpine:3.19` or `alpine:latest`):
  kubectl set image pod/err-image-nonexistent-tag alpine=alpine:latest -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod err-image-nonexistent-tag -n k9s-lab
GUIDE
      ;;
    7)
      cat <<'GUIDE'
[ Workload ]   Pod/err-image-invalid-registry (Namespace: k9s-lab)
[ Symptom ]    `ErrImagePull` / `ImagePullBackOff` (DNS lookup failure on registry).
[ Step 1: Diagnose ]
  kubectl describe pod err-image-invalid-registry -n k9s-lab | grep -i "lookup"
[ Step 2: Root Cause ]
  Registry hostname `invalid-registry.internal-lab.local` cannot be resolved by node DNS.
[ Step 3: Remediate ]
  Point the pod image to a valid upstream registry (`docker.io/library/alpine:latest`):
  kubectl set image pod/err-image-invalid-registry alpine=alpine:latest -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod err-image-invalid-registry -n k9s-lab
GUIDE
      ;;
    8)
      cat <<'GUIDE'
[ Workload ]   Pod/err-image-unauthorized-private (Namespace: k9s-lab)
[ Symptom ]    `ErrImagePull` / `ImagePullBackOff` (401 Unauthorized / 403 Forbidden).
[ Step 1: Diagnose ]
  kubectl describe pod err-image-unauthorized-private -n k9s-lab | tail -n 12
[ Step 2: Root Cause ]
  Pod pulls from restricted registry path `ghcr.io/internal-enterprise-private-org/secure-alpine:latest` without valid `imagePullSecrets`.
[ Step 3: Remediate ]
  Switch image to an accessible public image (or attach `imagePullSecrets` in production):
  kubectl set image pod/err-image-unauthorized-private private-app=alpine:latest -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod err-image-unauthorized-private -n k9s-lab
GUIDE
      ;;
    9)
      cat <<'GUIDE'
[ Workload ]   Pod/err-image-arch-mismatch (Namespace: k9s-lab)
[ Symptom ]    `ImagePullBackOff` or `exec format error` (`s390x` binary on `x86_64`/`arm64` host).
[ Step 1: Diagnose ]
  kubectl describe pod err-image-arch-mismatch -n k9s-lab | tail -n 12
[ Step 2: Root Cause ]
  Image `s390x/busybox:latest` is compiled for IBM Z mainframe architecture, incompatible with your Ubuntu node CPU architecture.
[ Step 3: Remediate ]
  Switch to multi-arch `busybox:latest`:
  kubectl set image pod/err-image-arch-mismatch busybox-s390x=busybox:latest -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod err-image-arch-mismatch -n k9s-lab
GUIDE
      ;;
    10)
      cat <<'GUIDE'
[ Workload ]   Deployment/env-var-crash-app (Namespace: k9s-lab)
[ Symptom ]    `CrashLoopBackOff` with Exit Code 1.
[ Step 1: Diagnose ]
  kubectl logs -l scenario=s10 -n k9s-lab
[ Step 2: Root Cause ]
  Logs show: `FATAL: REQUIRED_DB_HOST is missing. Application cannot start.`
[ Step 3: Remediate ]
  Inject the missing environment variable `REQUIRED_DB_HOST`:
  kubectl set env deployment/env-var-crash-app REQUIRED_DB_HOST=postgres.k9s-lab.svc.cluster.local -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod -l scenario=s10 -n k9s-lab
GUIDE
      ;;
    11)
      cat <<'GUIDE'
[ Workload ]   Deployment/permission-denied-app (Namespace: k9s-lab)
[ Symptom ]    `CrashLoopBackOff` with Exit Code 126 (Command invoked cannot execute).
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s11 -n k9s-lab | grep -A 5 "Last State:"
  kubectl logs -l scenario=s11 -n k9s-lab
[ Step 2: Root Cause ]
  Script `/tmp/script.sh` has execute bits stripped (`chmod -x`), causing POSIX shell exit code 126.
[ Step 3: Remediate ]
  Patch the args to use `chmod +x /tmp/script.sh` and `sleep 3600`:
  kubectl patch deployment permission-denied-app -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["echo \"echo Running...\" > /tmp/script.sh && chmod +x /tmp/script.sh && /tmp/script.sh && sleep 3600"]}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s11 -n k9s-lab
GUIDE
      ;;
    12)
      cat <<'GUIDE'
[ Workload ]   Deployment/liveness-probe-404 (Namespace: k9s-lab)
[ Symptom ]    Container runs briefly, then restarts continuously with Exit Code 137 (`Killing container`).
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s12 -n k9s-lab | grep -i "Unhealthy"
[ Step 2: Root Cause ]
  `livenessProbe.httpGet.path` points to `/non-existent-health-check`, returning HTTP 404. Kubelet kills the container.
[ Step 3: Remediate ]
  Update `livenessProbe.httpGet.path` to `/`:
  kubectl patch deployment liveness-probe-404 -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/"}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s12 -n k9s-lab
GUIDE
      ;;
    13)
      cat <<'GUIDE'
[ Workload ]   Deployment/liveness-probe-timeout (Namespace: k9s-lab)
[ Symptom ]    Container killed before initialization completes (Exit Code 137).
[ Step 1: Diagnose ]
  kubectl logs -l scenario=s13 -n k9s-lab
  kubectl describe pod -l scenario=s13 -n k9s-lab | grep -i "Liveness probe failed"
[ Step 2: Root Cause ]
  Application takes 15 seconds to create `/tmp/healthy`, but `initialDelaySeconds: 1`, `periodSeconds: 2`, `failureThreshold: 2` kills the pod after ~5 seconds.
[ Step 3: Remediate ]
  Increase `initialDelaySeconds` to `20` (or add a `startupProbe`):
  kubectl patch deployment liveness-probe-timeout -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":20}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s13 -n k9s-lab
GUIDE
      ;;
    14)
      cat <<'GUIDE'
[ Workload ]   Deployment/pending-insufficient-cpu (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `Pending` state indefinitely.
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s14 -n k9s-lab | grep -A 5 "Events:"
[ Step 2: Root Cause ]
  Event shows `0/2 nodes are available: 2 Insufficient cpu`. Pod requests `128` CPU cores.
[ Step 3: Remediate ]
  Lower `requests.cpu` to `25m`:
  kubectl patch deployment pending-insufficient-cpu -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"25m"}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s14 -n k9s-lab
GUIDE
      ;;
    15)
      cat <<'GUIDE'
[ Workload ]   Deployment/pending-nodeselector-mismatch (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `Pending` (`0/2 nodes are available: 2 node(s) didn't match Pod's node selector`).
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s15 -n k9s-lab | tail -n 10
  kubectl get nodes --show-labels
[ Step 2: Root Cause ]
  Pod requires `nodeSelector: disktype=super-fast-nvme`, which no node possesses.
[ Step 3: Remediate ]
  Label one of your nodes with `disktype=super-fast-nvme`:
  NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
  kubectl label node "$NODE" disktype=super-fast-nvme --overwrite
[ Step 4: Verify ]
  kubectl get pod -l scenario=s15 -n k9s-lab
GUIDE
      ;;
    16)
      cat <<'GUIDE'
[ Workload ]   Deployment/pending-taint-dedicated-gpu (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `Pending` (`untolerated taint {dedicated: gpu}`).
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s16 -n k9s-lab | tail -n 10
[ Step 2: Root Cause ]
  Target node has taint `dedicated=gpu:NoSchedule`, and while the pod has `nodeSelector: dedicated=gpu`, it lacks the matching `tolerations` block.
[ Step 3: Remediate ]
  Patch the deployment to add the matching toleration:
  kubectl patch deployment pending-taint-dedicated-gpu -n k9s-lab --type='json' -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"dedicated","operator":"Equal","value":"gpu","effect":"NoSchedule"}]}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s16 -n k9s-lab
GUIDE
      ;;
    17)
      cat <<'GUIDE'
[ Workload ]   Deployment/quota-blocked-app (Namespace: k9s-lab-quota)
[ Symptom ]    Deployment shows `0/2` replicas, and `0` pods exist in `k9s-lab-quota`.
[ Step 1: Diagnose ]
  kubectl get rs -l scenario=s17 -n k9s-lab-quota
  kubectl describe rs -l scenario=s17 -n k9s-lab-quota
[ Step 2: Root Cause ]
  ReplicaSet event reports `FailedCreate: exceeded quota: strict-quota`. Quota allows `50m` CPU / `64Mi` RAM total, while each pod requests `200m` CPU / `128Mi` RAM.
[ Step 3: Remediate ]
  Raise the `ResourceQuota` in `k9s-lab-quota` and restart the deployment:
  kubectl patch resourcequota strict-quota -n k9s-lab-quota --type='merge' -p '{"spec":{"hard":{"requests.cpu":"500m","requests.memory":"512Mi"}}}'
  kubectl rollout restart deployment/quota-blocked-app -n k9s-lab-quota
[ Step 4: Verify ]
  kubectl get pods -l scenario=s17 -n k9s-lab-quota
GUIDE
      ;;
    18)
      cat <<'GUIDE'
[ Workload ]   Deployment/missing-sa-app (Namespace: k9s-lab)
[ Symptom ]    Deployment shows `0/1` ready, zero pods created.
[ Step 1: Diagnose ]
  kubectl describe rs -l scenario=s18 -n k9s-lab | tail -n 10
[ Step 2: Root Cause ]
  ReplicaSet fails admission with `error looking up service account k9s-lab/custom-app-sa: serviceaccount "custom-app-sa" not found`.
[ Step 3: Remediate ]
  Create the missing ServiceAccount and trigger ReplicaSet reconciliation:
  kubectl create serviceaccount custom-app-sa -n k9s-lab
  kubectl rollout restart deployment/missing-sa-app -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod -l scenario=s18 -n k9s-lab
GUIDE
      ;;
    19)
      cat <<'GUIDE'
[ Workload ]   Deployment/app-blocked-by-pvc & PVC/pending-pvc-missing-sc (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `Pending` (`pod has unbound immediate PersistentVolumeClaims`).
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s19 -n k9s-lab
  kubectl describe pvc pending-pvc-missing-sc -n k9s-lab
[ Step 2: Root Cause ]
  PVC requests `storageClassName: non-existent-fast-ssd`, which does not exist.
[ Step 3: Remediate ]
  Since `storageClassName` on an existing PVC is immutable, either create a matching StorageClass/PV or switch the Deployment volume to `emptyDir` (or default SC if available):
  kubectl patch deployment app-blocked-by-pvc -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"pgdata","emptyDir":{}}},{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"POSTGRES_PASSWORD","value":"labpass"}]}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s19 -n k9s-lab
GUIDE
      ;;
    20)
      cat <<'GUIDE'
[ Workload ]   Deployment/init-container-failure (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `Init:0/1` (`Init:Error` / `Init:CrashLoopBackOff`).
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s20 -n k9s-lab
  kubectl logs -l scenario=s20 -n k9s-lab -c check-db-connectivity
[ Step 2: Root Cause ]
  InitContainer runs `nc -z non-existent-database-service 5432`, which fails DNS resolution.
[ Step 3: Remediate ]
  Create a dummy ExternalName/ClusterIP service or point the InitContainer check to `healthy-frontend` port `80`:
  kubectl patch deployment init-container-failure -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/initContainers/0/command","value":["sh","-c","echo \"DB check passed\"; exit 0"]}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s20 -n k9s-lab
GUIDE
      ;;
    21)
      cat <<'GUIDE'
[ Workload ]   Deployment/memory-pressure-sim (Namespace: k9s-lab)
[ Symptom ]    Pod stuck in `Pending` (`Insufficient memory`) on 2GB nodes.
[ Step 1: Diagnose ]
  kubectl describe pod -l scenario=s21 -n k9s-lab | tail -n 10
[ Step 2: Root Cause ]
  Pod requests `1500Mi` RAM (`limits: 1600Mi`), which exceeds allocatable free memory on a 2GB Ubuntu node.
[ Step 3: Remediate ]
  Right-size memory requests/limits to `64Mi`/`128Mi` and allocation to `32Mi`:
  kubectl patch deployment memory-pressure-sim -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"64Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"128Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["-mem-total","32Mi","-mem-alloc-size","8Mi","-mem-alloc-time","1s"]}]'
[ Step 4: Verify ]
  kubectl get pod -l scenario=s21 -n k9s-lab
GUIDE
      ;;
    22)
      cat <<'GUIDE'
[ Workload ]   Deployment/dns-ndots-trap (Namespace: k9s-lab)
[ Symptom ]    Pod logs show `ERROR: DNS lookup timed out!` every 5 seconds.
[ Step 1: Diagnose ]
  kubectl logs -l scenario=s22 -n k9s-lab --tail=10
  kubectl exec -it deploy/dns-ndots-trap -n k9s-lab -- cat /etc/resolv.conf
[ Step 2: Root Cause ]
  `dnsPolicy: None` overrides CoreDNS with a dead RFC5737 TEST-NET IP (`192.0.2.53`) and `ndots: 5`, causing every query to traverse search domains and hit UDP timeout.
[ Step 3: Remediate ]
  Restore `dnsPolicy: ClusterFirst`, remove the custom `nameservers` override, and tune `ndots` to `2`:
  kubectl patch deployment dns-ndots-trap -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirst"},{"op":"replace","path":"/spec/template/spec/dnsConfig","value":{"options":[{"name":"ndots","value":"2"},{"name":"timeout","value":"2"}]}}]'
[ Step 4: Verify ]
  kubectl logs -l scenario=s22 -n k9s-lab --tail=10
GUIDE
      ;;
    23)
      cat <<'GUIDE'
[ Workload ]   Service/payment-gateway-svc & Deployment/payment-gateway (Namespace: k9s-lab)
[ Symptom ]    `payment-client-prober` logs `FAILED: Connection refused/timeout`.
[ Step 1: Diagnose ]
  kubectl logs pod/payment-client-prober -n k9s-lab --tail=5
  kubectl get endpoints payment-gateway-svc -n k9s-lab
  kubectl describe svc payment-gateway-svc -n k9s-lab
  kubectl get pods -l scenario=s23 -n k9s-lab --show-labels
[ Step 2: Root Cause ]
  `Endpoints` is `<none>`. Service selector looks for `app: payment-v2`, whereas the Deployment pods carry `app: payment-v1`.
[ Step 3: Remediate ]
  Update Service selector to `app: payment-v1`:
  kubectl patch svc payment-gateway-svc -n k9s-lab --type='merge' -p '{"spec":{"selector":{"app":"payment-v1"}}}'
[ Step 4: Verify ]
  kubectl get endpoints payment-gateway-svc -n k9s-lab
  kubectl logs pod/payment-client-prober -n k9s-lab --tail=5
GUIDE
      ;;
    24)
      cat <<'GUIDE'
[ Workload ]   Service/inventory-svc & Deployment/inventory-backend (Namespace: k9s-lab)
[ Symptom ]    Endpoints are populated, but curling `inventory-svc:80` returns `Connection refused` (TCP RST).
[ Step 1: Diagnose ]
  kubectl get endpoints inventory-svc -n k9s-lab
  kubectl get svc inventory-svc -n k9s-lab -o yaml | grep -A 5 "ports:"
  kubectl get deploy inventory-backend -n k9s-lab -o jsonpath='{.spec.template.spec.containers[0].ports}'
[ Step 2: Root Cause ]
  Service forwards `port: 80` to `targetPort: 8080`, but the `nginx:alpine` container listens on port `80`.
[ Step 3: Remediate ]
  Patch `inventory-svc` `targetPort` to `80`:
  kubectl patch svc inventory-svc -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
[ Step 4: Verify ]
  kubectl exec pod/payment-client-prober -n k9s-lab -- wget -qO- --timeout=2 http://inventory-svc.k9s-lab.svc.cluster.local:80 | head -n 5
GUIDE
      ;;
    25)
      cat <<'GUIDE'
[ Workload ]   NetworkPolicy/strict-zero-trust-egress & Deployment/isolated-microservice (Namespace: k9s-lab-netpol)
[ Symptom ]    `isolated-microservice` logs `BLOCKED: Egress NetworkPolicy is dropping UDP/TCP 53 to CoreDNS!`.
[ Step 1: Diagnose ]
  kubectl logs -l scenario=s25 -n k9s-lab-netpol --tail=5
  kubectl describe networkpolicy strict-zero-trust-egress -n k9s-lab-netpol
[ Step 2: Root Cause ]
  `strict-zero-trust-egress` has `egress: []` (Default-Deny all egress), which drops UDP/TCP port 53 traffic to `kube-system` CoreDNS as well as internal API calls.
[ Step 3: Remediate ]
  Patch the `NetworkPolicy` to allow egress on UDP/TCP port 53 (DNS) and TCP port 443/80:
  kubectl patch networkpolicy strict-zero-trust-egress -n k9s-lab-netpol --type='merge' -p '{"spec":{"egress":[{"ports":[{"protocol":"UDP","port":53},{"protocol":"TCP","port":53},{"protocol":"TCP","port":443},{"protocol":"TCP","port":80}]}]}}'
[ Step 4: Verify ]
  kubectl logs -l scenario=s25 -n k9s-lab-netpol --tail=5
GUIDE
      ;;
    26)
      cat <<'GUIDE'
[ Workload ]   Deployment/nccl-rdma-worker (Namespace: k9s-lab)
[ Symptom ]    Pod crashes in `CrashLoopBackOff` with `FATAL: Secondary RDMA interface 'net1' not found!`.
[ Step 1: Diagnose ]
  kubectl logs -l scenario=s26 -n k9s-lab
  kubectl describe pod -l scenario=s26 -n k9s-lab | grep -A 3 "Annotations:"
[ Step 2: Root Cause ]
  Pod requests secondary Multus interface `k8s.v1.cni.cncf.io/networks: sriov-rdma-net` and checks for `REQUIRED_IFACE=net1`. Because Multus/SR-IOV hardware is absent on this 2-node VM lab, only `eth0` is provisioned.
[ Step 3: Remediate ]
  Fallback `REQUIRED_IFACE` to `eth0` so the NCCL worker binds to the primary CNI interface:
  kubectl set env deployment/nccl-rdma-worker REQUIRED_IFACE=eth0 -n k9s-lab
[ Step 4: Verify ]
  kubectl get pod -l scenario=s26 -n k9s-lab
  kubectl logs -l scenario=s26 -n k9s-lab
GUIDE
      ;;
    *)
      err "Invalid scenario number: $1. Choose between 1 and 26."
      exit 1
      ;;
  esac
}

auto_fix_scenario() {
  local num="${1#s}"
  num=$((10#$num))
  log "Auto-remediating Scenario #${num}..."

  case "$num" in
    1)
      kubectl patch deployment load-cpu-hog -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:alpine"},{"op":"remove","path":"/spec/template/spec/containers/0/args"}]'
      ;;
    2)
      kubectl patch deployment memory-leak-app -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["-mem-total","32Mi","-mem-alloc-size","8Mi","-mem-alloc-time","1s"]}]'
      ;;
    3)
      kubectl patch deployment crashing-service -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["echo \"Storage journal recovered.\"; sleep 3600"]}]'
      ;;
    4)
      kubectl create secret generic non-existent-prod-secret --from-literal=token=prod-sre-secret-123 -n k9s-lab --dry-run=client -o yaml | kubectl apply -f -
      kubectl rollout restart deployment/missing-secret-worker -n k9s-lab
      ;;
    5)
      log "Scenario 5 is already healthy baseline."
      ;;
    6)
      kubectl set image pod/err-image-nonexistent-tag alpine=alpine:latest -n k9s-lab
      ;;
    7)
      kubectl set image pod/err-image-invalid-registry alpine=alpine:latest -n k9s-lab
      ;;
    8)
      kubectl set image pod/err-image-unauthorized-private private-app=alpine:latest -n k9s-lab
      ;;
    9)
      kubectl set image pod/err-image-arch-mismatch busybox-s390x=busybox:latest -n k9s-lab
      ;;
    10)
      kubectl set env deployment/env-var-crash-app REQUIRED_DB_HOST=postgres.k9s-lab.svc.cluster.local -n k9s-lab
      ;;
    11)
      kubectl patch deployment permission-denied-app -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["echo \"echo Running...\" > /tmp/script.sh && chmod +x /tmp/script.sh && /tmp/script.sh && sleep 3600"]}]'
      ;;
    12)
      kubectl patch deployment liveness-probe-404 -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/"}]'
      ;;
    13)
      kubectl patch deployment liveness-probe-timeout -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":20}]'
      ;;
    14)
      kubectl patch deployment pending-insufficient-cpu -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"25m"}]'
      ;;
    15)
      NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
      kubectl label node "$NODE" disktype=super-fast-nvme --overwrite
      ;;
    16)
      kubectl patch deployment pending-taint-dedicated-gpu -n k9s-lab --type='json' -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"dedicated","operator":"Equal","value":"gpu","effect":"NoSchedule"}]}]'
      ;;
    17)
      kubectl patch resourcequota strict-quota -n k9s-lab-quota --type='merge' -p '{"spec":{"hard":{"requests.cpu":"500m","requests.memory":"512Mi"}}}'
      kubectl rollout restart deployment/quota-blocked-app -n k9s-lab-quota
      ;;
    18)
      kubectl create serviceaccount custom-app-sa -n k9s-lab --dry-run=client -o yaml | kubectl apply -f -
      kubectl rollout restart deployment/missing-sa-app -n k9s-lab
      ;;
    19)
      kubectl patch deployment app-blocked-by-pvc -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"pgdata","emptyDir":{}}},{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"POSTGRES_PASSWORD","value":"labpass"}]}]'
      ;;
    20)
      kubectl patch deployment init-container-failure -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/initContainers/0/command","value":["sh","-c","echo \"DB check passed\"; exit 0"]}]'
      ;;
    21)
      kubectl patch deployment memory-pressure-sim -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"64Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"128Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["-mem-total","32Mi","-mem-alloc-size","8Mi","-mem-alloc-time","1s"]}]'
      ;;
    22)
      kubectl patch deployment dns-ndots-trap -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirst"},{"op":"replace","path":"/spec/template/spec/dnsConfig","value":{"options":[{"name":"ndots","value":"2"},{"name":"timeout","value":"2"}]}}]'
      ;;
    23)
      kubectl patch svc payment-gateway-svc -n k9s-lab --type='merge' -p '{"spec":{"selector":{"app":"payment-v1"}}}'
      ;;
    24)
      kubectl patch svc inventory-svc -n k9s-lab --type='json' -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
      ;;
    25)
      kubectl patch networkpolicy strict-zero-trust-egress -n k9s-lab-netpol --type='merge' -p '{"spec":{"egress":[{"ports":[{"protocol":"UDP","port":53},{"protocol":"TCP","port":53},{"protocol":"TCP","port":443},{"protocol":"TCP","port":80}]}]}}'
      ;;
    26)
      kubectl set env deployment/nccl-rdma-worker REQUIRED_IFACE=eth0 -n k9s-lab
      ;;
    *)
      err "Invalid scenario number: $1. Choose between 1 and 26."
      exit 1
      ;;
  esac
  log "Scenario #${num} remediation applied! Run 'kubectl get all -l scenario=$(printf "s%02d" "$num") -A' to verify."
}

reset_lab() {
  warn "Deleting lab namespaces and cleaning node labels/taints..."
  kubectl delete ns k9s-lab k9s-lab-quota k9s-lab-netpol --ignore-not-found=true
  for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl taint nodes "$node" dedicated=gpu:NoSchedule- 2>/dev/null || true
    kubectl label node "$node" dedicated- disktype- 2>/dev/null || true
  done
  log "Lab reset complete."
}

deploy_lab() {
  # -------------------------------------------------------------
  # 1. Install k9s if missing
  # -------------------------------------------------------------
  if ! command -v k9s &> /dev/null; then
    log "Installing latest k9s binary..."
    curl -sS https://webinstall.dev/k9s | bash
    export PATH="${HOME}/.local/bin:${PATH}"
  else
    log "k9s is already installed: $(k9s version --short 2>/dev/null || k9s version)"
  fi

  # -------------------------------------------------------------
  # 2. Deploy & Patch metrics-server
  # -------------------------------------------------------------
  log "Checking metrics-server status..."
  if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    log "metrics-server not detected. Deploying upstream manifest..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  fi

  log "Ensuring metrics-server has --kubelet-insecure-tls configured..."
  METRICS_ARGS=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}')

  if [[ "$METRICS_ARGS" != *"--kubelet-insecure-tls"* ]]; then
    warn "Patching metrics-server to disable strict Kubelet TLS checks..."
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
  fi

  log "Waiting for metrics-server rollout..."
  kubectl rollout status deployment/metrics-server -n kube-system --timeout=60s

  # -------------------------------------------------------------
  # 2.5 Prepare Node Setup for Taint Scenario (s16)
  # -------------------------------------------------------------
  TARGET_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
  log "Applying test taint and label to target node '${TARGET_NODE}' for Scenario s16..."
  kubectl label node "${TARGET_NODE}" dedicated=gpu --overwrite
  kubectl taint nodes "${TARGET_NODE}" dedicated=gpu:NoSchedule --overwrite

  # -------------------------------------------------------------
  # 3. Deploy Labeled Multi-Scenario Lab Workloads (s01 - s26)
  # -------------------------------------------------------------
  log "Deploying 26 labeled scenarios across 'k9s-lab', 'k9s-lab-quota', and 'k9s-lab-netpol'..."

  cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: k9s-lab
  labels:
    lab: k9s-troubleshooting
---
# =============================================================
# Scenario 1 (s01): Heavy CPU Load
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s01-load-cpu-hog
  namespace: k9s-lab
  labels:
    scenario: s01
    category: resources
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-cpu-hog
      scenario: s01
  template:
    metadata:
      labels:
        app: load-cpu-hog
        scenario: s01
        category: resources
    spec:
      containers:
      - name: stress
        image: vish/stress
        args: ["-cpus", "2"]
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 600m
            memory: 128Mi
---
# =============================================================
# Scenario 2 (s02): OOMKilled Trigger (Exit Code 137)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  namespace: k9s-lab
  labels:
    scenario: s02
    category: resources
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-leak-app
      scenario: s02
  template:
    metadata:
      labels:
        app: memory-leak-app
        scenario: s02
        category: resources
    spec:
      containers:
      - name: leaker
        image: vish/stress
        args: ["-mem-total", "256Mi", "-mem-alloc-size", "16Mi", "-mem-alloc-time", "1s"]
        resources:
          limits:
            memory: 64Mi
---
# =============================================================
# Scenario 3 (s03): Application CrashLoop
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crashing-service
  namespace: k9s-lab
  labels:
    scenario: s03
    category: crashloop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crashing-service
      scenario: s03
  template:
    metadata:
      labels:
        app: crashing-service
        scenario: s03
        category: crashloop
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "[$(date +%T)] Worker initialising storage engine...";
            sleep 4;
            echo "[$(date +%T)] FATAL: Corrupted metadata journal block 0x044fa";
            exit 1;
---
# =============================================================
# Scenario 4 (s04): Missing Secret / CreateContainerConfigError
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: missing-secret-worker
  namespace: k9s-lab
  labels:
    scenario: s04
    category: config
spec:
  replicas: 1
  selector:
    matchLabels:
      app: missing-secret-worker
      scenario: s04
  template:
    metadata:
      labels:
        app: missing-secret-worker
        scenario: s04
        category: config
    spec:
      containers:
      - name: worker
        image: nginx:alpine
        env:
        - name: API_AUTH_KEY
          valueFrom:
            secretKeyRef:
              name: non-existent-prod-secret
              key: token
---
# =============================================================
# Scenario 5 (s05): Healthy Baseline Traffic
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: healthy-frontend
  namespace: k9s-lab
  labels:
    scenario: s05
    category: baseline
spec:
  replicas: 2
  selector:
    matchLabels:
      app: healthy-frontend
      scenario: s05
  template:
    metadata:
      labels:
        app: healthy-frontend
        scenario: s05
        category: baseline
    spec:
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: 25m
            memory: 32Mi
          limits:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: healthy-frontend
  namespace: k9s-lab
  labels:
    scenario: s05
    category: baseline
spec:
  selector:
    app: healthy-frontend
  ports:
  - port: 80
    targetPort: 80
---
# =============================================================
# Scenario 6 (s06): ImagePullBackOff #1 - Nonexistent Tag (404)
# =============================================================
apiVersion: v1
kind: Pod
metadata:
  name: err-image-nonexistent-tag
  namespace: k9s-lab
  labels:
    scenario: s06
    category: imagepull
spec:
  containers:
  - name: alpine
    image: alpine:99.99.99-nonexistent
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# =============================================================
# Scenario 7 (s07): ImagePullBackOff #2 - Invalid Registry DNS
# =============================================================
apiVersion: v1
kind: Pod
metadata:
  name: err-image-invalid-registry
  namespace: k9s-lab
  labels:
    scenario: s07
    category: imagepull
spec:
  containers:
  - name: alpine
    image: invalid-registry.internal-lab.local/library/alpine:latest
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# =============================================================
# Scenario 8 (s08): ImagePullBackOff #3 - Missing Auth (401)
# =============================================================
apiVersion: v1
kind: Pod
metadata:
  name: err-image-unauthorized-private
  namespace: k9s-lab
  labels:
    scenario: s08
    category: imagepull
spec:
  containers:
  - name: private-app
    image: ghcr.io/internal-enterprise-private-org/secure-alpine:latest
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# =============================================================
# Scenario 9 (s09): ImagePullBackOff #4 - Arch Mismatch (s390x)
# =============================================================
apiVersion: v1
kind: Pod
metadata:
  name: err-image-arch-mismatch
  namespace: k9s-lab
  labels:
    scenario: s09
    category: imagepull
spec:
  containers:
  - name: busybox-s390x
    image: s390x/busybox:latest
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# =============================================================
# Scenario 10 (s10): CrashLoopBackOff (Exit 1) - Missing Env Var
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: env-var-crash-app
  namespace: k9s-lab
  labels:
    scenario: s10
    category: crashloop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: env-var-crash-app
      scenario: s10
  template:
    metadata:
      labels:
        app: env-var-crash-app
        scenario: s10
        category: crashloop
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            if [ -z "$REQUIRED_DB_HOST" ]; then
              echo "FATAL: REQUIRED_DB_HOST is missing. Application cannot start."
              exit 1
            fi
            sleep 3600
---
# =============================================================
# Scenario 11 (s11): CrashLoopBackOff (Exit 126) - chmod -x
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: permission-denied-app
  namespace: k9s-lab
  labels:
    scenario: s11
    category: crashloop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: permission-denied-app
      scenario: s11
  template:
    metadata:
      labels:
        app: permission-denied-app
        scenario: s11
        category: crashloop
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "echo 'Running...'" > /tmp/script.sh
            chmod -x /tmp/script.sh
            echo "Attempting to execute script without permissions..."
            /tmp/script.sh
---
# =============================================================
# Scenario 12 (s12): Liveness Probe Failing (HTTP 404)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: liveness-probe-404
  namespace: k9s-lab
  labels:
    scenario: s12
    category: probes
spec:
  replicas: 1
  selector:
    matchLabels:
      app: liveness-probe-404
      scenario: s12
  template:
    metadata:
      labels:
        app: liveness-probe-404
        scenario: s12
        category: probes
    spec:
      containers:
      - name: web
        image: nginx:alpine
        livenessProbe:
          httpGet:
            path: /non-existent-health-check
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 2
---
# =============================================================
# Scenario 13 (s13): Liveness Probe Timeout (Init Delay Short)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: liveness-probe-timeout
  namespace: k9s-lab
  labels:
    scenario: s13
    category: probes
spec:
  replicas: 1
  selector:
    matchLabels:
      app: liveness-probe-timeout
      scenario: s13
  template:
    metadata:
      labels:
        app: liveness-probe-timeout
        scenario: s13
        category: probes
    spec:
      containers:
      - name: slow-starter
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Initializing heavy application (takes 15s)..."
            sleep 15
            touch /tmp/healthy
            echo "Ready."
            sleep 3600
        livenessProbe:
          exec:
            command: ["cat", "/tmp/healthy"]
          initialDelaySeconds: 1
          periodSeconds: 2
          failureThreshold: 2
---
# =============================================================
# Scenario 14 (s14): Pending - Insufficient CPU (128 Cores)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pending-insufficient-cpu
  namespace: k9s-lab
  labels:
    scenario: s14
    category: scheduling
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pending-insufficient-cpu
      scenario: s14
  template:
    metadata:
      labels:
        app: pending-insufficient-cpu
        scenario: s14
        category: scheduling
    spec:
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: "128"
            memory: 64Mi
---
# =============================================================
# Scenario 15 (s15): Pending - NodeSelector Mismatch
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pending-nodeselector-mismatch
  namespace: k9s-lab
  labels:
    scenario: s15
    category: scheduling
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pending-nodeselector-mismatch
      scenario: s15
  template:
    metadata:
      labels:
        app: pending-nodeselector-mismatch
        scenario: s15
        category: scheduling
    spec:
      nodeSelector:
        disktype: super-fast-nvme
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: 25m
            memory: 32Mi
---
# =============================================================
# Scenario 16 (s16): Pending - Untolerated Node Taint
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pending-taint-dedicated-gpu
  namespace: k9s-lab
  labels:
    scenario: s16
    category: scheduling
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pending-taint-dedicated-gpu
      scenario: s16
  template:
    metadata:
      labels:
        app: pending-taint-dedicated-gpu
        scenario: s16
        category: scheduling
    spec:
      nodeSelector:
        dedicated: gpu
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: 25m
            memory: 32Mi
---
# =============================================================
# Scenario 17 (s17): Missing Pods - Blocked by ResourceQuota
# =============================================================
apiVersion: v1
kind: Namespace
metadata:
  name: k9s-lab-quota
  labels:
    scenario: s17
    category: governance
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: strict-quota
  namespace: k9s-lab-quota
  labels:
    scenario: s17
    category: governance
spec:
  hard:
    requests.cpu: "50m"
    requests.memory: "64Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quota-blocked-app
  namespace: k9s-lab-quota
  labels:
    scenario: s17
    category: governance
spec:
  replicas: 2
  selector:
    matchLabels:
      app: quota-blocked-app
      scenario: s17
  template:
    metadata:
      labels:
        app: quota-blocked-app
        scenario: s17
        category: governance
    spec:
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 400m
            memory: 256Mi
---
# =============================================================
# Scenario 18 (s18): Missing Pods - ServiceAccount Not Found
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: missing-sa-app
  namespace: k9s-lab
  labels:
    scenario: s18
    category: rbac-sa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: missing-sa-app
      scenario: s18
  template:
    metadata:
      labels:
        app: missing-sa-app
        scenario: s18
        category: rbac-sa
    spec:
      serviceAccountName: custom-app-sa
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: 25m
            memory: 32Mi
---
# =============================================================
# Scenario 19 (s19): PVC Binding Failure (Missing StorageClass)
# =============================================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pending-pvc-missing-sc
  namespace: k9s-lab
  labels:
    scenario: s19
    category: storage
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: non-existent-fast-ssd
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blocked-by-pvc
  namespace: k9s-lab
  labels:
    scenario: s19
    category: storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-blocked-by-pvc
      scenario: s19
  template:
    metadata:
      labels:
        app: app-blocked-by-pvc
        scenario: s19
        category: storage
    spec:
      containers:
      - name: db
        image: postgres:15-alpine
        volumeMounts:
        - mountPath: /var/lib/postgresql/data
          name: pgdata
      volumes:
      - name: pgdata
        persistentVolumeClaim:
          claimName: pending-pvc-missing-sc
---
# =============================================================
# Scenario 20 (s20): InitContainer Failure (Startup Dependency)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: init-container-failure
  namespace: k9s-lab
  labels:
    scenario: s20
    category: init-deps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: init-container-failure
      scenario: s20
  template:
    metadata:
      labels:
        app: init-container-failure
        scenario: s20
        category: init-deps
    spec:
      initContainers:
      - name: check-db-connectivity
        image: busybox:latest
        command: ["nc", "-z", "non-existent-database-service", "5432"]
      containers:
      - name: web-frontend
        image: nginx:alpine
        resources:
          requests:
            cpu: 25m
            memory: 32Mi
---
# =============================================================
# Scenario 21 (s21): High Memory Request (2GB Node Safety)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-pressure-sim
  namespace: k9s-lab
  labels:
    scenario: s21
    category: scheduling
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-pressure-sim
      scenario: s21
  template:
    metadata:
      labels:
        app: memory-pressure-sim
        scenario: s21
        category: scheduling
    spec:
      containers:
      - name: allocator
        image: vish/stress
        args: ["-mem-total", "200Mi", "-mem-alloc-size", "50Mi", "-mem-alloc-time", "1s"]
        resources:
          requests:
            memory: 1500Mi
          limits:
            memory: 1600Mi
---
# =============================================================
# Scenario 22 (s22): DNS ndots:5 Amplification & Dead Resolver
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dns-ndots-trap
  namespace: k9s-lab
  labels:
    scenario: s22
    category: net-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dns-ndots-trap
      scenario: s22
  template:
    metadata:
      labels:
        app: dns-ndots-trap
        scenario: s22
        category: net-dns
    spec:
      dnsPolicy: "None"
      dnsConfig:
        nameservers:
          - 192.0.2.53
        searches:
          - k9s-lab.svc.cluster.local
          - svc.cluster.local
          - cluster.local
        options:
          - name: ndots
            value: "5"
          - name: timeout
            value: "2"
          - name: attempts
            value: "1"
      containers:
      - name: dns-prober
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              echo "[$(date +%T)] Probing internal service healthy-frontend.k9s-lab.svc.cluster.local..."
              if ! nslookup healthy-frontend.k9s-lab.svc.cluster.local; then
                echo "[$(date +%T)] ERROR: DNS lookup timed out! Check /etc/resolv.conf, ndots, and CoreDNS IP."
              fi
              sleep 5
            done
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
---
# =============================================================
# Scenario 23 (s23): Silent Service Blackhole (Empty Endpoints)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-gateway
  namespace: k9s-lab
  labels:
    scenario: s23
    category: net-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-v1
      scenario: s23
  template:
    metadata:
      labels:
        app: payment-v1
        scenario: s23
        category: net-service
    spec:
      containers:
      - name: api
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
---
apiVersion: v1
kind: Service
metadata:
  name: payment-gateway-svc
  namespace: k9s-lab
  labels:
    scenario: s23
    category: net-service
spec:
  selector:
    app: payment-v2
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: payment-client-prober
  namespace: k9s-lab
  labels:
    app: payment-client-prober
    scenario: s23
    category: net-service
spec:
  containers:
  - name: client
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
      - |
        while true; do
          echo "[$(date +%T)] Calling payment-gateway-svc:80..."
          wget -qO- --timeout=2 http://payment-gateway-svc.k9s-lab.svc.cluster.local:80 >/dev/null || echo "[$(date +%T)] FAILED: Connection refused/timeout (Check Service Endpoints!)"
          sleep 5
        done
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
---
# =============================================================
# Scenario 24 (s24): Service TargetPort Socket Mismatch (RST)
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-backend
  namespace: k9s-lab
  labels:
    scenario: s24
    category: net-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-backend
      scenario: s24
  template:
    metadata:
      labels:
        app: inventory-backend
        scenario: s24
        category: net-service
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
---
apiVersion: v1
kind: Service
metadata:
  name: inventory-svc
  namespace: k9s-lab
  labels:
    scenario: s24
    category: net-service
spec:
  selector:
    app: inventory-backend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
---
# =============================================================
# Scenario 25 (s25): Zero-Trust Egress Lockout (CoreDNS Drop)
# =============================================================
apiVersion: v1
kind: Namespace
metadata:
  name: k9s-lab-netpol
  labels:
    scenario: s25
    category: net-policy
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: strict-zero-trust-egress
  namespace: k9s-lab-netpol
  labels:
    scenario: s25
    category: net-policy
spec:
  podSelector:
    matchLabels:
      app: isolated-microservice
  policyTypes:
  - Egress
  egress: []
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: isolated-microservice
  namespace: k9s-lab-netpol
  labels:
    scenario: s25
    category: net-policy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: isolated-microservice
      scenario: s25
  template:
    metadata:
      labels:
        app: isolated-microservice
        scenario: s25
        category: net-policy
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              echo "[$(date +%T)] Attempting service discovery via CoreDNS..."
              if ! nslookup kubernetes.default.svc.cluster.local; then
                echo "[$(date +%T)] BLOCKED: Egress NetworkPolicy is dropping UDP/TCP 53 to CoreDNS!"
              fi
              sleep 5
            done
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
---
# =============================================================
# Scenario 26 (s26): AI Infra Missing Secondary RDMA Interface
# =============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nccl-rdma-worker
  namespace: k9s-lab
  labels:
    scenario: s26
    category: ai-networking
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nccl-rdma-worker
      scenario: s26
  template:
    metadata:
      labels:
        app: nccl-rdma-worker
        scenario: s26
        category: ai-networking
      annotations:
        k8s.v1.cni.cncf.io/networks: sriov-rdma-net
    spec:
      containers:
      - name: nccl-trainer
        image: busybox:latest
        env:
        - name: REQUIRED_IFACE
          value: "net1"
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "[$(date +%T)] Initializing NCCL Distributed AllReduce..."
            if ! ip link show "$REQUIRED_IFACE" >/dev/null 2>&1; then
              echo "[$(date +%T)] FATAL: Secondary RDMA interface '$REQUIRED_IFACE' not found! Multus CNI / SR-IOV NAD missing."
              exit 1
            fi
            echo "NCCL bound to $REQUIRED_IFACE. Training started."
            sleep 3600
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
EOF

  # -------------------------------------------------------------
  # 4. Wait for metrics API synchronization
  # -------------------------------------------------------------
  log "Waiting 15 seconds for first metrics scrape cycle to complete..."
  sleep 15

  log "Cluster verification:"
  kubectl top nodes || true

  echo -e "\n\033[1;36m========================================================================\033[0m"
  echo -e " Environment Ready! Quick Commands:"
  echo -e "   1. List all labeled scenarios : \033[1;33m$0 --list\033[0m"
  echo -e "   2. View step-by-step solution : \033[1;33m$0 --solve 22\033[0m"
  echo -e "   3. Auto-apply fix for #22     : \033[1;33m$0 --auto-fix 22\033[0m"
  echo -e "   4. Filter by scenario in k9s  : \033[1;33mk9s -n k9s-lab\033[0m then type \033[1;32m/-l scenario=s22\033[0m"
  echo -e "\033[1;36m========================================================================\033[0m\n"
}

# -------------------------------------------------------------
# Main CLI Dispatcher
# -------------------------------------------------------------
MODE="${1:---deploy}"

case "$MODE" in
  --deploy|-d)
    deploy_lab
    ;;
  --list|-l)
    list_scenarios
    ;;
  --solve|-s)
    if [[ -z "${2:-}" ]]; then
      err "Please provide a scenario number (1-26). Example: $0 --solve 22"
      exit 1
    fi
    solve_scenario "$2"
    ;;
  --auto-fix|-f)
    if [[ -z "${2:-}" ]]; then
      err "Please provide a scenario number (1-26). Example: $0 --auto-fix 22"
      exit 1
    fi
    auto_fix_scenario "$2"
    ;;
  --reset|-r)
    reset_lab
    ;;
  --help|-h)
    usage
    ;;
  *)
    err "Unknown option: $MODE"
    usage
    exit 1
    ;;
esac
