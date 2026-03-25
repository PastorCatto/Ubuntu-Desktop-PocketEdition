#!/bin/bash

# --- Configuration ---
SOURCE_SCRIPT="deploy_workspace.sh"
TEMP_SCRIPT="deploy_workspace_new.sh"

echo "======================================================="
echo "   Toolchain Morphing Utility: Device Adapter"
echo "======================================================="

# 1. Collect New Device Data
read -p "New Vendor (e.g., samsung, lenovo, oneplus): " NEW_VENDOR
read -p "New Codename (e.g., gtaxl, carbon, enchilada): " NEW_CODENAME
read -p "New Model Name (e.g., Galaxy Tab A9 Plus): " NEW_MODEL
read -p "Path to extra script logic to append (leave blank if none): " EXTRA_LOGIC

# Create a copy to work on
cp "$SOURCE_SCRIPT" "$TEMP_SCRIPT"

# 2. Perform Intelligent Replacements
# We handle lowercase (beryllium), Capitalized (Beryllium), Vendor, and Model Name.
echo ">>> Injecting new device identities..."

# Replace Vendor (e.g., xiaomi -> samsung)
sed -i "s/xiaomi/$NEW_VENDOR/g" "$TEMP_SCRIPT"

# Replace Codename lowercase (e.g., beryllium -> gtaxl)
sed -i "s/beryllium/$NEW_CODENAME/g" "$TEMP_SCRIPT"

# Replace Codename Capitalized (e.g., Beryllium -> Gtaxl)
# This uses a bash trick to capitalize the first letter of the input
CAP_CODENAME="$(echo ${NEW_CODENAME:0:1} | tr '[:lower:]' '[:upper:]')${NEW_CODENAME:1}"
sed -i "s/Beryllium/$CAP_CODENAME/g" "$TEMP_SCRIPT"

# Replace Model Name (e.g., Poco F1 -> Galaxy Tab A9 Plus)
sed -i "s/Poco F1/$NEW_MODEL/g" "$TEMP_SCRIPT"

# 3. Append Extra Logic
if [[ -n "$EXTRA_LOGIC" && -f "$EXTRA_LOGIC" ]]; then
    echo ">>> Appending extra user logic from $EXTRA_LOGIC..."
    echo -e "\n# --- Custom User Additions ---\n" >> "$TEMP_SCRIPT"
    cat "$EXTRA_LOGIC" >> "$TEMP_SCRIPT"
fi

chmod +x "$TEMP_SCRIPT"

# --- Output the Execution Layout ---
echo ""
echo "======================================================="
echo "  MORPH COMPLETE: $TEMP_SCRIPT is ready."
echo "======================================================="
echo ">>> RECOMMENDED EXECUTION ORDER:"
echo "-------------------------------------------------------"
echo "1. Run Deployment:  ./$TEMP_SCRIPT"
echo "   (This generates your 1-7 device-specific scripts)"
echo ""
echo "2. Pre-flight:     bash 1_preflight.sh"
echo "   (Configures your build.env and deps)"
echo ""
echo "3. pmOS Prep:      bash 2_pmos_setup.sh"
echo "   (Initializes pmbootstrap for $NEW_CODENAME)"
echo ""
echo "4. Firmware:       bash 3_firmware_fetcher.sh"
echo "   (Retrieves hardware blobs from your target device)"
echo ""
echo "5. The Transplant: bash 4_the_transplant.sh"
echo "   (Builds the actual Ubuntu RootFS)"
echo ""
echo "6. Final Seal:     bash 6_seal_rootfs.sh"
echo "   (Produces the final .img files for flashing)"
echo "-------------------------------------------------------"