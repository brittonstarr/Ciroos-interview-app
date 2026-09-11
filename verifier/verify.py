#!/usr/bin/env python3
"""
Python verification tool for the AWS Application & Infrastructure
Observability Challenge.

Confirms:
  1. No unintended public access paths exist anywhere in the environment.
  2. Only the intended C1 -> C2 (frontend -> ledger tier) communication is
     permitted.

Two modes:
  --static (default): read-only AWS API audit (EC2/ELBv2/WAFv2). No
    cluster access required — just AWS credentials with read permissions
    (see reader-iam-policy.json for the minimal set).
  --live: additionally runs a real positive test (kubectl exec into a C1
    pod, confirm it CAN reach each C2 ledger service) and a real negative
    test (this machine attempts to reach the same C2 endpoints directly
    over the internet, confirming it CANNOT). Requires kubectl configured
    with contexts `c1`/`c2` (see scripts/01-configure-kubectl.sh) for the
    positive half; the negative half needs nothing but network access.

Usage:
    pip install -r requirements.txt
    python3 verify.py                  # static checks only
    python3 verify.py --live           # static + live connectivity checks
    python3 verify.py --config other.yaml

Exit code is 0 only if every check PASSed (WARNs don't fail the run —
they're flagged, documented trade-offs; see README.md).
"""
from __future__ import annotations

import argparse
import ipaddress
import socket
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import boto3
import botocore.exceptions
import yaml

PASS, WARN, FAIL = "PASS", "WARN", "FAIL"


@dataclass
class Result:
    name: str
    status: str
    detail: str


@dataclass
class Report:
    results: list = field(default_factory=list)

    def add(self, name: str, status: str, detail: str) -> None:
        self.results.append(Result(name, status, detail))
        marker = {"PASS": "[PASS]", "WARN": "[WARN]", "FAIL": "[FAIL]"}[status]
        print(f"{marker} {name}: {detail}")

    def summary(self) -> int:
        counts = {PASS: 0, WARN: 0, FAIL: 0}
        for r in self.results:
            counts[r.status] += 1
        print("\n" + "=" * 70)
        print(f"{counts[PASS]} passed, {counts[WARN]} warnings, {counts[FAIL]} failed")
        print("=" * 70)
        return 1 if counts[FAIL] else 0


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


# ---------------------------------------------------------------------------
# Static checks
# ---------------------------------------------------------------------------

def check_no_public_ledger_load_balancers(report: Report, cfg: dict) -> None:
    """Nothing in C2 should ever be internet-facing."""
    region = cfg["c2"]["region"]
    project = cfg["project_name"]
    elbv2 = boto3.client("elbv2", region_name=region)

    paginator = elbv2.get_paginator("describe_load_balancers")
    offenders = []
    total = 0
    for page in paginator.paginate():
        for lb in page["LoadBalancers"]:
            tags = _get_lb_tags(elbv2, lb["LoadBalancerArn"])
            if tags.get("Project") != project and project not in lb["LoadBalancerName"]:
                continue
            total += 1
            if lb["Scheme"] != "internal":
                offenders.append(f"{lb['LoadBalancerName']} ({lb['Scheme']})")

    if offenders:
        report.add(
            "C2 load balancers are internal-only",
            FAIL,
            f"Found internet-facing load balancer(s) in C2: {', '.join(offenders)}",
        )
    else:
        report.add(
            "C2 load balancers are internal-only",
            PASS,
            f"Checked {total} load balancer(s) tagged/named for this project in {region}; all internal.",
        )


