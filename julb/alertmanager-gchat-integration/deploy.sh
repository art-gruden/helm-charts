#!/bin/bash

# Define the namespace - Assuming this namespace ALREADY EXISTS
NAMESPACE="monitoring"
SECRET_NAME="gchat-webhook-url"
CUSTOM_VALUES_FILE="my-custom-values.yaml" # New file for template

# --- Create the Kubernetes Secret (if you haven't already) ---
# This ensures your webhook URL is stored securely as a Secret, not directly in Helm values.
read -p "Enter your Google Chat Webhook URL (e.g., https://chat.googleapis.com/v1/spaces/...): " GOOGLE_CHAT_WEBHOOK_URL

echo "Creating Kubernetes Secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl create secret generic "$SECRET_NAME" \
  --from-literal=notification-url="$GOOGLE_CHAT_WEBHOOK_URL" \
  --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '$SECRET_NAME' created successfully in namespace '$NAMESPACE'."

# --- Create custom values.yaml for the template ---
echo "Creating custom values file: $CUSTOM_VALUES_FILE"
cat <<EOF > "$CUSTOM_VALUES_FILE"
alertManagerGChatIntegration:
  notificationTemplateJsonJ2: |
    {%- if labels.severity == 'critical' -%}
    {% set icon_unicode = '\\u274C\\u274C' %}
    {%- elif labels.severity == 'error' -%}
    {% set icon_unicode = '\\u274C' %}
    {%- elif labels.severity == 'warning' -%}
    {% set icon_unicode = '\\u26A0' %}
    {%- elif labels.severity == 'info' -%}\u0020
    {% set icon_unicode = '\\u2139' %}
    {%- endif -%}
    {{ icon_unicode }} *{{ labels.alertname }} - {{ status | title }}* (Origin: _{{ origin }}_)
    ```
    {% for key, value in annotations.items() -%}
    {{ key | title }}: {{ value }}
    {% endfor -%}
    ```
EOF
echo "Custom values file '$CUSTOM_VALUES_FILE' created."


# --- Deploy the Helm Chart ---
echo "Deploying alertmanager-gchat-integration Helm chart..."
helm upgrade --install alertmanager-gchat-integration gruden-charts/alertmanager-gchat-integration \
  --namespace "$NAMESPACE" \
  --version 1.0.5 \
  -f "$CUSTOM_VALUES_FILE" \
  --set replicaCount=1 \
  --set image.tag=1.0.5 \
  --set "alertManagerGChatIntegration.configToml.rooms[0].name=default" \
  --set "alertManagerGChatIntegration.configToml.rooms[0].notificationUrlFromSecret.name=$SECRET_NAME" \
  --set "alertManagerGChatIntegration.configToml.rooms[0].notificationUrlFromSecret.key=notification-url" \
  --set "podSecurityContext.fsGroup=65534" \
  --set "securityContext.runAsNonRoot=true" \
  --set "securityContext.runAsUser=65534" \
  --set "securityContext.runAsGroup=65534" \
  --set "serviceAccount.create=true" \
  --set "serviceAccount.name=alertmanager-gchat-integration" \
  # IMPORTANT: These labels must be added directly to the chart's templates/deployment.yaml
  # as this chart does not support generic extraLabels via --set.
  # If the below --set for extraLabels doesn't work (which is likely), you MUST modify the chart source.
  --set "extraLabels.app\.kubernetes\.io/name=alertmanager-gchat-integration" \
  --set "extraLabels.kiwigrid_com_operated_by=sre" \
  --set "extraLabels.kiwigrid_com_owned_by=sre"

echo "Helm deployment initiated. Check `helm history alertmanager-gchat-integration` for status."
echo "Then, check Kubernetes resources: `kubectl get all -n $NAMESPACE -l app=alertmanager-gchat-integration`"
echo "And pod logs: `kubectl logs -f -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -l app=alertmanager-gchat-integration -o jsonpath='{.items[0].metadata.name}')`"

# --- REMINDER: Configure Alertmanager ---
echo ""
echo "--- Next Steps: Configure Alertmanager ---"
echo "You still need to configure your Prometheus Alertmanager to send webhooks to this service."
echo "Here's an example AlertmanagerConfig for your reference:"
echo "---"
echo "apiVersion: monitoring.coreos.com/v1alpha1"
echo "kind: AlertmanagerConfig"
echo "metadata:"
echo "  name: gchat-receiver"
echo "  namespace: $NAMESPACE"
echo "  labels:"
echo "    alertmanager-config: enabled"
echo "    kiwigrid_com_operated_by: dpe"
echo "    kiwigrid_com_owned_by: dpe"
echo "spec:"
echo "  receivers:"
echo "  - name: google-chat-default"
echo "    webhookConfigs:"
echo "    - sendResolved: true"
echo "      url: http://alertmanager-gchat-integration.$NAMESPACE.svc.cluster.local:80/alerts?room=default"
echo "  route:"
echo "    receiver: google-chat-default"
echo "    groupWait: 30s"
echo "    groupInterval: 5m"
echo "    repeatInterval: 4h"
echo "---"
echo "Save this as a YAML file (e.g., alertmanager-gchat-config.yaml) and apply it:"
echo "kubectl apply -f alertmanager-gchat-config.yaml -n $NAMESPACE"
echo "Remember to verify the labels required by your cluster's policies for this AlertmanagerConfig resource as well."