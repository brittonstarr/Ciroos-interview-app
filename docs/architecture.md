# Architecture

This document is the visual companion to `architecture-design.md` (design
rationale and trade-offs) and the root `README.md` (deploy steps). Diagrams
are Mermaid so they render natively on GitHub and stay text-diffable as the
design evolves.

## 1. Network topology

Two independent VPCs in two regions, connected by cross-region VPC Peering,
each running one EKS cluster. Only C1 has a public-facing edge (ALB + WAF);
C2 is never reachable from the internet.

```mermaid
flowchart TB
    Internet((Internet))

    subgraph C1["C1 — us-east-1 — VPC 10.10.0.0/16"]
        direction TB
        WAF["AWS WAFv2\n(managed rules + rate limit)"]
        ALB["Application Load Balancer\n(internet-facing, public subnets)"]
        subgraph C1Priv["Private subnets"]
            EKS1["EKS Cluster C1\nfrontend, userservice,\ncontacts, accounts-db,\nloadgenerator"]
        end
        NAT1["NAT Gateway\n(public subnet)"]
    end

    subgraph C2["C2 — us-west-2 — VPC 10.20.0.0/16"]
        direction TB
        subgraph C2Priv["Private subnets"]
            EKS2["EKS Cluster C2\nledgerwriter, balancereader,\ntransactionhistory, ledger-db"]
            NLB["Internal NLBs\n(ledgerwriter, balancereader,\ntransactionhistory)"]
        end
        NAT2["NAT Gateway\n(public subnet, egress-only)"]
    end

    Peering[["VPC Peering\n(cross-region)"]]

    Internet -->|HTTPS| WAF --> ALB --> EKS1
    EKS1 -->|"private: TCP/8080\nC1 subnet CIDRs only"| Peering
    Peering --> NLB --> EKS2
    EKS1 -.->|egress only| NAT1 -.-> Internet
    EKS2 -.->|egress only| NAT2 -.-> Internet

    style C2 fill:#f5f5f5
    style Internet fill:#fff,stroke:#999
```

**Key properties:**
- C1's public subnets host only the ALB and NAT Gateway — no pods run there.
- C2 has **no internet-facing load balancer at all**; its public subnets
  exist solely so its NAT Gateway can provide egress (image pulls, DNS,
  AWS API calls) — inbound is never possible through them.
- The only path between the two VPCs is the peering connection, and the
  only traffic permitted over it is TCP/8080 from C1's private-subnet
  CIDRs to C2's EKS node security group (see §3).
- EKS API endpoints are currently reachable from `0.0.0.0/0` for build-time
  convenience (documented trade-off in `architecture-design.md` §6); this
  is `kubectl`-to-control-plane access, not application traffic, and is a
  named follow-up to restrict before treating this as production-grade.

## 2. Application service graph (Bank of Anthos, split across clusters)

```mermaid
flowchart LR
    User((End user)) -->|HTTPS| ALB

    subgraph C1["C1 (identity / UI tier)"]
        ALB --> frontend
        frontend --> userservice
        frontend --> contacts
        userservice --> accountsdb[(accounts-db)]
        contacts --> accountsdb
        loadgen["loadgenerator"] -.synthetic traffic.-> frontend
    end

    subgraph C2["C2 (ledger tier)"]
        ledgerwriter
        balancereader
        transactionhistory
        ledgerwriter --> ledgerdb[(ledger-db)]
        balancereader --> ledgerdb
        transactionhistory --> ledgerdb
    end

    frontend -->|"POST /payment\n(private, cross-region)"| ledgerwriter
    frontend -->|"GET /balance\n(private, cross-region)"| balancereader
    frontend -->|"GET /history\n(private, cross-region)"| transactionhistory

    style C1 fill:#eef6ff
    style C2 fill:#fff5ee
```

**Split rationale (full detail in `architecture-design.md` §2):** the
identity/UI tier (frontend, userservice, contacts, accounts-db) runs in C1
alongside the public entry point; the ledger tier (ledgerwriter,
balancereader, transactionhistory, ledger-db) runs in C2. This gives a
clean, single-direction C1→C2 dependency that maps directly onto the
challenge's "service in C1 must communicate with a specific service in C2"
requirement, with three real, independently-testable request/response
paths rather than one.

## 3. C1 → C2 request path, layer by layer

```mermaid
sequenceDiagram
    participant U as End user
    participant WAF as WAFv2
    participant ALB as ALB (C1)
    participant FE as frontend (C1)
    participant PC as VPC Peering
    participant SG as C2 node SG\n(port 8080, C1 CIDRs only)
    participant NLB as Internal NLB (C2)
    participant LW as ledgerwriter (C2)

    U->>WAF: HTTPS request
    WAF->>ALB: allowed (managed rules + rate limit pass)
    ALB->>FE: forward to pod (target-type ip)
    FE->>PC: TCP/8080 to ledgerwriter's NLB DNS name
    PC->>SG: cross-region, private IP space only
    SG->>NLB: permitted (source CIDR + port match)
    NLB->>LW: health-checked target
    LW-->>FE: response (JSON)
    FE-->>U: rendered page
```

Every hop after the ALB stays on private IP space — no segment of the
C1→C2 path traverses the public internet. NetworkPolicy (applied inside
each cluster) narrows this further at the pod level: C2's default-deny
policy only admits traffic on port 8080 from C1's subnet CIDRs into the
ledger-tier pods specifically, and only the ledger-tier pods may reach
`ledger-db`.

## 4. Observability data flow

```mermaid
flowchart LR
    subgraph C1["C1 cluster"]
        A1["Datadog Agent\n(DaemonSet)"]
    end
    subgraph C2["C2 cluster"]
        A2["Datadog Agent\n(DaemonSet)"]
    end
    AWS["AWS integration\n(cross-account IAM role)\nCloudWatch metrics: ALB, NLB, NAT, VPC"]

    A1 -->|logs, container/kube-state metrics,\nAPM, NPM| DD[(Datadog)]
    A2 -->|logs, container/kube-state metrics,\nAPM, NPM| DD
    AWS -->|infra metrics| DD

    DD --> Dash["Dashboard\n(infra/datadog/dashboard.tf)"]
    DD --> Mon["Monitors\n(infra/datadog/monitors.tf)"]
    Mon -->|alert| Notify["Demo: shown live\nduring fault injection"]
```

See `docs/fault-injection.md` for how the monitored metrics are
deliberately violated and detected.

## Where each diagram's source of truth lives

| Diagram | Backed by |
|---|---|
| §1 Network topology | `infra/terraform/modules/network`, `modules/eks`, `modules/peering`, `modules/waf` |
| §2 Service graph | `k8s/c1/`, `k8s/c2/` |
| §3 Request path | `k8s/c1/07-frontend.yaml`, `modules/peering`, `k8s/c2/07-networkpolicy.yaml` |
| §4 Observability | `k8s/addons/datadog-values.yaml`, `infra/datadog/` |
</content>
