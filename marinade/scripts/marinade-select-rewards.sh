#!/usr/bin/env bash
set -euo pipefail

LPS=1000000000
API="https://institutional-staking.marinade.finance/v1"
VOTE="${1:-}"; FROM="${2:-}"; TO="${3:-}"
[[ -z "$VOTE" || -z "$FROM" || -z "$TO" ]] && { echo "Usage: $0 VOTE FROM_EPOCH TO_EPOCH"; exit 1; }

VALS_JSON="$(curl -sSf "$API/validators/epoch?from_epoch=$FROM&to_epoch=$TO")"
ROWS="$(jq --arg v "$VOTE" '[.[] | select(.vote_account == $v)]' <<<"$VALS_JSON")"

printf "\n%-8s │ %-12s │ %-12s │ %-12s │ %-12s │ %-12s │ %-12s\n" \
  "Epoch" "MNDE_tar" "VAL_tar" "POT" "MNDE_paid" "VAL_paid" "Stkr_bonds"
printf "%s\n" "────────────────────────────────────────────────────────────────────────────────────────────────────────────"

jq -c '.[]' <<<"$ROWS" | while read -r r; do
  epoch=$(jq -r '.epoch' <<<"$r")
  apy=$(jq -r '.apy | tonumber' <<<"$r")
  inst_ratio=$(jq -r '.institutional_staked_ratio | tonumber' <<<"$r")
  total_rewards=$(jq -r '.total_rewards_lamports | tonumber' <<<"$r")
  validator_rewards=$(jq -r '.validator_rewards_lamports | tonumber' <<<"$r")

  total_rewards_inst=$(jq -n --argjson tr "$total_rewards" --argjson ir "$inst_ratio" --argjson L "$LPS" '($tr*$ir)/$L')
  pot=$(jq -n --argjson vr "$validator_rewards" --argjson ir "$inst_ratio" --argjson L "$LPS" '($vr*$ir)/$L')

  mnde_target=$(jq -n --argjson tri "$total_rewards_inst" --argjson apy "$apy" '$tri * (0.003 / $apy)')
  val_target=$(jq -n --argjson tri "$total_rewards_inst" --argjson apy "$apy" '$tri * (0.005 / $apy)')

  mnde_paid=$(awk -v t="$mnde_target" -v p="$pot" 'BEGIN{print (t<p)?t:p}')
  rem_after_mnde=$(awk -v p="$pot" -v m="$mnde_paid" 'BEGIN{r=p-m; if(r<0) r=0; print r}')
  val_paid=$(awk -v t="$val_target" -v r="$rem_after_mnde" 'BEGIN{print (t<r)?t:r}')
  stakers_bonds=$(awk -v p="$pot" -v m="$mnde_paid" -v v="$val_paid" 'BEGIN{s=p-m-v; if(s<0)s=0; print s}')

  printf "%-8s │ %-12.6f │ %-12.6f │ %-12.6f │ %-12.6f │ %-12.6f │ %-12.6f\n" \
    "$epoch" "$mnde_target" "$val_target" "$pot" "$mnde_paid" "$val_paid" "$stakers_bonds"
done
