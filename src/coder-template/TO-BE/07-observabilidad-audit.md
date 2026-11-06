# Sección 7: Observabilidad y Audit

## Estado: ✅ Aprobada

## Capas de Observabilidad

1. **Coder Audit Log** (built-in): workspace lifecycle, logins, template changes
2. **Claude Code Usage** (custom): tokens, tool calls, skills, MCP calls, sesiones
3. **Kubernetes Metrics**: CPU/RAM por pod, network egress, pod events, policy denies
4. **Governance Events**: gate violations, blocked egress, unauthorized MCP access

## Stack

| Componente | Herramienta | Función |
|-----------|-------------|---------|
| Métricas | Prometheus + Grafana | CPU, RAM, tokens, dashboards |
| Logs | Loki | Workspace logs, Claude sessions |
| Audit trail | Coder built-in + PostgreSQL | User actions |
| Alertas | Grafana Alerting | Cost anomalies, violations |
| Dashboards | Grafana | Usage por rol, cost, adoption |

## KPIs del Piloto

| Métrica | Meta |
|---------|------|
| workspace_active_count | Track adoption |
| claude_tokens_total por user/día | < budget cap |
| governance_gate_violations | → 0 |
| network_policy_denied_total | Detect misuse |
| workspace_cost_usd per user/día | A definir en semana 8 post-baseline |

## Audit Trail — Retención

| Evento | Retención |
|--------|-----------|
| Login, workspace start | 1 año |
| Claude sessions | 90 días |
| Governance violations | 1 año |
| Network denies | 30 días |