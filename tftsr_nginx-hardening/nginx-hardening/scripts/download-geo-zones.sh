#!/usr/bin/env bash
# Download ipdeny.com aggregated zone files for all blocked countries.
# Run this on a machine WITH internet access, then rsync the output
# directory to the DMZ host and set geo_zone_files_dir in your inventory.
#
# Usage:
#   ./scripts/download-geo-zones.sh [output-dir]
#
# Example workflow:
#   # On your workstation:
#   ./scripts/download-geo-zones.sh /tmp/geo_zones
#   rsync -av /tmp/geo_zones/ sarman@dmz-host:/opt/geo_zones/
#
#   # Then run the playbook pointing at the cache:
#   ansible-playbook -K playbooks/geo_blocking.yml -e geo_zone_files_dir=/opt/geo_zones

set -euo pipefail

BASE_URL="https://www.ipdeny.com/ipblocks/data/aggregated"
OUT_DIR="${1:-/tmp/geo_zones}"

# All blocked country codes (excludes US and ipdeny-absent territories)
COUNTRIES=(
  AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ
  BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BW BY BZ
  CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CY CZ
  DE DJ DK DM DO DZ
  EC EE EG ER ES ET
  FI FJ FK FM FO FR
  GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GT GU GW GY
  HK HN HR HT HU
  ID IE IL IM IN IO IQ IR IS IT
  JE JM JO JP
  KE KG KH KI KM KN KP KR KW KY KZ
  LA LB LC LI LK LR LS LT LU LV LY
  MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ
  NA NC NE NF NG NI NL NO NP NR NU NZ
  OM
  PA PE PF PG PH PK PL PM PR PS PT PW PY
  QA
  RE RO RS RU RW
  SA SB SC SD SE SG SI SK SL SM SN SO SR SS ST SV SX SY SZ
  TC TD TG TH TJ TK TL TM TN TO TR TT TV TW TZ
  UA UG UM UY UZ
  VA VC VE VG VI VN VU
  WF WS
  YE YT
  ZA ZM ZW
)

mkdir -p "$OUT_DIR"
echo "Downloading ${#COUNTRIES[@]} zone files to $OUT_DIR ..."

ok=0; fail=0
for cc in "${COUNTRIES[@]}"; do
  url="${BASE_URL}/${cc,,}-aggregated.zone"
  dest="${OUT_DIR}/${cc,,}.zone"
  if curl -fsSL --connect-timeout 10 --max-time 30 -o "$dest" "$url"; then
    (( ++ok ))
  else
    echo "  SKIP $cc (no zone file at ipdeny.com)"
    rm -f "$dest"
    (( ++fail ))
  fi
done

echo "Done: $ok downloaded, $fail skipped."
echo ""
echo "Next steps:"
echo "  rsync -av ${OUT_DIR}/ USER@DMZ_HOST:/opt/geo_zones/"
echo "  ansible-playbook -K playbooks/geo_blocking.yml -e geo_zone_files_dir=/opt/geo_zones"
