#!/bin/bash
# Mobuntu RC16a — build-dummies.sh
# Run ONCE on the build host to produce dummy .deb packages.
# Commit the resulting .deb files to packages/dummy/.
# These are arm64 packages built on the x86-64 host via equivs.
#
# Usage:
#   cd packages/dummy/
#   ./build-dummies.sh
#
# Requires: equivs
#   sudo apt-get install equivs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
die()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

command -v equivs-build &>/dev/null || \
    die "equivs not installed. Run: sudo apt-get install equivs"

info "Building dummy packages for Mobuntu RC16a..."
info "These block hexagonrpcd from being pulled in by sdm845-support."
echo ""

for control in hexagonrpcd-dummy.control qcom-support-common-dummy.control; do
    [ -f "$control" ] || die "Missing control file: $control"
    pkg=$(grep '^Package:' "$control" | awk '{print $2}')
    info "Building: $pkg"
    equivs-build "$control"
    ok "Built: ${pkg}_99.0-mobuntu1_all.deb"
done

echo ""
ok "Done. Commit the .deb files to packages/dummy/ and re-run the build."
echo ""
echo "Files produced:"
ls -lh ./*.deb 2>/dev/null || true
