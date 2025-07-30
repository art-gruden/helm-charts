#!/bin/bash

# Define the namespace - Assuming this namespace ALREADY EXISTS
NAMESPACE="monitoring"
SECRET_NAME="gchat-webhook-url"

# --- Create the Kubernetes Secret (if you haven't already) ---
# This ensures your webhook URL is stored securely as a Secret, not directly in Helm values.
read -p "Enter your Google Chat Webhook URL (e.g., https://chat.googleapis.com/v1/spaces/...): " GOOGLE_CHAT_WEBHOOK_URL

echo "Creating Kubernetes Secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl create secret generic "$SECRET_NAME" \
  --from-literal=notification-url="$GOOGLE_CHAT_WEBHOOK_URL" \
  --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '$SECRET_NAME' created successfully in namespace '$NAMESPACE'."

# --- Deploy the Helm Chart ---
echo "Deploying alertmanager-gchat-integration Helm chart..."
helm upgrade --install alertmanager-gchat-integration gruden-charts/alertmanager-gchat-integration \
  --namespace "$NAMESPACE" \
  --version 1.0.5 \
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
  --set "alertManagerGChatIntegration.notificationTemplateJsonJ2=|\n    {%- if labels.severity == 'critical' -%}\n    {% set icon_unicode = '\\u274C\\u274C' %}\n    {%- elif labels.severity == 'error' -%}\n    {% set icon_unicode = '\\u274C' %}\n    {%- elif labels.severity == 'warning' -%}\n    {% set icon_unicode = '\\u26A0' %}\n    {%- elif labels.severity == 'info' -%}\n    {% set icon_unicode = '\\u2139' %}\n    {%- endif -%}\n    {{ icon_unicode }} *{{ labels.alertname }} - {{ status | title }}* (Origin: _{{ origin }}_)\n    ```\n    {% for key, value in annotations.items() -%}\n    {{ key | title }}: {{ value }}\n    {% endfor -%}\n    ```" \
  # IMPORTANT: These labels might *still* cause a Forbidden error if the Helm chart's templates
  # do not explicitly support generic extraLabels or a similar mechanism.
  # If it fails, you would need to modify the Helm chart's templates directly in your forked repo.
  --set "extraLabels.app\.kubernetes\.io/name=alertmanager-gchat-integration" \
  --set "extraLabels.kiwigrid_com_operated_by=sre" \
  --set "extraLabels.kiwigrid_com_owned_by=sre"

echo "Helm deployment initiated. Check `helm history alertmanager-gchat-integration` for status."
echo "Then, check Kubernetes resources: `kubectl get all -n $NAMESPACE -l app=alertmanager-gchat-integration`"
echo "And pod logs: `kubectl logs -f -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -l app=alertmanager-gchat-integration -o jsonpath='{.items[0].metadata.name}')`"
