#!/usr/bin/env bash
# PRIMARY fault for the live demo: scale ledgerwriter to 0 replicas.
#
# Why this one is "the" demo fault and not the SG-based one below: it
# deterministically trips datadog_monitor.ledgerwriter_unavailable
# (kubernetes_state.deployment.replicas_available < 1) with no ambiguity —
# no dependency on exact AWS metric tag naming or NLB health-check routing
# nuances. See docs/fault-injection.md for the full narrative and the
# secondary (SG-based) option.
set -euo pipefail

kubectl --context c2 -n boa scale deployment/ledgerwriter --replicas=0
echo "ledgerwriter scaled to 0. The C1 -> C2 path is now broken."
echo "Watch: Datadog monitor 'ledgerwriter has no available replicas', the dashboard's"
echo "ledger-tier replica-availability widget, and frontend logs (transaction submission will start failing)."
