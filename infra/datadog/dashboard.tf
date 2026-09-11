# CONFIDENCE NOTE: a real `terraform plan` against this file only flagged
# the deprecated `is_read_only` argument (fixed below, see comment on the
# resource) — every widget block shape below (widget { <type>_definition
# { ... } }) validated clean against the live provider schema.
#
# One thing intentionally NOT here: a live network topology view of the
# C1->C2 traffic. That's Datadog's Cloud Network Monitoring "Network Map"
# (enabled via k8s/addons/datadog-values.yaml), which is a built-in
# Datadog page, not something built through datadog_dashboard — show that
# live during the demo from Network > Network Map instead of a screenshot
# baked into a dashboard widget.

resource "datadog_dashboard" "boa_challenge" {
  title       = "Bank of Anthos Challenge — C1/C2 Overview"
  description = "App + infra observability for the AWS EKS Application & Infrastructure Observability Challenge. Primary fault-demo signal: ledgerwriter replica availability."
  layout_type = "ordered"
  # `is_read_only` is deprecated/non-functional in current provider
  # versions (confirmed via the `terraform plan` warning) — omitted.
  # Everyone on this Datadog org can already edit; `restricted_roles`
  # would be the way to lock that down if needed later.

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
        q            = "avg:kubernetes_state.deployment.replicas_available{cluster:${local.c2_cluster}} by {kube_deployment}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Identity/UI-tier replica availability (C1)"
      request {
        q            = "avg:kubernetes_state.deployment.replicas_available{cluster:${local.c1_cluster}} by {kube_deployment}"
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
      query = "cluster:${local.c2_cluster}"
    }
  }
}
