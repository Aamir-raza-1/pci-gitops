#!/bin/bash
set -euo pipefail

# ---------------- CONFIG ----------------
PROJECT_ID="dev-ezo"
SA_NAME="cnrm-local-sa-$(date +%s)"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="gcp-key.json"

OP_NS="configconnector-operator-system"
CNRM_NS="cnrm-system"
RES_NS="gcp-resources"

BUCKET_NAME="cnrm-local-bucket-$(date +%s)"

RELEASE_TAR="release-bundle.tar.gz"
RELEASE_DIR="release-bundle"
PATCHED_MANIFEST="install-local.yaml"

# ------------- HELPERS ------------------
info()    { echo -e "\n🔹 $1"; }
success() { echo -e "\n✅ $1"; }
fail()    { echo -e "\n❌ $1"; exit 1; }

# ------------- PRECHECK -----------------
command -v kubectl >/dev/null || fail "kubectl missing"
command -v gcloud  >/dev/null || fail "gcloud missing"
command -v yq      >/dev/null || fail "yq missing"
command -v tar     >/dev/null || fail "tar missing"

# ------------- CLEANUP ------------------
info "Cleaning old namespaces"
kubectl delete ns ${OP_NS} ${CNRM_NS} ${RES_NS} --ignore-not-found
sleep 10

rm -rf ${RELEASE_DIR} ${RELEASE_TAR} ${PATCHED_MANIFEST}

# -------- DOWNLOAD RELEASE --------------
info "Downloading latest Config Connector release bundle"
gcloud storage cp \
  gs://configconnector-operator/latest/release-bundle.tar.gz \
  ${RELEASE_TAR}

tar zxvf ${RELEASE_TAR}
success "Release bundle extracted"

# -------- LOCATE OPERATOR MANIFEST ------
info "Locating operator manifest from extracted bundle"

ORIGINAL_MANIFEST="operator-system/configconnector-operator.yaml"

if [[ ! -f "${ORIGINAL_MANIFEST}" ]]; then
  fail "Expected operator manifest not found at ${ORIGINAL_MANIFEST}"
fi

echo "Using manifest: ${ORIGINAL_MANIFEST}"


[[ -f "${ORIGINAL_MANIFEST}" ]] || fail "Operator manifest not found"

echo "Using manifest: ${ORIGINAL_MANIFEST}"

# -------- PATCH MANIFEST FOR KIND -------
info "Patching operator manifest for local Kind use"

yq eval '
  del(. | select(.kind == "ClusterPodMonitoring")) |
  del(.spec.template.spec.containers[] | select(.name == "prom-to-sd")) |
  (
    select(.kind=="StatefulSet" and .metadata.name=="cnrm-controller-manager")
    .spec.template.spec.volumes += [{"name":"gcp-sa-key","secret":{"secretName":"gcp-sa-key"}}]
  ) |
  (
    select(.kind=="StatefulSet" and .metadata.name=="cnrm-controller-manager")
    .spec.template.spec.containers[] | select(.name=="manager")
  ).volumeMounts += {"name":"gcp-sa-key","mountPath":"/gcp","readOnly":true} |
  (
    select(.kind=="StatefulSet" and .metadata.name=="cnrm-controller-manager")
    .spec.template.spec.containers[] | select(.name=="manager")
  ).env += {"name":"GOOGLE_APPLICATION_CREDENTIALS","value":"/gcp/key.json"}
' "${ORIGINAL_MANIFEST}" > "${PATCHED_MANIFEST}"

success "Local operator manifest created"

# -------- GCP SERVICE ACCOUNT ----------
info "Creating GCP Service Account"
gcloud iam service-accounts create "${SA_NAME}" \
  --project="${PROJECT_ID}" \
  --display-name="Config Connector Local"

sleep 10

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor" \
  --condition=None >/dev/null

gcloud iam service-accounts keys create "${KEY_FILE}" \
  --iam-account="${SA_EMAIL}"

success "GCP Service Account ready"

# -------- SUPPORTING MANIFESTS ----------
info "Generating supporting manifests"

cat <<EOF > configconnector.yaml
apiVersion: core.cnrm.cloud.google.com/v1beta1
kind: ConfigConnector
metadata:
  name: configconnector.core.cnrm.cloud.google.com
spec:
  mode: cluster
  credentialSecretName: gcp-sa-key
EOF

cat <<EOF > namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${RES_NS}
  annotations:
    cnrm.cloud.google.com/project-id: ${PROJECT_ID}
EOF

cat <<EOF > bucket.yaml
apiVersion: storage.cnrm.cloud.google.com/v1beta1
kind: StorageBucket
metadata:
  name: ${BUCKET_NAME}
  namespace: ${RES_NS}
  annotations:
    cnrm.cloud.google.com/project-id: ${PROJECT_ID}
spec:
  location: US-CENTRAL1
EOF

success "Manifests generated"

# -------- INSTALL OPERATOR --------------
info "Creating namespaces"
kubectl create ns ${OP_NS}
kubectl create ns ${CNRM_NS}

info "Creating GCP credential secret"
kubectl create secret generic gcp-sa-key \
  --from-file=key.json=${KEY_FILE} \
  -n ${CNRM_NS}

info "Installing Config Connector operator"
kubectl apply -f "${PATCHED_MANIFEST}"

info "Waiting for operator StatefulSet rollout to complete"

kubectl rollout status statefulset/configconnector-operator \
  -n ${OP_NS} --timeout=5m



success "Operator running"
sleep 30

# -------- ACTIVATE CONFIG CONNECTOR -----
info "Applying ConfigConnector CR"
kubectl apply -f configconnector.yaml

info "Waiting for Config Connector to become healthy"
sleep 100
until [[ "$(kubectl get configconnector configconnector.core.cnrm.cloud.google.com \
  -o jsonpath='{.status.healthy}')" == "true" ]]; do
  echo "Config Connector not healthy yet, waiting..."
  sleep 5
done

success "Config Connector is healthy"


# -------- VERIFY CRDs -------------------
info "Waiting for StorageBucket CRD"
until kubectl get crd storagebuckets.storage.cnrm.cloud.google.com >/dev/null 2>&1; do
  sleep 2
done

# -------- APPLY TEST RESOURCE -----------
info "Applying test namespace and bucket"
kubectl apply -f namespace.yaml
kubectl apply -f bucket.yaml

info "Waiting for bucket Ready"
kubectl wait --for=condition=Ready --timeout=5m \
  -n ${RES_NS} storagebucket/${BUCKET_NAME}

info "Verifying bucket exists in GCP"
gcloud storage buckets describe "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" --format="value(name)"

success "🎉 CONFIG CONNECTOR LOCAL SETUP VERIFIED END-TO-END"