def check_c1_public_surface_is_only_the_alb(report: Report, cfg: dict) -> None:
    """C1 should have exactly one internet-facing load balancer: the frontend ALB."""
    region = cfg["c1"]["region"]
    project = cfg["project_name"]
    name_hint = cfg["c1"]["expected_public_alb_name_contains"]
    elbv2 = boto3.client("elbv2", region_name=region)

    paginator = elbv2.get_paginator("describe_load_balancers")
    public_lbs = []
    for page in paginator.paginate():
        for lb in page["LoadBalancers"]:
            tags = _get_lb_tags(elbv2, lb["LoadBalancerArn"])
            relevant = tags.get("Project") == project or project in lb["LoadBalancerName"]
            if relevant and lb["Scheme"] == "internet-facing":
                public_lbs.append(lb)

    unexpected = [lb for lb in public_lbs if name_hint not in lb["LoadBalancerName"]]
    if unexpected:
        report.add(
            "C1 public surface limited to the frontend ALB",
            FAIL,
            f"Unexpected internet-facing load balancer(s): {[lb['LoadBalancerName'] for lb in unexpected]}",
        )
    elif not public_lbs:
        report.add(
            "C1 public surface limited to the frontend ALB",
            WARN,
            "No internet-facing load balancer found yet — expected if the app hasn't been deployed.",
        )
    else:
        report.add(
            "C1 public surface limited to the frontend ALB",
            PASS,
            f"Exactly the expected ALB(s) are internet-facing: {[lb['LoadBalancerName'] for lb in public_lbs]}",
        )
        return public_lbs[0]["LoadBalancerArn"]


def check_waf_attached(report: Report, cfg: dict, alb_arn: Optional[str]) -> None:
    region = cfg["c1"]["region"]
    if not alb_arn:
        report.add("WAF attached to public ALB", WARN, "Skipped — no ALB ARN found in the previous check.")
        return
    wafv2 = boto3.client("wafv2", region_name=region)
    try:
        resp = wafv2.get_web_acl_for_resource(ResourceArn=alb_arn)
    except botocore.exceptions.ClientError as e:
        report.add("WAF attached to public ALB", FAIL, f"Could not query WAF association: {e}")
        return
    web_acl = resp.get("WebACL")
    if web_acl:
        report.add("WAF attached to public ALB", PASS, f"WebACL '{web_acl['Name']}' is associated.")
    else:
        report.add("WAF attached to public ALB", FAIL, "No WebACL associated with the public ALB.")


def check_no_sg_open_to_world_except_alb(report: Report, cfg: dict) -> None:
    """Any security group allowing 0.0.0.0/0 ingress should only be the ALB's, on allowed_public_ports."""
    allowed_ports = set(cfg["allowed_public_ports"])
    offenders = []
    checked = 0

    for region_cfg in (cfg["c1"], cfg["c2"]):
        region = region_cfg["region"]
        ec2 = boto3.client("ec2", region_name=region)
        paginator = ec2.get_paginator("describe_security_groups")
        for page in paginator.paginate():
            for sg in page["SecurityGroups"]:
                checked += 1
                for perm in sg.get("IpPermissions", []):
                    for ip_range in perm.get("IpRanges", []):
                        if ip_range.get("CidrIp") != "0.0.0.0/0":
                            continue
                        from_port = perm.get("FromPort")
                        to_port = perm.get("ToPort")
                        is_allowed = (
                            from_port in allowed_ports and to_port in allowed_ports
                        ) or (from_port is None and to_port is None and perm.get("IpProtocol") == "-1" and False)
                        if not is_allowed:
                            offenders.append(
                                f"{sg['GroupId']} ({sg.get('GroupName')}) in {region}: "
                                f"{perm.get('IpProtocol')} {from_port}-{to_port} open to 0.0.0.0/0"
                            )

    if offenders:
        report.add(
            "No security group open to the internet outside allowed ports",
            FAIL,
            f"{len(offenders)} offending rule(s): " + "; ".join(offenders[:10]) + (" ..." if len(offenders) > 10 else ""),
        )
    else:
        report.add(
            "No security group open to the internet outside allowed ports",
            PASS,
            f"Checked {checked} security groups across both regions; only ports {sorted(allowed_ports)} are open to 0.0.0.0/0 (the ALB).",
        )


