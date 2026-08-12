#!/bin/bash
# Extracts PDF metadata for review — embedded fields + filesystem dates
# Usage: ./pdf_metadata.sh <file.pdf>
#    or: ./pdf_metadata.sh   (runs on all meeting-related PDFs)

dump_meta() {
    local file="$1"
    local basename=$(basename "$file")

    echo "========================================"
    echo "File: $basename"
    echo "========================================"

    # Filesystem dates
    echo ""
    echo "Filesystem:"
    stat -f "  Created:  %SB" -t "%Y-%m-%d %H:%M:%S" "$file"
    stat -f "  Modified: %Sm" -t "%Y-%m-%d %H:%M:%S" "$file"

    # Embedded PDF metadata via python (works on macOS)
    # Dumps everything. High-value fields up top, structural/raw at the bottom.
    echo ""
    echo "Embedded PDF Metadata:"
    python3 -c "
import sys, re

with open(sys.argv[1], 'rb') as f:
    data = f.read()
text = data.decode('latin-1')

# Fields we care about most
priority_keys = ['Title', 'Author', 'Subject', 'Keywords', 'Creator',
                 'Producer', 'CreationDate', 'ModDate', 'SourceModified',
                 'LastModified', 'Lang', 'Company']

# Fields that are pure PDF plumbing — never useful
plumbing = {'Type', 'Subtype', 'Filter', 'Length', 'BaseFont', 'Encoding',
            'Name', 'ColorSpace', 'Width', 'Height', 'BitsPerComponent',
            'Resources', 'MediaBox', 'CropBox', 'Rotate', 'Pages', 'Count',
            'Contents', 'Parent', 'Annots', 'StructTreeRoot', 'MarkInfo',
            'Metadata', 'OutputIntents', 'OpenAction', 'PageMode',
            'Outlines', 'Dests', 'Threads', 'PageLayout', 'PageLabels',
            'StructParents', 'Tabs'}

priority_out = []
other_out = []

# --- PDF Info Dict: every /Key (Value) pair ---
for m in re.finditer(r'/([A-Za-z]{2,})\s*\(([^)]*)\)', text):
    key, val = m.group(1), m.group(2).strip()
    if not val or key in plumbing:
        continue
    printable = sum(1 for c in val if 32 <= ord(c) < 127)
    is_clean = len(val) > 0 and printable / len(val) > 0.7
    line = f'  {key:20s} {val}'
    if key in priority_keys and is_clean:
        priority_out.append(line)
    elif is_clean:
        other_out.append(line)
    else:
        other_out.append(f'  {key:20s} (binary/non-printable, {len(val)} bytes)')

# --- Hex-encoded strings: /Key <FEFF...> ---
for m in re.finditer(r'/([A-Za-z]+)\s*<([0-9A-Fa-f]+)>', text):
    key, hexval = m.group(1), m.group(2)
    if len(hexval) < 8:
        continue
    try:
        decoded = bytes.fromhex(hexval).decode('utf-16-be', errors='replace').strip('\x00').strip()
        if decoded and len(decoded) > 1:
            line = f'  {key:20s} {decoded} (hex-decoded)'
            if key in priority_keys:
                priority_out.append(line)
            else:
                other_out.append(line)
    except:
        other_out.append(f'  {key:20s} <{hexval[:40]}...> (raw hex, {len(hexval)} chars)')

# --- XMP: all tags ---
xmp_priority = []
xmp_other = []
xmp_start = text.find('<x:xmpmeta')
if xmp_start >= 0:
    xmp_end = text.find('</x:xmpmeta', xmp_start)
    if xmp_end >= 0:
        xmp = text[xmp_start:xmp_end+30]
        for m2 in re.finditer(r'<([a-zA-Z]+:[a-zA-Z]+)>([^<]+)</\1>', xmp):
            tag, val = m2.group(1), m2.group(2).strip()
            if val:
                line = f'  {tag:20s} {val}'
                short_key = tag.split(':')[-1] if ':' in tag else tag
                if short_key in ('CreatorTool', 'Producer', 'CreateDate', 'ModifyDate',
                                 'MetadataDate', 'DocumentID', 'InstanceID'):
                    xmp_priority.append(line)
                else:
                    xmp_other.append(line)

# --- Output ---
if priority_out or other_out or xmp_priority or xmp_other:
    print('  --- Info Dict (key fields) ---')
    for line in priority_out:
        print(line)
    if xmp_priority:
        print('  --- XMP Stream (key fields) ---')
        for line in xmp_priority:
            print(line)
    if other_out or xmp_other:
        print('  --- Other fields ---')
        for line in other_out:
            print(line)
        for line in xmp_other:
            print(line)
else:
    print('  (none found — likely scanned/image PDF)')
" "$file"

    echo ""
}

if [ -n "$1" ]; then
    dump_meta "$1"
else
    echo "Scanning all meeting-related PDFs in 05_DocsFromPortal..."
    echo ""
    find "$(dirname "$0")/05_DocsFromPortal" -iname "*.pdf" \
        \( -iname "*minute*" -o -iname "*meeting*" -o -iname "*agenda*" -o -iname "*board*" -o -iname "*community*" \) \
        | sort | while read -r f; do
        dump_meta "$f"
    done
fi
