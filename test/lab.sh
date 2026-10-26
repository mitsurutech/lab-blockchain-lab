#!/usr/bin/env bash
# What compose.yaml's header promises, checked from inside the lab's own network and through
# docker exec, which is how the platform's terminal reaches the lab's Python: run by check.sh.
set -euo pipefail
: "${NET:?run through test/check.sh}"
: "${CID:?run through test/check.sh}"
probe() { docker run --rm --network "$NET" lab-check-probe bash -c "$1"; }
run() { docker exec "$CID" "$@"; }
# Every step is the same each time (SHA-256 of fixed text), so the output is held exactly.
expect() { # expect <name> <text that must be a line of the output>...
  local out; out=$(run python3 "steps/$1.py"); shift
  for want in "$@"; do
    echo "$out" | grep -Fxq -- "$want" || { echo "missing '$want' in: $out" >&2; exit 1; }
  done
}

echo "- JupyterLab answers with no token to type"
probe '
set -eu
code=$(curl -s -o /dev/null -w "%{http_code}" http://jupyter:8888/lab)
[ "$code" = 200 ] || { echo "JupyterLab answered $code" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "start.ipynb" || { echo "no start.ipynb" >&2; exit 1; }
curl -fs -H "Host: someone-8888.example.com" -H "Origin: https://someone-8888.example.com" \
  http://jupyter:8888/api/kernelspecs | grep -q python3 || { echo "a proxied host is refused" >&2; exit 1; }
echo "- no way out to the internet"
if curl -s -m 4 -o /dev/null https://example.com; then echo "the lab reached the internet" >&2; exit 1; fi
'

echo "- the work folder holds the modules, the notebook and the step scripts"
run ls chain.py ledger.py lamport.py start.ipynb steps/link.py steps/tamper.py steps/mine.py \
  steps/balances.py steps/sign.py steps/fork.py >/dev/null

echo "- link.py: three blocks, each holding the hash of the one before"
expect link \
  "block 0 previous 0000000000 hash 000e13dc51" \
  "block 1 previous 000e13dc51 hash 0007118fa7" \
  "block 2 previous 0007118fa7 hash 000c5aaf76" \
  "each block holds the hash of the one before it"

echo "- tamper.py: changing a block breaks the chain, faking its hash does not help, re-mining breaks the next"
expect tamper \
  "before: (True, None)" \
  "after changing one amount in block 1: (False, 1)" \
  "after also faking block 1's hash: (False, 1)" \
  "after mining block 1 again: (False, 2)"

echo "- mine.py: 15, 835, 7992 and 109028 tries for difficulty 1 to 4"
expect mine \
  "difficulty 1 nonce 14 tries 15 hash 053b25815c28" \
  "difficulty 2 nonce 834 tries 835 hash 007f84c997a5" \
  "difficulty 3 nonce 7991 tries 7992 hash 00099b1fa581" \
  "difficulty 4 nonce 109027 tries 109028 hash 0000a629fed9"

echo "- balances.py: Asha 6, Ben 0, Cara 9, and Cara's payment of 8 refused"
expect balances \
  "balances: {'Asha': 6, 'Ben': 0, 'Cara': 9}" \
  "refused: Cara to Asha 8"

echo "- sign.py: the signature checks out, and fails when one letter changes"
expect sign \
  "public key holds 256 pairs of hashes" \
  "signature holds 256 revealed secrets" \
  "signed message checks out: True" \
  "one letter changed checks out: False"

echo "- fork.py: the longer chain has more work (768 against 1024) and wins"
expect fork \
  "both chains valid: True True" \
  "chain A blocks: 3 work: 768" \
  "chain B blocks: 4 work: 1024" \
  "the chain with more work wins: B" \
  "same last block in both? False"

echo "- the starter notebook runs from top to bottom inside the memory limit"
run jupyter nbconvert --to notebook --execute start.ipynb --output /tmp/ran.ipynb >/dev/null 2>&1 \
  || { echo "start.ipynb does not run" >&2; exit 1; }
echo "  ok"
