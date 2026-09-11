#!/usr/bin/env bash
# Generates a FRESH RSA keypair for JWT signing and creates the `jwt-key`
# Secret directly in both clusters via kubectl — it is deliberately never
# written to a committed manifest or to disk outside a throwaway temp dir.
#
# Why a fresh keypair matters: the upstream Bank of Anthos repo ships a
# demo `extras/jwt/jwt-secret.yaml` with a *publicly known* private key —
# fine for a five-minute local demo, but using a checked-in-on-GitHub
# private key as your actual auth signing key in a deployed environment is
# a real, meaningful vulnerability, not a hypothetical one. Generating a
# fresh key here removes that specific finding entirely.
#
# C1 gets the full keypair (userservice signs JWTs here).
# C2 gets only the public key (the ledger-tier services only verify).
set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

openssl genrsa -out "$TMPDIR/jwtRS256.key" 4096 2>/dev/null
openssl rsa -in "$TMPDIR/jwtRS256.key" -pubout -out "$TMPDIR/jwtRS256.key.pub" 2>/dev/null

kubectl --context c1 create namespace boa --dry-run=client -o yaml | kubectl --context c1 apply -f -
kubectl --context c2 create namespace boa --dry-run=client -o yaml | kubectl --context c2 apply -f -

kubectl --context c1 -n boa create secret generic jwt-key \
  --from-file=jwtRS256.key="$TMPDIR/jwtRS256.key" \
  --from-file=jwtRS256.key.pub="$TMPDIR/jwtRS256.key.pub" \
  --dry-run=client -o yaml | kubectl --context c1 apply -f -

kubectl --context c2 -n boa create secret generic jwt-key \
  --from-file=jwtRS256.key.pub="$TMPDIR/jwtRS256.key.pub" \
  --dry-run=client -o yaml | kubectl --context c2 apply -f -

echo "jwt-key Secret created in both clusters (private key only in C1, public-key-only in C2)."
