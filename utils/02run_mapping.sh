#!/bin/bash
set -euo pipefail

# ============================================================================
#  Map raw reads to assembled contigs/scaffolds, generate sorted BAM
#  Usage: ./run_mapping.sh -r <contigs.fa> -o <outdir> [ -1 R1.fq ] [ -2 R2.fq ] [ -U single.fq ] [ -t threads ]
# ============================================================================

# ----------------------------- Default parameters ----------------------------
THREADS=8
hisat2="hisat2"
SAMTOOLS="samtools"

# ----------------------------- Help message ----------------------------------
usage() {
    cat <<EOF
Usage: $0 -r <contigs.fa> -o <outdir> (must provide -1 -2 or -U)

Required:
  -r    Reference sequence file (assembled contigs/scaffolds FASTA)
  -o    Output directory (for index, BAM, and logs)

Reads input (choose one):
  -1    R1 fastq (paired-end)
  -2    R2 fastq (paired-end)
  -U    Single-end fastq

Optional:
  -t    Number of threads (default: 8)
  -h    Show this help

Examples:
  # Paired-end
  $0 -r assembly/contigs.fasta -o mapping/ -1 reads_R1.fq.gz -2 reads_R2.fq.gz -t 16
  # Single-end
  $0 -r contigs.fa -o ./mapping -U single.fq.gz
EOF
    exit 0
}

# ----------------------------- Parse arguments -------------------------------
REF=""
OUTDIR=""
R1=""
R2=""
U=""

while getopts "r:o:1:2:U:t:h" opt; do
    case "$opt" in
        r) REF="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        1) R1="$OPTARG" ;;
        2) R2="$OPTARG" ;;
        U) U="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check required arguments
[ -z "$REF" ] && { echo "Error: Missing -r"; usage; }
[ -z "$OUTDIR" ] && { echo "Error: Missing -o"; usage; }

# Check reads input
if [ -z "${R1}${R2}${U}" ]; then
    echo "Error: Must provide reads input (-1 -2 or -U)"
    usage
fi

mkdir -p "$OUTDIR"

# ----------------------------- Determine read name and final BAM path --------
if [ -n "$U" ]; then
    read_base=$(basename "$U")
    read_name="${read_base%%.*}"
else
    read_base1=$(basename "$R1")
    read_name="${read_base1%%.*}"
fi
FINAL_BAM="$OUTDIR/${read_name}.sorted.bam"
FINAL_BAI="${FINAL_BAM}.bai"

# ----------------------------- Skip if final BAM and BAI already exist -------
if [ -f "$FINAL_BAM" ] && [ -s "$FINAL_BAM" ] && [ -f "$FINAL_BAI" ] && [ -s "$FINAL_BAI" ]; then
    echo Mapping result already exist:
    echo $FINAL_BAM and $FINAL_BAI
    echo "Skipping entire mapping process for this sample."
    #echo "To rerun, delete both files manually."
    echo "================================="
    exit 0
fi

# ----------------------------- Logging ---------------------------------------
LOG="$OUTDIR/mapping.log"
exec > >(tee -a "$LOG") 2>&1

echo "===== Mapping started ====="
echo "Reference: $REF"
echo "Output directory: $OUTDIR"
echo "Threads: $THREADS"

# ============================================================================
# 1. Build hisat2 index (if not present)
# ============================================================================
ref_name=$(basename "$REF")
ref_prefix="${ref_name%.*}"
idx_prefix="$OUTDIR/${ref_prefix}"

if [ -f "${idx_prefix}.1.ht2" ]; then
    echo "Index already exists, skipping build"
else
    echo "Building hisat2 index..."
    time hisat2-build "$REF" "$idx_prefix"
fi

# ============================================================================
# 2. Align reads to generate SAM
# ============================================================================
SAM="$OUTDIR/${read_name}.sam"
if [ -n "$U" ]; then
    CMD="hisat2 -x $idx_prefix -U $U -S $SAM -p $THREADS --no-unal"
else
    CMD="hisat2 -x $idx_prefix -1 $R1 -2 $R2 -S $SAM -p $THREADS --no-unal"
fi

echo "Running alignment:"
echo "$CMD"
time eval $CMD

# ============================================================================
# 3. Convert to sorted BAM and index
# ============================================================================
echo "Converting SAM to sorted BAM..."
time $SAMTOOLS sort -@ "$THREADS" -o "$FINAL_BAM" "$SAM"
$SAMTOOLS index "$FINAL_BAM"

# ============================================================================
# 4. Clean up intermediate files (SAM and Hisat2 indices)
# ============================================================================
echo "Removing intermediate SAM file: $SAM"
rm -f "$SAM"

echo "Removing Hisat2 index files (${idx_prefix}*.ht2)"
rm -f "${idx_prefix}"*.ht2
echo "================================="
echo "Final BAM: $FINAL_BAM"
echo "Index: $FINAL_BAI"
echo "===== Mapping ended $(date) ====="