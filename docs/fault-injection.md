# Fault Injection Plan

This challenge requires: "Create a fault in the application/underlying
infrastructure that creates violation of the metrics you are monitoring"
and then demonstrate in Datadog that the fault was detected.

Two fault scenarios are provided. **Use the primary one for the live demo.**
The secondary one is a bonus if time allows and is more thematically on
point (it breaks the actual private-connectivity mechanism this challenge
is about), but its detection signal is less deterministic — see the caveat
below.

## Primary fault: scale `ledgerwriter` to 0 replicas (C2)

**Scripts:** `scripts/fault-inject-scale-ledgerwriter.sh` /
`scripts/fault-restore-scale-ledgerwriter.sh`

```bash
./scripts/fault-inject-scale-ledgerwriter.sh
```

This runs `kubectl --context c2 -n boa scale deployment/ledgerwriter --replicas=0`.

**Why this is the primary fault:**
- It deterministically trips `datadog_monitor.ledgerwriter_unavailable`,
  which alerts on `kubernetes_state.deployment.replicas_available{kube_deployment:ledgerwriter,...} < 1`.
  There's no ambiguity about whether or when it fires — kube-state-metrics
  reports replica counts on a short, predictable interval.
- It's fast to trigger and fast to reverse (`--replicas=1`), which matters
  live in a demo.
- It produces a clean, layered story across the whole stack you built:
  1. **Kubernetes layer:** `ledgerwriter` deployment shows 0/0 available
     replicas (`kubectl get deploy -n boa` on C2, or the Datadog
     Kubernetes/Live Containers view).
  2. **Network layer:** the C2 internal NLB fronting `ledgerwriter` now has
     zero healthy targets (visible in the AWS Console, and reflected by
     `datadog_monitor.ledgerwriter_nlb_unhealthy` if that monitor's tag
     naming matches your account — see the confidence note in
     `infra/datadog/monitors.tf`).
  3. **Application layer:** the C1 `frontend`, calling across the peering
     connection to C2's `ledgerwriter`, starts failing transaction
     submissions. This shows up as elevated error-level log volume from
     `frontend`, which is what `datadog_monitor.frontend_error_log_spike`
     watches.
  4. **User-facing layer:** if you drive traffic through the ALB URL during
     the fault window (manually, or via the `loadgenerator` already running
     in C1), you can show a real failed transaction in the browser at the
     same time the monitors go red.

**Demo sequence:**
1. Show the app working normally (submit a transaction via the frontend
   URL, show it succeed).
2. Show the Datadog dashboard / monitor list in a steady, all-green state.
3. Run `fault-inject-scale-ledgerwriter.sh`.
4. Within roughly 1-2 monitor evaluation cycles, show
   `ledgerwriter_unavailable` transition to Alert in Datadog, and point out
   the dashboard's replica-availability widget dropping to 0.
5. Attempt a transaction in the UI, show it fail.
6. Run `fault-restore-scale-ledgerwriter.sh`, show the monitor recover and
   the UI transaction succeed again.

## Secondary / bonus fault: revoke the C1→C2 security group rule

**Scripts:** `scripts/fault-inject-block-c2-sg.sh` /
`scripts/fault-restore-block-c2-sg.sh`

```bash
./scripts/fault-inject-block-c2-sg.sh
```

This runs `aws ec2 revoke-security-group-ingress` against the C2 node
security group, removing the rule (created by `infra/terraform/modules/peering`)
that permits inbound TCP/8080 from C1's private subnet CIDRs. It targets the
security group ID from `terraform output c2_cluster_security_group_id`, so it
always revokes the exact rule Terraform created — nothing broader.

**Why this is secondary, not primary, despite being more on-theme:**
This fault breaks the private-connectivity path itself — directly hitting
the "secure private connectivity between C1 and C2" mechanism the whole
challenge is centered on, which makes for a great second act once the
primary fault has proven the monitoring works. But which Datadog signal
fires first, and how cleanly, depends on infrastructure specifics that
weren't verified against live AWS/Datadog from this build environment:

- Traffic from C1 to C2 is denied at the security-group layer before it
  ever reaches the `ledgerwriter` pod. `kube-state-metrics` will keep
  reporting `ledgerwriter` as healthy (1/1 replicas) throughout, so
  `ledgerwriter_unavailable` will **not** fire for this fault — that's
  expected, not a bug.
- The intended signal is `frontend_error_log_spike` (the frontend's
  outbound calls to `ledgerwriter` start timing out / erroring) and
  potentially `ledgerwriter_nlb_unhealthy`, depending on whether the NLB's
  health check path also flows through the affected security group or a
  separate one AWS Load Balancer Controller manages for it. That detail
  couldn't be confirmed live from the sandbox this was built in.

**Recommendation:** run this once, before the actual demo, to see which
monitor(s) it trips and how fast, then decide whether to include it. If it
works cleanly, it's a strong "we broke the exact thing this challenge is
about, and caught it" moment. If the NLB health-check timing is slow or the
log-spike threshold doesn't trip within your demo window, fall back to
narrating it live ("here's the mechanism, here's why detection depends on
X") rather than depending on it to fire on cue.

```bash
./scripts/fault-restore-block-c2-sg.sh
```

Re-authorizes the same rule. (`terraform apply` also fixes this via drift
detection, but the restore script is faster mid-demo.)

## Choosing what to show live

Given the 24-hour constraint, the recommended plan is:
1. Rehearse the primary fault once, end to end, before the live demo, to
   confirm timing (how long until the monitor alerts) and take a screenshot
   of the triggered state as a fallback in case live timing is tight.
2. If time allows, rehearse the secondary fault once to see what it
   actually trips, and decide whether to include it live or only describe
   it in the write-up.
3. Always restore both faults after rehearsal so the environment is clean
   for the actual demo.
</content>
</invoke>
