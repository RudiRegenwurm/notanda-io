#!/bin/sh
# Listet alle offenen Platzhalter der Form [GROSSBUCHSTABEN ...] in den HTML-Dateien.
cd "$(dirname "$0")"
grep -n -o '\[[A-Z][A-Z0-9 ,/-]*\]' index.html imprint.html privacy.html | sort -u
n=$(grep -o '\[[A-Z][A-Z0-9 ,/-]*\]' index.html imprint.html privacy.html | wc -l)
echo "--- $n offene Platzhalter"
