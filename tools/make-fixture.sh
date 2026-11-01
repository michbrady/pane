#!/bin/zsh
# Builds a throwaway home folder for snapshots: tools/make-fixture.sh /tmp/Pane-home
set -eu
home=${1:?usage: make-fixture.sh <dir>}
rm -rf "$home"
mkdir -p "$home"/{Desktop,Downloads,Pictures,Music,Empty} "$home"/Volumes/{Backup,NAS}
mkdir -p "$home/Library/Mobile Documents/com~apple~CloudDocs" "$home/Library/CloudStorage/Dropbox" "$home/Library/CloudStorage/GoogleDrive-me@example.com" "$home"/Documents/{Work,Personal,"Tax Returns"}
file() { # path size-in-KB date
  mkdir -p "${1:h}"; dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null; touch -t "$3" "$1"
}
d="$home/Documents"
file "$home/Volumes/Backup/Archive.zip" 20 202610010900
file "$home/Volumes/NAS/Holiday.mov" 40 202610020900
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
# Finder tags, so the Tags column has something to show.
tag() { xattr -wx com.apple.metadata:_kMDItemUserTags "$(python3 -c 'import plistlib,sys;print(plistlib.dumps(sys.argv[2:],fmt=plistlib.FMT_BINARY).hex())' x "${@:2}")" "$1"; }
tag "$d/Budget 2026.xlsx" "Work"
tag "$d/Trip itinerary.pdf" "Red" "Travel"
file "$home/Pictures/Beach.jpg" 3400 202608141530
file "$home/Pictures/Family.png" 2100 202607040900
file "$home/Downloads/Installer.dmg" 80000 202610301800
file "$home/Downloads/Receipt.pdf" 60 202610291200
file "$home/Desktop/Screenshot.png" 900 202610311000
# Real content for the preview pane, written last so nothing overwrites it: text, a small PDF (padded so it stays the largest file), and a PNG.
python3 - "$home" <<'PY'
import struct, sys, zlib
home = sys.argv[1]
open(f"{home}/Documents/Notes.txt", "w").write("Notes for the week\n\n- Book the dentist\n- Renew passport\n- Plan the weekend trip\n- Draft the quarterly review\n")
def png(w, h):
    rows = b"".join(b"\x00" + b"".join(bytes((40 + x * 160 // w, 120 + y * 100 // h, 200 - x * 100 // w)) for x in range(w)) for y in range(h))
    def chunk(tag, data): return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
open(f"{home}/Pictures/Beach.jpg", "wb").write(png(320, 200))
text = b"BT /F1 24 Tf 72 700 Td (Trip itinerary) Tj 0 -36 Td /F1 14 Tf (Day 1: Arrive and check in) Tj 0 -24 Td (Day 2: Coast walk and lunch) Tj 0 -24 Td (Day 3: Head home) Tj ET"
objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(text) + text + b"\nendstream", b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out = b"%PDF-1.4\n"; offsets = []
for i, o in enumerate(objs, 1):
    offsets.append(len(out)); out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(f"{home}/Documents/Trip itinerary.pdf", "wb").write(out + b"\n" * (1884160 - len(out)))
PY
touch -t 202610310714 "$d/Notes.txt"; touch -t 202609300800 "$d/Trip itinerary.pdf"; touch -t 202608141530 "$home/Pictures/Beach.jpg"
# An old-style iCloud stub: a hidden file that stands for "Report.pdf", which is not on this Mac.
python3 - "$home" <<'PY'
import plistlib, sys
home = sys.argv[1]
icloud = f"{home}/Library/Mobile Documents/com~apple~CloudDocs"
open(f"{icloud}/.Report.pdf.icloud", "wb").write(plistlib.dumps({"NSURLFileSizeKey": 482304, "NSURLNameKey": "Report.pdf"}, fmt=plistlib.FMT_BINARY))
open(f"{icloud}/Shopping list.txt", "w").write("milk\neggs\n")
open(f"{home}/Library/CloudStorage/Dropbox/Team notes.txt", "w").write("shared\n")
PY
