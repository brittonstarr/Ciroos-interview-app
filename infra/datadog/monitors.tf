locals {
  c2_cluster = data.terraform_remote_state.infra.outputs.c2_cluster_name
  c1_cluster = data.terraform_remote_state.infra.outputs.c1_cluster_name
}

# --- PRIMARY monitor for the live fault demo --------------------------------
# Highest-confidence signal in this whole set: Kubernetes-state metrics from
# the Datadog Agent's built-in kube-state-metrics integration, no app
# changes or uncertain tag names required. Scaling ledgerwriter to 0 (the
# planned fault, see docs/write-up.md) trips this directly and reliably —
# this is the monitor to point at during the demo.
resource "datadog_monitor" "ledgerwriter_unavailable" {
  name    = "[boa-challenge] ledgerwriter has no available replicas (C1->C2 path down)"
  type    = "metric alert"
  message = <<-EOT
    ledgerwriter in ${local.c2_cluster} has 0 available replicas — the
    private C1->C2 connectivity path (frontend -> ledgerwriter) is down.
    This is expected during the fault-injection demo; otherwise page.
    @slack-boa-challenge-alerts
  EOT

  query = "max(last_5m):avg:kubernetes_state.deployment.replicas_available{kube_deployment:ledgerwriter,cluster_name:${local.c2_cluster}} < 1"

  monitor_thresholds {
    critical = 1
  }

  notify_no_data    = true
  no_data_timeframe = 10
  tags              = ["project:boa-challenge", "cluster:c2", "tier:ledger"]
}

# --- Supporting monitor: AWS NLB target health -------------------------------
# Ties the same fault directly to the "private connectivity" infrastructure
# layer (not just the app layer) via the Datadog AWS integration.
# CONFIDENCE NOTE: the tag key AWS integration metrics use for target group
# (target_group vs targetgroup) should be confirmed in Metrics Explorer once
# real data is flowing — left as `target_group` here, the more common form.
resource "datadog_monitor" "ledgerwriter_nlb_unhealthy" {
  name    = "[boa-challenge] ledgerwriter internal NLB has unhealthy targets"
  type    = "metric alert"
  message = "The internal NLB fronting ledgerwriter has unhealthy targets. @slack-boa-challenge-alerts"

  query = "max(last_5m):avg:aws.networkelb.un_healthy_host_count{target_group:*ledgerwriter*} > 0"

  monitor_thresholds {
    critical = 0
  }

  notify_no_data    = false
  tags              = ["project:boa-challenge", "cluster:c2", "tier:ledger"]
}

# --- Supporting monitor: application error logs -----------------------------
resource "datadog_monitor" "frontend_error_log_spike" {
  name    = "[boa-challenge] frontend error log spike"
  type    = "log alert"
  message = "frontend is logging errors faster than expected — likely a downstream (ledger-tier) failure. @slack-boa-challenge-alerts"

  query = "logs(\"service:frontend status:error\").index(\"*\").rollup(\"count\").last(\"5m\") > 20"

  monitor_thresholds {
    critical = 20
  }

  tags = ["project:boa-challenge", "cluster:c1", "tier:web"]
}

# --- Supporting monitor: node CPU (general infra health) --------------------
resource "datadog_monitor" "node_cpu_high" {
  name    = "[boa-challenge] node CPU high"
  type    = "metric alert"
  message = "A node is running hot. @slack-boa-challenge-alerts"

  query = "avg(last_10m):avg:system.cpu.user{project:boa-challenge} by {host} > 80"

  monitor_thresholds {
    critical = 80
    warning  = 65
  }

  tags = ["project:boa-challenge"]
}
