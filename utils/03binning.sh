#!/bin/bash
set -euo pipefail

# ============================================================================
# Single-sample binning script using MetaBAT2
# Usage: ./binning_single.sh -c <contigs.fa> -o <output_dir> [ -b <mapped.bam> ] [ -t <threads> ]
# ============================================================================

# ----------------------------- Default parameters ------------------------------------
THREADS=8
#MIN_CONTIG_LEN=1500   # MetaBAT2 default length filter

# ----------------------------- Help message ------------------------------------
usage() {
    cat <<EOF
Usage: $0 -c <contigs.fa> -o <output_dir> [options]

Required:
  -c    Contigs/scaffolds FASTA file path
  -o    Output root directory (bin files and intermediates will be stored here)

Optional:
  -b    BAM file (sorted and indexed); if not provided, script will try to find
        <basename>.sorted.bam in the same directory as contigs
  -t    Number of threads (default: 8)
  -m    Minimum contig length (default: 1500)
  -h    Show this help
EOF
    exit 0
}

# ----------------------------- Argument validation ------------------------------------
while getopts "c:o:b:t:m:h" opt; do
    case "$opt" in
        c) CONTIGS="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        b) BAM="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        #m) MIN_CONTIG_LEN="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "${CONTIGS:-}" ] || [ -z "${OUTDIR:-}" ]; then
    echo "Error: parameters -c and -o not provided"
    usage
fi

# ----------- BAM file handling ----------
if [ -z "${BAM:-}" ]; then
    # Auto-detect: take basename of CONTIGS (remove extension) and add .sorted.bam
    base="${CONTIGS%.*}"
    BAM="${base}.sorted.bam"
    if [ ! -f "$BAM" ]; then
        echo "Error: BAM file not specified and auto-detected path ($BAM) does not exist"
        exit 1
    fi
    echo "Using auto-detected BAM: $BAM"
fi

if [ ! -f "${BAM}.bai" ]; then
    echo "Warning: BAM index ${BAM}.bai not found, generating now..."
    if ! command -v samtools &>/dev/null; then
        echo "Error: samtools is not installed, cannot generate index"
        exit 1
    fi
    samtools index "$BAM"
fi

# ----------- Create output directory ----------
mkdir -p "$OUTDIR"

# ----------------------------- Logging  ------------------------------------
LOG="$OUTDIR/binning.log"
exec > >(tee -a "$LOG") 2>&1
echo "===== Binning started $(date) ====="
echo "contigs: $CONTIGS"
echo "BAM: $BAM"
echo "Output path: $OUTDIR"
# echo "Threads: $THREADS, Minimum contig length: $MIN_CONTIG_LEN"

# ===========================================================================
# Step 1: Calculate contig depths
# ===========================================================================
DEPTH_FILE="$OUTDIR/depth.txt"
echo "--- Calculating depth information ---"
if [ -f "$DEPTH_FILE" ] && [ -s "$DEPTH_FILE" ]; then
    echo "Depth file already exists, skipping calculation"
else
    time jgi_summarize_bam_contig_depths --outputDepth "$DEPTH_FILE" "$BAM"
    echo "Depth file generated: $DEPTH_FILE"
fi


# ===========================================================================
# Step 2: MetaBAT2 binning
# ===========================================================================
echo "--- MetaBAT2 binning ---"
BIN_PREFIX="$OUTDIR/bin"

if ls "$BIN_PREFIX".*.fa 1>/dev/null 2>&1; then
    echo "Existing bin results found, skipping binning step"
else
    time metabat2 -i "$CONTIGS"  -a "$DEPTH_FILE" -o "$BIN_PREFIX" \
                  -t "$THREADS" -v
    echo "Binning complete"
fi


# ===========================================================================
# Step 3: Generate binning statistics (optional)
# ===========================================================================
echo "--- Generating binning statistics ---"
NUM_BINS=$(ls "$BIN_PREFIX".*.fa 2>/dev/null | wc -l)
echo "Acquired $NUM_BINS bins in total"

# Optional: use CheckM for further evaluation, uncomment if needed
# checkm lineage_wf "$OUTDIR" "$OUTDIR/checkm" -t "$THREADS" -x fa

echo "===== Binning ended $(date) ====="
