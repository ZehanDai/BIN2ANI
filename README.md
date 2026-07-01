# Bin2ANI: From Binned Genomes to Average Nucleotide Identity

## Description
A general-purpose pipeline for species-level identification of metagenome-assembled genomes
It takes raw mNGS/WGS fastq as input, performs de novo assembly, binning into metagenome-assembled genomes (MAGs), and ANI-based comparison against the reference set. For each bin, the pipeline reports the closest matching reference genome along with its ANI value.

Theoretically, when the reference database is comprehensive, bins that fall below the accepted species boundary (e.g., ANI < 95%) can be flagged as potential novel species candidates. 

## Dependencies
* fastp (v0.23.4) – quality control and adapter trimming
* SPAdes (v4.3.0) – de novo assembly
* MetaBAT2 (v20260625_113535) – binning of assembled contigs
* HISAT2 (v2.2.1) – read mapping to scaffolds
* fastANI (v1.33) – average nucleotide identity calculation
Optionally 
* CheckM v1.25
Additionally, checkM requires HMMER (≥3.1b1), Prodigal (≥2.60), and pplacer (≥1.1) .


## Usage
./pipe.sh -1 <R1.fq.gz> -2 <R2.fq.gz> -r <reference_genome_dir> [options]

Required:
  -1    R1 read file (gzip compressed)
  -2    R2 read file (gzip compressed)
  -r    Reference genome directory (for fastANI comparison, contains .fna/.fa files)

Optional:
  -o    Output root directory (default: ./pipeline_output)
  -t    Number of threads (default: 8)
  -h    Show this help


## Testing 
Following is a case using a Shiella WGS data SRR7291905
(require SRAtools v3.4.1 and ncbi-genome-download v0.3.3)

### Downloading test WGS data
```
> prefetch -c SRR7291905
> fasterq-dump SRR7291905 -O SRR7291905/
> ls ./SRR7291905
SRR7291905.sra  SRR7291905_1.fastq  SRR7291905_2.fastq
> cd ./SRR7291905
> gzip SRR7291905*.fastq # optional
```

### Prepare a reference genome accession list
Given a file containing the assembly accession IDs of the reference genomes
```
> cat acc.lst
GCF_008727215.1
GCF_002968215.1
GCF_002949495.1
GCF_963281075.1
GCF_000012025.1
```

### Download reference genomes
Use ncbi-genome-download to fetch the corresponding FASTA files from GenBank:
```
refd=ref_genbank_genome
mkdir -p $refd
ncbi-genome-download --flat-output --section genbank --formats fasta \
         -o "$refd" -A acc.lst "bacteria"
```
This will place all .fna.gz (or .fa.gz) files directly inside $refd.

### Run the pipeline
Set the input paths and output directory, then execute the main script:
```
# path to reference (whole genome fasta)
refd=ref_genbank_genome

# path to query (fastq files)
fq1=SRR7291905/SRR7291905_1.fastq.gz
fq2=SRR7291905/SRR7291905_2.fastq.gz
oud=~/pipeline_output

bash ./pipe.sh -1 $fq1 -2 $fq2 -r $refd -o $oud
```

### Integrating checkM and fastANI output (Optional) 
A supplementary python3 script file `annotate_ani.py` was provided udner `utils/`, which could assist in merging fastANI output with optional CheckM metrics (completeness and contamination). Given a NCBI Genome database TSV (e.g., `shigella_ncbi_GenomeDatabase.tsv`), it also adds taxonomic annotations (species, strain, etc.) to the fastANI results.


