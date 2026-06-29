#!/bin/bash
set -e

# ================================================
# Step 1: QC + Assembly
# Usage: qc_assembly.sh -1 R1.fastq.gz -2 R2.fastq.gz -o outdir [options]
#        qc_assembly.sh -u single.fastq.gz -o outdir [options]
# Options: -t threads (default 16), -m memory_GB (default 100)
# ================================================

# ---------- Default parameters ----------
THREADS=4
MEMORY=8
R1=""
R2=""
SINGLE=""
OUTDIR=""
PREFIX=""

# ---------- Help message ----------
usage() {
    cat <<EOF
Usage: $0 -1 <R1.fastq.gz> -2 <R2.fastq.gz> -o <output_dir> [-t threads] [-m memory_GB]
   or: $0 -u <single_end.fastq.gz> -o <output_dir> [-t threads] [-m memory_GB] [-p custom_prefix]

Options:
  -1  R1 file for paired-end sequencing (supports .gz)
  -2  R2 file for paired-end sequencing (used with -1)
  -u  Single-end sequencing file (mutually exclusive with -1/-2)
  -o  Output root directory (will create 01fastp_report, 01fastp_cleanData, 02spades_out)
  -t  Number of threads (default 4)
  -m  SPAdes memory limit in GB (default 8)
  -p  Custom sample prefix (if not specified, automatically extracted from filename)
  -h  Show this help

EOF
    exit 1
}

# ---------- Parse arguments ----------
while getopts "1:2:u:o:t:m:p:h" opt; do
    case $opt in
        1) R1="$OPTARG" ;;
        2) R2="$OPTARG" ;;
        u) SINGLE="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        m) MEMORY="$OPTARG" ;;
        p) PREFIX="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ---------- Argument validation ----------
if [ -z "$OUTDIR" ]; then
    echo "Error: Must specify -o output directory"
    usage
fi

# Check input file combination validity
if [ -n "$R1" ] && [ -n "$R2" ]; then
    # Paired-end mode
    if [ -n "$SINGLE" ]; then
        echo "Error: Cannot specify both paired-end (-1/-2) and single-end (-u)"
        usage
    fi
    if [ ! -f "$R1" ] || [ ! -f "$R2" ]; then
        echo "Error: R1 or R2 file does not exist"
        exit 1
    fi
    MODE="PE"
    echo "Paired-end mode: R1=$R1, R2=$R2"
elif [ -n "$SINGLE" ]; then
    # Single-end mode
    if [ -n "$R1" ] || [ -n "$R2" ]; then
        echo "Error: Cannot specify both single-end (-u) and paired-end (-1/-2)"
        usage
    fi
    if [ ! -f "$SINGLE" ]; then
        echo "Error: Single-end file does not exist"
        exit 1
    fi
    MODE="SE"
    echo "Single-end mode: $SINGLE"
else
    echo "Error: Must specify input files (-1 -2 or -u)"
    usage
fi

# ---------- Determine sample prefix ----------
if [ -n "$PREFIX" ]; then
    base="$PREFIX"
    echo "Using custom prefix: $base"
else
    if [ "$MODE" = "PE" ]; then
        # Extract prefix: remove _1.fq.clean.gz or _1.fastq.gz etc.
        base=$(basename "$R1" | sed -E 's/_1\.[^.]+(\.gz)?$//')
        # If not removed, try more general truncation: take part before last _1
        if [ "$base" = "$(basename "$R1")" ]; then
            base=$(basename "$R1" | sed -E 's/_1\..*$//')
        fi
    else
        base=$(basename "$SINGLE" | sed -E 's/\.[^.]+(\.gz)?$//')
        base=$(basename "$base" | sed -E 's/\.fq$//')
    fi
    echo "Auto-extracted prefix: $base"
fi

# ---------- Define SPAdes output path ----------
spades_out="$OUTDIR/02spades_out/$base"

# ---------- Check if already processed (skip if scaffolds.fasta exists) ----------
if [ -f "$spades_out/scaffolds.fasta" ] && [ -s "$spades_out/scaffolds.fasta" ]; then
    echo "================================="
    echo "Sample $base already processed (scaffolds.fasta exists)."
    echo "Assembly results: $spades_out"
    echo "Skipping QC and assembly for this sample."
    echo "================================="
    exit 0
fi

# ---------- Create output subdirectories ----------
mkdir -p "$OUTDIR/01fastp_report"
mkdir -p "$OUTDIR/01fastp_cleanData"
mkdir -p "$OUTDIR/02spades_out"

# ---------- 1. Fastp QC ----------
echo "Running quality control..."
if [ "$MODE" = "PE" ]; then
    fastp -j "$OUTDIR/01fastp_report/${base}.fastp.json" \
          -h "$OUTDIR/01fastp_report/${base}.fastp.html" \
          -c -3 -W 4 --thread "$THREADS" \
          --in1 "$R1" --in2 "$R2" \
          --out1 "$OUTDIR/01fastp_cleanData/${base}.1.c.fastq.gz" \
          --out2 "$OUTDIR/01fastp_cleanData/${base}.2.c.fastq.gz" \
          --detect_adapter_for_pe \
          --compression 6
else
    fastp -j "$OUTDIR/01fastp_report/${base}.fastp.json" \
          -h "$OUTDIR/01fastp_report/${base}.fastp.html" \
          -c --thread "$THREADS" \
          --in1 "$SINGLE" \
          --out1 "$OUTDIR/01fastp_cleanData/${base}.c.fastq.gz" \
          --detect_adapter_for_se \
          --compression 6
fi

# ---------- 2. SPAdes assembly ----------
echo "运行 SPAdes 进行组装..."
mkdir -p "$spades_out"

if [ "$MODE" = "PE" ]; then
    spades.py -1 "$OUTDIR/01fastp_cleanData/${base}.1.c.fastq.gz" \
              -2 "$OUTDIR/01fastp_cleanData/${base}.2.c.fastq.gz" \
              -t "$THREADS" -m "$MEMORY" \
              --isolate \
              -k auto \
              -o "$spades_out"
else
    spades.py -s "$OUTDIR/01fastp_cleanData/${base}.c.fastq.gz" \
              -t "$THREADS" -m "$MEMORY" \
              --isolate \
              -k auto \
              -o "$spades_out"
fi

echo "================================="
echo "Sample $base processing complete!"
echo "QC report: $OUTDIR/01fastp_report/"
echo "Cleaned data: $OUTDIR/01fastp_cleanData/"
echo "Assembly results: $spades_out"
echo "================================="
