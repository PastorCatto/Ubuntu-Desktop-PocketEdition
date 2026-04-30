#!/bin/bash
# Run once after cloning or extracting the repo to create firmware symlinks.
# firmware/oneplus-fajita -> oneplus-enchilada (shared blob set, same oneplus6 path)
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
ln -sfn oneplus-enchilada oneplus-fajita
echo ">>> firmware/oneplus-fajita -> oneplus-enchilada"
echo ">>> Done."
