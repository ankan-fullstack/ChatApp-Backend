set -oe errexit

# desired cluster name; default is "kind"
KIND_CLUSTER_NAME="chatapp-backend"

kind delete clusters $KIND_CLUSTER_NAME

# default registry name and port
reg_name='chatapp-registry'
reg_port='5000'

echo "> initializing Docker registry"

# create registry container unless it already exists
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

echo "> initializing Kind cluster: ${KIND_CLUSTER_NAME} with registry ${reg_name}"

# create a cluster with the local registry enabled in containerd
cat <<EOF | kind create cluster --name "${KIND_CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.26.0
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:${reg_port}"]
EOF

#Checking if the registry and cluster is on same network
if ["$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = "null"]; then
    docker network connect "kind" "${reg_name}"
fi

echo "> applying local-registry docs"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF