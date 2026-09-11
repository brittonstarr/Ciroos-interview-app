# CONFIDENCE NOTE: same caveat as aws-integration.tf — this couldn't be
# `terraform validate`-checked from this sandbox. The general widget-block
# shape (widget { <type>_definition { ... } }) is stable across recent
# provider versions; if a specific nested attribute name has moved, it's a
# quick fix once you see the validate error.
#
# One thing intentionally NOT here: a live network topology view of the
# C1->C2 traffic. That's Datadog's Cloud Network Monitoring "Network Map"
# (enabled via k8s/addons/datadog-values.yaml), which is a built-in
# Datadog page, not something built through datadog_dashboard — show that
# live during the demo from Network > Network Map instead of a screenshot
# baked into a dashboard widget.

resource "datadog_dashboard" "boa_challenge" {
  title        = "Bank of Anthos Challenge — C1/C2 Overview"
  description  = "App + infra observability for the AWS EKS Application & Infrastructure Observability Challenge. Primary fault-demo signal: ledgerwriter replica availability."
  layout_type  = "ordered"
  is_read_only = false

  widget {
    note_definition {
      content          = "**C1 (us-east-1, identity/UI)** <-> VPC Peering <-> **C2 (us-west-2, ledger)**\n\nPrimary fault-demo monitor: *ledgerwriter has no available replicas*."
      background_color = "blue"
      font_size        = "16"
      text_align       = "left"
    }
  }

  widget {
    timeseries_definition {
      title = "Ledger-tier replica availability (C2)"
      request {
        q            = "avg:kubernetes_state.deployment.replicas_available{cluster_name:${local.c2_cluster}} by {kube_deployment}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Identity/UI-tier replica availability (C1)"
      request {
        q            = "avg:kubernetes_state.deployment.replicas_available{cluster_name:${local.c1_cluster}} by {kube_deployment}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "ledgerwriter internal NLB target health"
      request {
        q            = "avg:aws.networkelb.healthy_host_count{target_group:*ledgerwriter*}"
        display_type = "line"
      }
      request {
        q            = "avg:aws.networkelb.un_healthy_host_count{target_group:*ledgerwriter*}"
        display_type = "line"
      }
    }
  }

  widget {
    query_value_definition {
      title = "Container restarts (last 1h, both clusters)"
      request {
        q          = "sum:kubernetes_state.container.restarts{project:boa-challenge}.as_count()"
        aggregator = "sum"
      }
    }
  }

  widget {
    log_stream_definition {
      title = "Frontend errors"
      query = "service:frontend status:error"
    }
  }

  widget {
    log_stream_definition {
      title = "Ledger-tier logs (all services)"
      query = "cluster_name:${local.c2_cluster}"
    }
  }
}
