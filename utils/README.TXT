The 01qc_assembly, 02run_mapping, 03binning, and 04run_fastANI scripts handle different tasks.
The shigella_ncbi_GenomeDatabase.tsv is a table exported from the NCBI Genome database, containing assembly accession IDs and related information.
* The annotate_ani.py is a helper script to match binning results with genome and CheckM information.
Example usage: python annotate_ani.py -a ~/pipeline_output/ani/LYYN-ref.ANI.txt \
                       -t ~/utils/shigella_ncbi_GenomeDatabase.tsv \
                       -c ~/pipeline_output/checkm \
                       -o annotated_ani.tsv
The annotated_ani.tsv is an example output generated through running annotate_ani.py.