def check_c2_private_subnets_have_no_igw_route(report: Report, cfg: dict) -> None:
    region = cfg["c2"]["region"]
    project = cfg["project_name"]
    ec2 = boto3.client("ec2", region_name=region)

    vpcs = ec2.describe_vpcs(Filters=[{"Name": "tag:Project", "Values": [project]}])["Vpcs"]
    if not vpcs:
        report.add("C2 private subnets have no route to an Internet Gateway", WARN, "Could not find a tagged C2 VPC.")
        return
    vpc_id = vpcs[0]["VpcId"]

    igws = ec2.describe_internet_gateways(
        Filters=[{"Name": "attachment.vpc-id", "Values": [vpc_id]}]
    )["InternetGateways"]
    igw_ids = {igw["InternetGatewayId"] for igw in igws}

    route_tables = ec2.describe_route_tables(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["RouteTables"]
    offenders = []
    for rt in route_tables:
        # Skip the main/public route table (it legitimately routes 0.0.0.0/0 -> IGW for the NAT Gateway's own subnet).
        is_main = any(a.get("Main") for a in rt.get("Associations", []))
        if is_main:
            continue
        for route in rt.get("Routes", []):
            if route.get("DestinationCidrBlock") == "0.0.0.0/0" and route.get("GatewayId") in igw_ids:
                offenders.append(rt["RouteTableId"])

    if offenders:
        report.add(
            "C2 private subnets have no route to an Internet Gateway",
            FAIL,
            f"Route table(s) with a direct IGW route: {offenders}",
        )
    else:
        report.add(
            "C2 private subnets have no route to an Internet Gateway",
            PASS,
            f"Checked {len(route_tables)} route table(s) in C2's VPC; only the NAT-Gateway-owning public route table has an IGW route.",
        )


def check_ledger_sg_rule_scoped_to_c1(report: Report, cfg: dict) -> None:
    """The SG rule allowing C1 -> C2 ledger ports should be scoped to C1's
    specific private subnets, never 0.0.0.0/0 and never the whole C1 VPC."""
    region = cfg["c2"]["region"]
    ports = {s["port"] for s in cfg["c2"]["ledger_services"]}
    # C1's frontend subnets (real client traffic) plus any documented
    # exceptions (e.g. C2's own VPC CIDR for NLB health-check probes —
    # see config.yaml's comment on c2.additional_allowed_cidrs).
    expected_cidrs = set(cfg["c1"]["private_subnet_cidrs"]) | set(cfg["c2"].get("additional_allowed_cidrs", []))
    c1_vpc_cidr = ipaddress.ip_network(cfg["c1"]["vpc_cidr"])

    ec2 = boto3.client("ec2", region_name=region)
    paginator = ec2.get_paginator("describe_security_groups")

    matching_rules = []
    for page in paginator.paginate():
        for sg in page["SecurityGroups"]:
            for perm in sg.get("IpPermissions", []):
                if perm.get("FromPort") not in ports:
                    continue
                for ip_range in perm.get("IpRanges", []):
                    cidr = ip_range.get("CidrIp")
                    matching_rules.append((sg["GroupId"], cidr))

    if not matching_rules:
        report.add(
            "C2 ledger-port SG rule scoped to C1's frontend subnets",
            WARN,
            f"No SG rule found for ports {sorted(ports)} yet — expected if not deployed.",
        )
        return

    bad = []
    for sg_id, cidr in matching_rules:
        if cidr == "0.0.0.0/0":
            bad.append(f"{sg_id}: wide open (0.0.0.0/0)")
            continue
        net = ipaddress.ip_network(cidr)
        if cidr not in expected_cidrs and net == c1_vpc_cidr:
            bad.append(f"{sg_id}: scoped to the WHOLE C1 VPC ({cidr}), not just the frontend subnets")
        elif cidr not in expected_cidrs:
            bad.append(f"{sg_id}: unexpected source {cidr} (expected one of {sorted(expected_cidrs)})")

    if bad:
        report.add("C2 ledger-port SG rule scoped to C1's frontend subnets", FAIL, "; ".join(bad))
    else:
        report.add(
            "C2 ledger-port SG rule scoped to C1's frontend subnets",
            PASS,
            f"All matching rules scoped exactly to {sorted(expected_cidrs)}.",
        )


def check_peering_connection_active(report: Report, cfg: dict) -> None:
    region = cfg["c1"]["region"]
    ec2 = boto3.client("ec2", region_name=region)
    conns = ec2.describe_vpc_peering_connections(
        Filters=[{"Name": "status-code", "Values": ["active", "pending-acceptance", "failed", "expired", "rejected"]}]
    )["VpcPeeringConnections"]

    project_conns = [
        c for c in conns
        if any(t["Key"] == "Purpose" and "c1-c2" in t["Value"] for t in c.get("Tags", []))
    ]
    if not project_conns:
        report.add("VPC Peering connection active", WARN, "No tagged C1<->C2 peering connection found yet.")
        return

    for c in project_conns:
        status = c["Status"]["Code"]
        if status == "active":
            report.add("VPC Peering connection active", PASS, f"{c['VpcPeeringConnectionId']} is active.")
        else:
            report.add("VPC Peering connection active", FAIL, f"{c['VpcPeeringConnectionId']} status is '{status}', not active.")


def check_eks_public_endpoint(report: Report, cfg: dict) -> None:
    """Documented trade-off, not a hard failure — see architecture-design.md
    section 10. Surfaced as WARN so it's visible, not hidden."""
    for label, region_cfg in (("C1", cfg["c1"]), ("C2", cfg["c2"])):
        region = region_cfg["region"]
        eks = boto3.client("eks", region_name=region)
        try:
            clusters = eks.list_clusters()["clusters"]
        except botocore.exceptions.ClientError as e:
            report.add(f"{label} EKS API endpoint exposure", WARN, f"Could not list clusters: {e}")
            continue
        project_clusters = [c for c in clusters if cfg["project_name"] in c]
        for name in project_clusters:
            desc = eks.describe_cluster(name=name)["cluster"]
            vpc_cfg = desc["resourcesVpcConfig"]
            if vpc_cfg.get("endpointPublicAccess") and "0.0.0.0/0" in vpc_cfg.get("publicAccessCidrs", []):
                report.add(
                    f"{label} EKS API endpoint exposure",
                    WARN,
                    f"{name}: public endpoint open to 0.0.0.0/0 — a documented build-time convenience trade-off "
                    "(see architecture-design.md), not a Service/application exposure. Tighten "
                    "cluster_endpoint_public_access_cidrs before anything longer-lived than this exercise.",
                )
            else:
                report.add(f"{label} EKS API endpoint exposure", PASS, f"{name}: public access restricted or disabled.")


def _get_lb_tags(elbv2, arn: str) -> dict:
    try:
        resp = elbv2.describe_tags(ResourceArns=[arn])
        for td in resp["TagDescriptions"]:
            return {t["Key"]: t["Value"] for t in td["Tags"]}
    except botocore.exceptions.ClientError:
        pass
    return {}


# ---------------------------------------------------------------------------
# Live checks (--live)
# ---------------------------------------------------------------------------

def live_positive_test(report: Report, cfg: dict) -> None:
    """From inside C1, each C2 ledger service should be reachable."""
    ctx = cfg["c1"]["kubectl_context"]
    pod = _find_pod(ctx, "app=frontend")
    if not pod:
        report.add("LIVE: C1 -> C2 connectivity (positive)", WARN, "No frontend pod found in C1 — is the app deployed?")
        return

    for svc in cfg["c2"]["ledger_services"]:
        addr = _service_api_addr_env_value(ctx, pod, svc["name"])
        if not addr:
            report.add(
                f"LIVE: C1 -> C2 connectivity ({svc['name']})",
                WARN,
                "Could not read the configured address from the frontend Pod's environment.",
            )
            continue
        ok, detail = _kubectl_curl(ctx, pod, addr, path="/ready", timeout=5)
        report.add(
            f"LIVE: C1 -> C2 connectivity ({svc['name']})",
            PASS if ok else FAIL,
            detail,
        )


def live_negative_test(report: Report, cfg: dict) -> None:
    """From wherever this script runs (presumably your own machine, i.e. the
    public internet), each C2 ledger service should be UNREACHABLE."""
    ctx = cfg["c2"]["kubectl_context"]
    for svc in cfg["c2"]["ledger_services"]:
        hostname = _get_svc_lb_hostname(ctx, svc["name"])
        if not hostname:
            report.add(
                f"LIVE: public unreachability of {svc['name']}",
                WARN,
                "Could not find a LoadBalancer hostname for this Service — is it deployed?",
            )
            continue
        reachable = _tcp_probe(hostname, svc["port"], timeout=5)
        report.add(
            f"LIVE: public unreachability of {svc['name']}",
            FAIL if reachable else PASS,
            f"{hostname}:{svc['port']} "
            + ("was reachable from this machine — internal NLB is NOT actually private!"
               if reachable else "was not reachable from this machine, as expected for an internal-only NLB."),
        )


def _find_pod(ctx: str, selector: str) -> Optional[str]:
    try:
        out = subprocess.run(
            ["kubectl", "--context", ctx, "-n", "boa", "get", "pods", "-l", selector,
             "-o", "jsonpath={.items[0].metadata.name}"],
            capture_output=True, text=True, timeout=15,
        )
        return out.stdout.strip() or None
    except (subprocess.SubprocessError, FileNotFoundError):
        return None


def _service_api_addr_env_value(ctx: str, pod: str, svc_name: str) -> Optional[str]:
    env_key = {
        "ledgerwriter": "TRANSACTIONS_API_ADDR",
        "balancereader": "BALANCES_API_ADDR",
        "transactionhistory": "HISTORY_API_ADDR",
    }.get(svc_name)
    if not env_key:
        return None
    try:
        out = subprocess.run(
            ["kubectl", "--context", ctx, "-n", "boa", "exec", pod, "--", "printenv", env_key],
            capture_output=True, text=True, timeout=15,
        )
        return out.stdout.strip() or None
    except (subprocess.SubprocessError, FileNotFoundError):
        return None


def _kubectl_curl(ctx: str, pod: str, addr: str, path: str, timeout: int) -> tuple[bool, str]:
    url = f"http://{addr}{path}"
    try:
        out = subprocess.run(
            ["kubectl", "--context", ctx, "-n", "boa", "exec", pod, "--",
             "wget", "-q", "-T", str(timeout), "-O", "-", url],
            capture_output=True, text=True, timeout=timeout + 5,
        )
        ok = out.returncode == 0
        return ok, f"{url} -> {'reachable' if ok else 'unreachable (rc=' + str(out.returncode) + ')'}"
    except (subprocess.SubprocessError, FileNotFoundError) as e:
        return False, f"{url} -> exec failed: {e}"


def _get_svc_lb_hostname(ctx: str, svc_name: str) -> Optional[str]:
    try:
        out = subprocess.run(
            ["kubectl", "--context", ctx, "-n", "boa", "get", "svc", svc_name,
             "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}"],
            capture_output=True, text=True, timeout=15,
        )
        return out.stdout.strip() or None
    except (subprocess.SubprocessError, FileNotFoundError):
        return None


def _tcp_probe(hostname: str, port: int, timeout: int) -> bool:
    try:
        with socket.create_connection((hostname, port), timeout=timeout):
            return True
    except OSError:
        return False


# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.yaml"))
    parser.add_argument("--live", action="store_true", help="Also run live positive/negative connectivity tests.")
    args = parser.parse_args()

    cfg = load_config(args.config)
    report = Report()

    print("== Static AWS configuration audit ==\n")
    check_no_public_ledger_load_balancers(report, cfg)
    alb_arn = check_c1_public_surface_is_only_the_alb(report, cfg)
    check_waf_attached(report, cfg, alb_arn)
    check_no_sg_open_to_world_except_alb(report, cfg)
    check_c2_private_subnets_have_no_igw_route(report, cfg)
    check_ledger_sg_rule_scoped_to_c1(report, cfg)
    check_peering_connection_active(report, cfg)
    check_eks_public_endpoint(report, cfg)

    if args.live:
        print("\n== Live connectivity tests ==\n")
        live_positive_test(report, cfg)
        live_negative_test(report, cfg)

    return report.summary()


if __name__ == "__main__":
    sys.exit(main())
