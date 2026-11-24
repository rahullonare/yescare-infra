#!/bin/bash
set -e

DOCTL_BIN="${DOCTL_PATH:-doctl}"
KUBECTL_BIN="kubectl.exe"

CTX="do-sgp1-yescare-pre-prod-scale-k8s"
KCFG='C:\Users\HP 745 G6\.kube\config'

echo "=== Setting up Kafka ==="

"${DOCTL_BIN}" kubernetes cluster kubeconfig save \
  yescare-pre-prod-scale-k8s \
  --set-current-context

echo
echo "=== Kubeconfig verification ==="

echo "Kubeconfig: $KCFG"

"${KUBECTL_BIN}" --kubeconfig="$KCFG" config get-contexts

echo
echo "Current context:"

CURRENT_CTX="$("${KUBECTL_BIN}" --kubeconfig="$KCFG" config current-context)"

echo "Current context: $CURRENT_CTX"

if [ "$CURRENT_CTX" != "$CTX" ]; then
  echo "Selecting context: $CTX"

  "${KUBECTL_BIN}" \
    --kubeconfig="$KCFG" \
    config use-context "$CTX"
fi

echo
echo "Current context final:"

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  config current-context

echo
echo "=== Testing cluster access ==="

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  get nodes

echo
echo "=== Creating messaging namespace ==="

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  create namespace messaging \
  --dry-run=client \
  -o yaml |
"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  --validate=false \
  apply -f -

echo
echo "=== Applying Kafka ==="

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  apply \
  --validate=false \
  -f "$(dirname "$0")/kafka.yaml"

echo
echo "=== Waiting for Kafka StatefulSet ==="

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  rollout status \
  statefulset/kafka \
  -n messaging \
  --timeout=300s

echo
echo "=== Waiting for Kafka pods ==="

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  wait \
  --for=condition=ready \
  pod \
  -l app=kafka \
  -n messaging \
  --timeout=300s

echo
echo "=== Waiting 15 seconds for Kafka to stabilize ==="

sleep 15

echo
echo "=== Creating Kafka topics ==="

TOPICS=(
  appointment.created
  appointment.updated
  consultation.started
  consultation.ended
  notification.send
  payment.processed
  doctor.onboarded
  user.signup
  consultation.completed
  consultation.cancel
  consultation.rejected
  consultation.prescribed
  doctor.force.logout
  doctor.display.ready
  consultation.assigned
  consultation.cancelled
  consultation.request
  consultation.accepted
  consultation.request.fcm
  doctor.presence.changed
  gateway.consultation.assign
  gateway.consultation.cancel
  gateway.consultation.complete
  gateway.consultation.in_progress
)

for topic in "${TOPICS[@]}"; do
  echo "Creating topic: $topic"

  "${KUBECTL_BIN}" \
    --kubeconfig="$KCFG" \
    --context="$CTX" \
    exec \
    -n messaging \
    kafka-0 \
    -- \
    /opt/kafka/bin/kafka-topics.sh \
    --create \
    --if-not-exists \
    --bootstrap-server localhost:9092 \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor 3
done

echo
echo "=== Kafka topics ==="

"${KUBECTL_BIN}" \
  --kubeconfig="$KCFG" \
  --context="$CTX" \
  exec \
  -n messaging \
  kafka-0 \
  -- \
  /opt/kafka/bin/kafka-topics.sh \
  --list \
  --bootstrap-server localhost:9092

echo
echo "=================================================="
echo "=== Kafka setup complete ==="
echo "=================================================="