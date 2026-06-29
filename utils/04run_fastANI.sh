#!/bin/bash
set -euo pipefail

# ============================================================================
#  Use fastANI to compare bins against reference genomes
#  Usage: ./run_fastANI.sh -b <bin_dir> -r <ref_dir> -o <output_file> [ -t <threads> ]
# ============================================================================

# ----------------------------- Default parameters ----------------------------
THREADS=8
OUTPUT="ani_results.txt"

# ----------------------------- Help message ----------------------------------
usage() {
    cat <<EOF
Usage: $0 -b <bin_dir> -r <ref_dir> -o <output_file> [ -t <threads> ]

Required:
  -b    Directory containing bin.*.fa files
  -r    Reference genome directory (contains .fna or .fa files, supports .gz)
  -o    Output result file (fastANI output)

Optional:
  -t    Number of threads (default: 4)
  -h    Show this help

Example:
  $0 -b ./bins -r ./ref_genomes -o ani.out -t 8
EOF
    exit 0
}

# ----------------------------- Parse arguments -------------------------------
BIN_DIR=""
REF_DIR=""
while getopts "b:r:o:t:h" opt; do
    case "$opt" in
        b) BIN_DIR="$OPTARG" ;;
        r) REF_DIR="$OPTARG" ;;
        o) OUTPUT="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check required arguments
if [ -z "$BIN_DIR" ] || [ -z "$REF_DIR" ] || [ -z "$OUTPUT" ]; then
    echo "Error: Missing required arguments (-b, -r, -o)"
    usage
fi

# ----------------------------- Check if output already exists ----------------
if [ -f "$OUTPUT" ] && [ -s "$OUTPUT" ]; then
    echo "===== ANI comparison already completed: $OUTPUT exists and is non-empty ====="
    echo "Skipping fastANI run for this sample."
    #echo "To rerun, delete $OUTPUT manually."
    exit 0
fi

# ----------------------------- Prepare file lists ----------------------------
# Find all bin files (assumed suffix .fa)
bin_files=($(find "$BIN_DIR" -maxdepth 1 -name "bin.*.fa" -type f | sort))
if [ ${#bin_files[@]} -eq 0 ]; then
    echo "Error: No bin.*.fa files found in $BIN_DIR"
    exit 1
fi
echo "Found ${#bin_files[@]} bins"

# Find all reference genome files (supports .fna, .fa, .gz)
ref_files=($(find "$REF_DIR" -maxdepth 1 -type f \( -name "*.fna*" -o -name "*.fa*" \) | sort))
if [ ${#ref_files[@]} -eq 0 ]; then
    echo "Error: No reference genome files found in $REF_DIR (*.fna, *.fa, *.fna.gz, etc.)"
    exit 1
fi
echo "Found ${#ref_files[@]} reference genomes"

# Create temporary list files
query_list=$(mktemp)
ref_list=$(mktemp)
trap 'rm -f "$query_list" "$ref_list"' EXIT  # Automatically remove temp files on exit

# Write to lists
printf "%s\n" "${bin_files[@]}" > "$query_list"
printf "%s\n" "${ref_files[@]}" > "$ref_list"

# ----------------------------- Run fastANI -----------------------------------
echo "--- Running fastANI (threads: $THREADS) ---"
echo "Output file: $OUTPUT"
time fastANI --ql "$query_list" --rl "$ref_list" -o "$OUTPUT" -t "$THREADS"

echo "--- ANI comparison completed ---"