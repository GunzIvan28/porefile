#!/usr/bin/env nextflow

params.fq = "$baseDir/data/*.fastq"
params.silvaDir = "$baseDir/silva"
params.downloadSilvaFiles = false
params.outdir = "results"
//params.cpus = 4
params.minimap2 = false
params.last = false
params.keepmaf = false
params.stoptocheckparams = false
params.nanofilt_quality = 8
params.nanofilt_maxlength = 1500
params.megan_lcaAlgorithm = "naive"
params.megan_lcaCoveragePercent = 100
params.help = false



nextflow.preview.dsl = 2



def helpMessage() {
    log.info """
    --------------------------
    ---> Long16S Pipeline <---
    --------------------------
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run iferres/long16S --fq 'data/*.fastq' --cpus 4 -profile local

    Note:
    SILVA and MEGAN databases are must be provided. Provide those parameters between quotes.

    Mandatory arguments:
        --fq                          Path to input data (must be surrounded with quotes).
        -profile                      Configuration profile to use. Available: local, nagual.

    Other:
        --cpus                        The max number of cpus to use on each process (Default: 4).
        --stoptocheckparams           Whether to stop after Summary process to check parameters. Default: false.
                                      If true, then the pipeline stops to allow user to check parameters. If
                                      everything is ok, then this parameter should be set to false, and resumed
                                      by using the -resume flag. Previous steps will be cached. If some params
                                      are modified, then those processes affected by them and their dependant
                                      processes will be re run.
        --nanofilt_quality            The '--quality' parameter of NanoFilt. Default: 8.
        --nanofilt_maxlength          The '--maxlength' parameter of NanoFilt. Default: 1500.
        --megan_lcaAlgorithm          The '--lcaAlgorithm' parameter of daa-meganizer (MEGAN). Default: naive.
        --megan_lcaCoveragePercent    The '--lcaCoveragePercent' parameter of daa-meganizer (MEGAN). Default: 100.

    Authors: Cecilia Salazar (csalazar@pasteur.edu.uy) & Ignacio Ferres (iferres@pasteur.edu.uy)
    Maintainer: Ignacio Ferres (iferres@pasteur.edu.uy)

    Microbial Genomics Laboratory
    Institut Pasteur de Montevideo (Uruguay)

    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}


// include modules
include Concatenate from './modules/processes'
include Demultiplex from './modules/processes'
include Filter from './modules/processes'
include NanoPlotNoFilt from './modules/processes'
include NanoPlotFilt from './modules/processes'
include SummaryTable from './modules/processes'
include ComputeComparison from './modules/processes'
include ExtractOtuTable from './modules/processes'

// include sub-workflows
include {DownloadSilva} from './workflows/Download'
include {LastWorkflow} from './workflows/Last'
include {Minimap2Workflow} from './workflows/Minimap2'

workflow {
  if ( params.downloadSilvaFiles ){
    DownloadSilva()
    DownloadSilva.out.fasta
      .set{ silva_fasta_ch }
    DownloadSilva.out.acctax
      .set{ silva_acctax_ch }
  } /*else {
    Channel.fromPath( "${params.silvaDir}" )
      .set{ raw_silva_ch }
  }*/
  Channel.fromPath(params.fq)
    .set{ fqs_ch }
  Concatenate( fqs_ch.collect() )
  Demultiplex( Concatenate.out )
  Demultiplex.out
    .flatten()
    .map { file -> tuple(file.baseName, file) }
    .set{ barcode_ch }
  Filter( barcode_ch )
  Filter.out
    .set{ filtered_ch }
  NanoPlotNoFilt( barcode_ch )
  NanoPlotFilt( Filter.out )
  NanoPlotNoFilt.out.counts
    .mix( NanoPlotFilt.out.counts )
    .set{ counts_ch }
  SummaryTable( counts_ch.collect() )
  if ( params.minimap2 ) {
    Minimap2Workflow( filtered_ch, silva_fasta_ch, silva_acctax_ch )
    Minimap2Workflow.out
      .set{ to_compare_ch }
  } else if ( params.last ) {
    LastWorkflow( filtered_ch, silva_fasta_ch, silva_acctax_ch )
    LastWorkflow.out
      .set{ to_compare_ch }
  }
  ComputeComparison( to_compare_ch.collect() )
  ExtractOtuTable( ComputeComparison.out )
}
