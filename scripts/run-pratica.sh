#!/usr/bin/env bash
set -euo pipefail

EVIDENCIAS="${EVIDENCIAS:-evidencias}"
mkdir -p "$EVIDENCIAS"

cleanup() {
  if [ -f /tmp/kubectl-proxy.pid ]; then
    kill "$(cat /tmp/kubectl-proxy.pid)" 2>/dev/null || true
  fi
  minikube delete --all --purge >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "AÇÃO 1 - INSTALAÇÃO DO KUBERNETES" | tee "$EVIDENCIAS/01-acao1-instalacao.txt"

curl -fsSLo /tmp/minikube-linux-amd64 \
  https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install -m 0755 /tmp/minikube-linux-amd64 /usr/local/bin/minikube

KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl

{
  echo "Runner: ubuntu-24.04"
  docker --version
  minikube version
  kubectl version --client=true
} | tee "$EVIDENCIAS/02-versoes.txt"

minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=3900mb \
  --kubernetes-version=stable \
  | tee "$EVIDENCIAS/03-minikube-start.txt"

{
  minikube status
  kubectl cluster-info
  kubectl get nodes -o wide
} | tee "$EVIDENCIAS/04-cluster-status.txt"

echo "AÇÃO 2 - DEPLOY, EXPOSIÇÃO E ESCALONAMENTO" | tee "$EVIDENCIAS/05-acao2-deploy.txt"

kubectl create deployment nginx --image=nginx:1.27-alpine \
  | tee "$EVIDENCIAS/06-nginx-create.txt"
kubectl expose deployment nginx --type=NodePort --port=80 \
  | tee "$EVIDENCIAS/07-nginx-expose.txt"
kubectl rollout status deployment/nginx --timeout=180s \
  | tee "$EVIDENCIAS/08-nginx-rollout.txt"

{
  kubectl get deployments -o wide
  kubectl get pods -o wide
  kubectl get services -o wide
} | tee "$EVIDENCIAS/09-nginx-status-1-replica.txt"

NODE_PORT="$(kubectl get service nginx -o jsonpath='{.spec.ports[0].nodePort}')"
MINIKUBE_IP="$(minikube ip)"
NGINX_URL="http://${MINIKUBE_IP}:${NODE_PORT}"
{
  echo "URL do serviço: ${NGINX_URL}"
  curl -fsSI --retry 10 --retry-delay 3 "$NGINX_URL" | sed -n '1,8p'
} | tee "$EVIDENCIAS/10-nginx-http.txt"

minikube addons enable metrics-server \
  | tee "$EVIDENCIAS/11-addon-metrics-server.txt"
minikube addons enable dashboard \
  | tee "$EVIDENCIAS/12-addon-dashboard.txt"

kubectl -n kubernetes-dashboard rollout status deployment/kubernetes-dashboard --timeout=240s \
  | tee "$EVIDENCIAS/13-dashboard-rollout.txt"
kubectl apply -f kubernetes/dashboard-adminuser.yaml \
  | tee "$EVIDENCIAS/14-dashboard-adminuser.txt"
kubectl -n kubernetes-dashboard create token admin-user --duration=1h > /tmp/dashboard-token
chmod 600 /tmp/dashboard-token

kubectl proxy --port=8001 --address=127.0.0.1 > "$EVIDENCIAS/15-kubectl-proxy.txt" 2>&1 &
echo $! > /tmp/kubectl-proxy.pid

DASHBOARD_URL="http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/"
export DASHBOARD_URL
export DASHBOARD_TOKEN_FILE=/tmp/dashboard-token

for tentativa in $(seq 1 36); do
  if curl -fsS "$DASHBOARD_URL" >/dev/null; then
    break
  fi
  if [ "$tentativa" -eq 36 ]; then
    echo "O Kubernetes Dashboard não ficou disponível." >&2
    exit 1
  fi
  sleep 5
done

node scripts/capturar-dashboard.js \
  "$EVIDENCIAS/01-dashboard-uma-replica.png" \
  '#/deployment/default/nginx?namespace=default'

kubectl scale deployment nginx --replicas=3 \
  | tee "$EVIDENCIAS/16-nginx-scale.txt"
kubectl rollout status deployment/nginx --timeout=180s \
  | tee "$EVIDENCIAS/17-nginx-scale-rollout.txt"

{
  kubectl get deployment nginx -o wide
  kubectl get pods -l app=nginx -o wide
} | tee "$EVIDENCIAS/18-nginx-status-3-replicas.txt"

node scripts/capturar-dashboard.js \
  "$EVIDENCIAS/02-dashboard-tres-replicas.png" \
  '#/pod?namespace=default'

echo "AÇÃO 3 - DASHBOARD, NOVOS CONTÊINERES E ANÁLISE" | tee "$EVIDENCIAS/19-acao3-dashboard.txt"

kubectl create deployment web-secundario --image=httpd:2.4-alpine \
  | tee "$EVIDENCIAS/20-web-secundario.txt"
kubectl create deployment gerador-carga --image=busybox:1.36 -- \
  /bin/sh -c 'while true; do wget -q -O- http://nginx >/dev/null; done' \
  | tee "$EVIDENCIAS/21-gerador-carga.txt"

kubectl rollout status deployment/web-secundario --timeout=180s
kubectl rollout status deployment/gerador-carga --timeout=180s

for tentativa in $(seq 1 24); do
  if kubectl top pods -n default > "$EVIDENCIAS/22-metricas-pods.txt" 2>/dev/null; then
    break
  fi
  if [ "$tentativa" -eq 24 ]; then
    echo "Métricas ainda não disponíveis após a espera." > "$EVIDENCIAS/22-metricas-pods.txt"
  fi
  sleep 5
done

{
  echo "DEPLOYMENTS"
  kubectl get deployments -o wide
  echo
  echo "PODS"
  kubectl get pods -o wide
  echo
  echo "SERVICES"
  kubectl get services -o wide
  echo
  echo "MÉTRICAS"
  cat "$EVIDENCIAS/22-metricas-pods.txt"
} | tee "$EVIDENCIAS/23-recursos-finais.txt"

kubectl get events --sort-by=.metadata.creationTimestamp \
  | tee "$EVIDENCIAS/24-eventos.txt"
kubectl describe deployment nginx \
  | tee "$EVIDENCIAS/25-describe-nginx.txt"
kubectl logs deployment/gerador-carga --tail=30 \
  > "$EVIDENCIAS/26-logs-gerador-carga.txt" 2>&1 || true

sleep 25
node scripts/capturar-dashboard.js \
  "$EVIDENCIAS/03-dashboard-recursos-e-logs.png" \
  '#/workloads?namespace=default'

{
  echo "RESULTADO DA PRÁTICA 09"
  echo "Cluster: single node Minikube com driver Docker"
  echo "Nginx: serviço NodePort acessível por HTTP"
  echo "Escalonamento: deployment nginx com 3 réplicas disponíveis"
  echo "Deployments adicionais: web-secundario e gerador-carga"
  echo "Dashboard: habilitado, autenticado e capturado em três momentos"
  echo "Métricas e logs: coletados nos arquivos de evidência"
} | tee "$EVIDENCIAS/27-resumo.txt"

file "$EVIDENCIAS"/*.png | tee "$EVIDENCIAS/28-validacao-imagens.txt"
echo "Prática 09 concluída com sucesso."
