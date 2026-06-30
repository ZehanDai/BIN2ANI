#!/usr/bin/env python3
"""
Usage:
  annotate_ani.py -a <ani.txt> -t <ncbi_table.tsv> [-o <output>]
  annotate_ani.py -a <ani.txt> -c <checkm_dir> [-o <output>]
  annotate_ani.py -a <ani.txt> -t <ncbi_table.tsv> -c <checkm_dir> [-o <output>]
"""

import sys, os, re, argparse
from collections import defaultdict

def parse_ncbi_table(table_file):
    mapping = {}
    with open(table_file) as f:
        header = f.readline().rstrip('\n').split('\t')
        # find indices by name, fallback to positions
        acc_idx = header.index("Assembly Accession") if "Assembly Accession" in header else 1
        org_idx = header.index("Organism Name") if "Organism Name" in header else 3
        strain_idx = header.index("Organism Infraspecific Names Strain") if "Organism Infraspecific Names Strain" in header else 5
        for line in f:
            cols = line.rstrip('\n').split('\t')
            if len(cols) <= max(acc_idx, org_idx, strain_idx): continue
            acc = cols[acc_idx].strip()
            org = cols[org_idx].strip()
            strain = cols[strain_idx].strip()
            mapping[acc] = (org, strain)
    return mapping

def parse_checkm_stats(checkm_dir):
    summary_file = os.path.join(checkm_dir, "checkm_summary.tsv")
    if not os.path.isfile(summary_file):
        sys.stderr.write(f"Warning: {summary_file} not found.\n")
        return {}
    stats = {}
    with open(summary_file) as f:
        lines = f.readlines()
    # Find data lines: lines that start with "  bin." or "bin." after stripping spaces
    data_started = False
    for line in lines:
        line = line.rstrip('\n')
        if line.startswith('[') or line.startswith('---') or not line.strip():
            continue
        # skip header lines, look for data lines
        if 'Bin Id' in line:
            # skip header
            continue
        # Check if line starts with bin. (possibly with leading spaces)
        if re.match(r'\s*bin\.\d+', line):
            tokens = re.split(r'\s+', line.strip())
            # tokens: ['bin.1', 'f__Enterobacteriaceae', '(UID5167)', '82', ..., '93.96', '0.11', '0.00']
            # we need last three: completeness, contamination, strain_heterogeneity
            if len(tokens) >= 3:
                try:
                    comp = float(tokens[-3])
                    cont = float(tokens[-2])
                    strain_het = float(tokens[-1])
                    bin_id = tokens[0]
                    stats[bin_id] = {
                        'completeness': comp,
                        'contamination': cont,
                        'strain_heterogeneity': strain_het
                    }
                except ValueError:
                    pass
    return stats

def extract_accession(ref_path):
    basename = os.path.basename(ref_path)
    parts = basename.split('_')
    if parts[0].startswith(('GCA_', 'GCF_')):
        return parts[0]
    if len(parts) >= 2 and re.match(r'GCA_\d+\.\d+', parts[0] + '_' + parts[1]):
        return parts[0] + '_' + parts[1]
    return basename

def main():
    parser = argparse.ArgumentParser(description="Annotate ANI results with species/lineage info and CheckM stats.")
    parser.add_argument('-a', '--ani', required=True, help='ANI result file')
    parser.add_argument('-t', '--table', help='NCBI genome database TSV')
    parser.add_argument('-c', '--checkm', help='CheckM output directory')
    parser.add_argument('-o', '--output', help='Output file (default: <ani>.annotated.txt)')
    args = parser.parse_args()
    if not args.table and not args.checkm:
        sys.exit("Error: Must provide either --table or --checkm (or both).")

    ncbi_map = {}
    if args.table:
        ncbi_map = parse_ncbi_table(args.table)
    checkm_stats = {}
    if args.checkm:
        checkm_stats = parse_checkm_stats(args.checkm)

    out_file = args.output or args.ani + '.annotated.txt'
    with open(args.ani) as fin, open(out_file, 'w') as fout:
        # write header
        header_fields = ["Bin", "Ref_file", "ANI", "Fragments_hit", "Total_fragments"]
        if ncbi_map:
            header_fields.extend(["Ref_species", "Ref_strain"])
        if checkm_stats:
            header_fields.extend(["CheckM_completeness", "CheckM_contamination", "CheckM_strain_heterogeneity"])
        fout.write("\t".join(header_fields) + "\n")

        for line in fin:
            line = line.rstrip('\n')
            if not line:
                continue
            cols = line.split('\t')
            if len(cols) < 5:
                continue
            bin_file, ref_path, ani, hits, total = cols[:5]
            out_cols = [bin_file, ref_path, ani, hits, total]

            if ncbi_map:
                acc = extract_accession(ref_path)
                org, strain = ncbi_map.get(acc, ("Unknown", ""))
                out_cols.extend([org, strain])

            if checkm_stats:
                bin_id = os.path.basename(bin_file).replace('.fa', '')
                stats = checkm_stats.get(bin_id, {})
                comp = str(stats.get('completeness', ''))
                cont = str(stats.get('contamination', ''))
                het = str(stats.get('strain_heterogeneity', ''))
                out_cols.extend([comp, cont, het])

            fout.write("\t".join(out_cols) + "\n")
    print(f"Annotated file written to: {out_file}")

if __name__ == "__main__":
    main()