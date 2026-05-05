#!/usr/bin/env bash

DIR="terraform"
issues=0

if ! command -v trivy &> /dev/null; then
    echo "[!!!] trivy could not be found. Please install trivy before running this script."
    exit 1
fi

if [ ! -d "$DIR" ]; then
    echo "[!!!] terraform directory could not be found. Please run this script from the root of your project."
    exit 1
fi

rm -f trivy_scan_*.txt

for file in $DIR/*.tf; do
    [ -e $file ] || continue

    report_name="trivy_scan_$(basename "$file").txt"

    if ! trivy config --severity HIGH,CRITICAL --exit-code 1 $file > $report_name; then
        echo "[!!!] HIGH and/or CRITICAL issues found in $scan_result"
        issues=$(( $issues + 1 ))
    else
        rm $report_name
    fi
done

if [[ "$issues" -gt 0 ]]; then
    echo "[!!!] HIGH and/or CRITICAL issues found in $issues config file(s)."
    exit 1
fi

echo "[*] Trivy scan completed"
echo "[*] No issues found in config files."
exit 0
