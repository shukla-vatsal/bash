#!/usr/bin/env bash
set -euo pipefail

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

warn() {
  echo -e "\033[1;33m[!] $1\033[0m"
}

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
# 3. Deploy Multi-Scenario Lab Workloads
# -------------------------------------------------------------
log "Deploying k9s playground workloads to namespace 'k9s-lab'..."

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: k9s-lab
---
# Scenario 1: Heavy CPU Load
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-cpu-hog
  namespace: k9s-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-cpu-hog
  template:
    metadata:
      labels:
        app: load-cpu-hog
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
# Scenario 2: OOMKilled Trigger
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  namespace: k9s-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-leak-app
  template:
    metadata:
      labels:
        app: memory-leak-app
    spec:
      containers:
      - name: leaker
        image: vish/stress
        args: ["-mem-total", "256Mi", "-mem-alloc-size", "16Mi", "-mem-alloc-time", "1s"]
        resources:
          limits:
            memory: 64Mi
---
# Scenario 3: Application CrashLoop
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crashing-service
  namespace: k9s-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crashing-service
  template:
    metadata:
      labels:
        app: crashing-service
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
# Scenario 4: Broken ConfigMap / Pending Pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: missing-secret-worker
  namespace: k9s-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: missing-secret-worker
  template:
    metadata:
      labels:
        app: missing-secret-worker
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
# Scenario 5: Healthy Baseline Traffic
apiVersion: apps/v1
kind: Deployment
metadata:
  name: healthy-frontend
  namespace: k9s-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: healthy-frontend
  template:
    metadata:
      labels:
        app: healthy-frontend
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
# Scenario 6: ImagePullBackOff #1 - Nonexistent Tag (404 Not Found)
apiVersion: v1
kind: Pod
metadata:
  name: err-image-nonexistent-tag
  namespace: k9s-lab
spec:
  containers:
  - name: alpine
    image: alpine:99.99.99-nonexistent
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# Scenario 7: ImagePullBackOff #2 - DNS / Unresolvable Registry Domain
apiVersion: v1
kind: Pod
metadata:
  name: err-image-invalid-registry
  namespace: k9s-lab
spec:
  containers:
  - name: alpine
    image: invalid-registry.internal-lab.local/library/alpine:latest
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# Scenario 8: ImagePullBackOff #3 - Missing Registry Auth / 401 Unauthorized
apiVersion: v1
kind: Pod
metadata:
  name: err-image-unauthorized-private
  namespace: k9s-lab
spec:
  containers:
  - name: private-app
    image: ghcr.io/internal-enterprise-private-org/secure-alpine:latest
    imagePullPolicy: Always
    command: ["sleep", "3600"]
---
# Scenario 9: ImagePullBackOff #4 - Host Architecture Incompatibility (s390x on x86_64)
apiVersion: v1
kind: Pod
metadata:
  name: err-image-arch-mismatch
  namespace: k9s-lab
spec:
  containers:
  - name: busybox-s390x
    image: s390x/busybox:latest
    imagePullPolicy: Always
    command: ["sleep", "3600"]
EOF

# -------------------------------------------------------------
# 4. Wait for metrics API synchronization
# -------------------------------------------------------------
log "Waiting 15 seconds for first metrics scrape cycle to complete..."
sleep 15

log "Cluster verification:"
kubectl top nodes || true

echo -e "\n\033[1;36m================================================================"
echo -e " Environment Ready! Launch k9s with:"
echo -e "   k9s -n k9s-lab"
echo -e "================================================================\033[0m\n"
