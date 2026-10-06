# Prática 09 — Instalando e utilizando Kubernetes

Projeto reproduzível para instalar Minikube e kubectl, iniciar um cluster Kubernetes single node, implantar e expor o Nginx, realizar escalonamento manual e analisar os recursos pelo Kubernetes Dashboard.

## O que a automação executa

- instala e verifica Minikube e kubectl;
- inicia um cluster com o driver Docker;
- cria o deployment `nginx` e o expõe como serviço NodePort;
- testa o acesso HTTP ao Nginx;
- escala o deployment de uma para três réplicas;
- cria os deployments adicionais `web-secundario` e `gerador-carga`;
- habilita Metrics Server e Kubernetes Dashboard;
- registra pods, deployments, services, métricas, eventos e logs;
- produz três capturas reais do Kubernetes Dashboard;
- publica o artefato `evidencias-pratica-09` no GitHub Actions.

## Execução

Em uma máquina Linux com Docker e sudo disponíveis:

```bash
chmod +x scripts/*.sh
./scripts/run-pratica.sh
```

As evidências são gravadas na pasta `evidencias/`. O workflow `.github/workflows/kubernetes.yml` executa a mesma sequência em um runner Ubuntu real.

## Arquivos principais

- `scripts/run-pratica.sh`: instalação, cluster, deployments, testes e coleta;
- `scripts/capturar-dashboard.js`: autenticação e capturas do dashboard;
- `kubernetes/dashboard-adminuser.yaml`: conta temporária para acesso ao dashboard;
- `.github/workflows/kubernetes.yml`: validação automatizada completa.
