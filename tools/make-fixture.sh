#!/bin/zsh
# Builds a throwaway home folder for snapshots: tools/make-fixture.sh /tmp/Pane-home
set -eu
home=${1:?usage: make-fixture.sh <dir>}
rm -rf "$home"
mkdir -p "$home"/{Desktop,Downloads,Pictures,Music,Empty} "$home"/Documents/{Work,Personal,"Tax Returns"}
file() { # path size-in-KB date
  mkdir -p "${1:h}"; dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null; touch -t "$3" "$1"
}
d="$home/Documents"
file "$d/Quarterly review.docx" 48 202610211430
file "$d/Budget 2026.xlsx" 112 202610150915
file "$d/Trip itinerary.pdf" 1840 202609300800
file "$d/Notes.txt" 4 202610310714
file "$d/Read me first.md" 2 202610281200
file "$d/A very long file name that keeps going to test how names truncate in the middle of the row.txt" 1 202610010000
file "$d/file2.txt" 1 202610020000
file "$d/file10.txt" 1 202610020000
file "$d/Work/Roadmap.key" 5200 202610221000
file "$d/Work/Invoice 0042.pdf" 96 202610091100
touch -t 202610200900 "$d/Work" "$d/Personal" "$d/Tax Returns"
file "$home/Pictures/Beach.jpg" 3400 202608141530
file "$home/Pictures/Family.png" 2100 202607040900
file "$home/Downloads/Installer.dmg" 80000 202610301800
file "$home/Downloads/Receipt.pdf" 60 202610291200
file "$home/Desktop/Screenshot.png" 900 202610311000
