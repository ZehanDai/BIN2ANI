#!/bin/bash

# ============================================================================
# Metagenomic analysis pipeline: assembly → mapping → binning → ANI identification
# Usage: ./pipeline.sh -1 R1.fq.gz -2 R2.fq.gz -r <reference_genome_dir> [options]
# ============================================================================

# ----------------------------- Default parameters ----------------------------
THREADS=8
OUTDIR="./pipeline_output"

# Sub-script paths (assumed to be in the same directory as this script, or use absolute paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QC_SCRIPT="${SCRIPT_DIR}/utils/01qc_assembly.sh"
MAPPING_SCRIPT="${SCRIPT_DIR}/utils/02run_mapping.sh"
BINNING_SCRIPT="${SCRIPT_DIR}/utils/03binning.sh"
FASTANI_SCRIPT="${SCRIPT_DIR}/utils/04run_fastANI.sh"

# ----------------------------- Help message ----------------------------------
usage() {
    cat <<EOF
Usage: $0 -1 <R1.fq.gz> -2 <R2.fq.gz> -r <reference_genome_dir> [options]

Required:
  -1    R1 read file (gzip compressed)
  -2    R2 read file (gzip compressed)
  -r    Reference genome directory (for fastANI comparison, contains .fna/.fa files)

Optional:
  -o    Output root directory (default: ./pipeline_output)
  -t    Number of threads (default: 8)
  -h    Show this help

EOF
    exit 0
}

# ----------------------------- Parse arguments -------------------------------
while getopts "1:2:r:o:t:m:h" opt; do
    case "$opt" in
        1) R1="$OPTARG" ;;
        2) R2="$OPTARG" ;;
        r) REF_DIR="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check required parameters after getopts
if [ -z "$R1" ] || [ -z "$R2" ] || [ -z "$REF_DIR" ]; then
    echo "Error: Missing required parameters -1, -2, or -r" >&2
    usage
fi

# ----------------------------- Create output subdirectories ------------------
mkdir -p "$OUTDIR"

echo "===== Pipeline started $(date) ====="
echo "Input files: $R1 $R2"
echo "Reference directory: $REF_DIR"
echo "Output directory: $OUTDIR"
echo "Threads: $THREADS"
echo ""

# ----------------------------- Step 1: QC and assembly -----------------------
echo "=== Step 1: QC and assembly (01qc_assembly.sh) ==="

# Assembly output directory: $OUTDIR/assembly
ASM_OUT="$OUTDIR/assembly"
bash "$QC_SCRIPT" -1 "$R1" -2 "$R2" -o "$ASM_OUT" -t "$THREADS"

# Locate assembly results (scaffolds.fasta)
SCAFFOLDS=$(find "$ASM_OUT/02spades_out" -maxdepth 2 -name "scaffolds.fasta" | head -1)
# (Commented out) Check if scaffolds found
# if [ -z "$SCAFFOLDS" ] || [ ! -f "$SCAFFOLDS" ]; then
#     echo "Error: Assembly result (scaffolds.fasta) not found. Please check output of 01qc_assembly.sh"
#     exit 1
# fi
# echo "Assembly result: $SCAFFOLDS"
echo ""

# ----------------------------- Step 2: Mapping to generate BAM ---------------
echo "=== Step 2: Mapping (run_mapping.sh) ==="
MAP_OUT="$OUTDIR/mapping"
mkdir -p "$MAP_OUT"
bash "$MAPPING_SCRIPT" -r "$SCAFFOLDS" -o "$MAP_OUT" -1 "$R1" -2 "$R2" -t "$THREADS"
# Get the generated BAM file (assuming script outputs basename.sorted.bam)
BAM_NAME=$(basename "${R1%%.*}")  # use R1 basename
BAM_FILE="$MAP_OUT/${BAM_NAME}.sorted.bam"
# echo "BAM file: $BAM_FILE"
echo ""

# ----------------------------- Step 3: Binning (binning.sh) ------------------
echo "=== Step 3: Binning (binning.sh) ==="
BIN_OUT="$OUTDIR/binning"
mkdir -p "$BIN_OUT"
bash "$BINNING_SCRIPT" -c "$SCAFFOLDS" -o "$BIN_OUT" -b "$BAM_FILE" -t "$THREADS"
# Check binning results
BIN_DIR="$BIN_OUT"   # Assuming binning.sh directly generates bin.*.fa in output directory
if [ ! -f "$BIN_OUT/bin.1.fa" ]; then
    echo "Warning: Binning results not found. Perhaps binning.sh output location differs; trying to search..."
    # Try to search
    BIN_FILES=$(find "$BIN_OUT" -maxdepth 1 -name "bin.*.fa" | head -1)
    if [ -z "$BIN_FILES" ]; then
        echo "Error: No bin.*.fa files found. Please check binning.sh"
        exit 1
    fi
    BIN_DIR="$BIN_OUT"
fi
# echo "Binning result directory: $BIN_DIR"
echo ""

# ----------------------------- Step 4: fastANI comparison --------------------
echo "=== Step 4: fastANI comparison (run_fastANI.sh) ==="
ANI_OUT="$OUTDIR/ani"
mkdir -p "$ANI_OUT"
ANI_FILE="$ANI_OUT/${BAM_NAME}-ref.ANI.txt"
bash "$FASTANI_SCRIPT" -b "$BIN_DIR" -r "$REF_DIR" -o "$ANI_FILE" -t "$THREADS"
echo "ANI result: $ANI_FILE"