#!/bin/bash

NAMESPACE="monitoring"
SECRET_NAME="calert-google-chat-webhook"
CALERT_CONFIGMAP_FILE="calert-configmap.yaml"
CALERT_DEPLOYMENT_FILE="calert-deployment.yaml"
CALERT_SERVICE_FILE="calert-service.yaml"


# --- Create Secret for Google Chat Webhook URL ---
read -p "Enter your Google Chat Webhook URL: " GOOGLE_CHAT_WEBHOOK_URL
echo "Creating Kubernetes Secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl create secret generic "$SECRET_NAME" \
  --from-literal=webhook-url="$GOOGLE_CHAT_WEBHOOK_URL" \
  --namespace "$NAMESPACE"
echo "Secret '$SECRET_NAME' created successfully."

# --- Create calert ConfigMap ---

echo "Applying calert ConfigMap..."
kubectl apply -f "$CALERT_CONFIGMAP_FILE" -n "$NAMESPACE"
echo "ConfigMap 'calert-config' applied."

# --- Create calert Deployment ---
echo "Applying calert Deployment..."
kubectl apply -f "$CALERT_DEPLOYMENT_FILE" -n "$NAMESPACE"
echo "Deployment 'calert' applied."

# --- Create calert Service ---

echo "Applying calert Service..."
kubectl apply -f "$CALERT_SERVICE_FILE" -n "$NAMESPACE"
echo "Service 'calert' applied."

echo "calert installation script completed. Verify resources:"
kubectl get all -n "$NAMESPACE" -l app=calert

echo ""
echo "--- Next Steps: Configure Alertmanager ---"
echo "You need to configure your Prometheus Alertmanager to send webhooks to calert."
echo "Add the following receiver to your Alertmanager configuration (e.g., in alertmanager.yml):"
echo ""
echo "receivers:"
echo "- name: 'google-chat-calert'"
echo "  webhook_configs:"
echo "  - url: 'http://calert.monitoring.svc.cluster.local:6000/dispatch?room=your-chat-room'"
echo "    send_resolved: true"
echo ""
echo "Then, route your desired alerts to this receiver."
echo "Remember to replace 'your-chat-room' with the actual room name you defined in calert-configmap.yaml."
echo "If you modify 'your-chat-room' in the ConfigMap, remember to update the env variable name too: CALERT_PROVIDERS_YOUR_NEW_ROOM_NAME__ENDPOINT."