% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/FootprintFilter.R
\docType{class}
\name{FootprintFilter-class}
\alias{FootprintFilter-class}
\alias{.FootprintFilter}
\alias{FootprintFilter}
\title{Create a FootprintFilter object}
\usage{
FootprintFilter(genomeDB, footprintDB, regions = data.frame(), quiet = TRUE)
}
\arguments{
\item{genomeDB}{A connection to a database that contains genome information}

\item{footprintDB}{A connection to a database that contains footprint information}

\item{regions}{A data frame that specifies the regions of interest
(default = data.frame())}

\item{quiet}{A logical denoting whether or not the filter should print output}
}
\value{
An object of the FootprintFilter class
}
\description{
A FootprintFilter object allows for filtering based on gene footprinting databases. Using its
associated \code{getCandidates} method and URIs for both a genome database and project database,
a FootprintFilter object can be used to filter a list of possible transcription factors to those
that match footprint motifs for a supplied target gene.
}
\examples{
\dontrun{
   load(system.file(package="trena", "extdata/ampAD.154genes.mef2cTFs.278samples.RData"))
   db.address <- system.file(package="trena", "extdata")
   genome.db.uri <- paste("sqlite:/",db.address,"mef2c.neighborhood.hg38.gtfAnnotation.db", sep = "/")
   project.db.uri <- paste("sqlite:/",db.address,"mef2c.neigborhood.hg38.footprints.db", sep = "/")
   target.gene <- "MEF2C"
   size.upstream <- 1000
   size.downstream <- 1000

      # Construct a Trena object and use it to retrive the regions
   trena <- Trena("hg38")
   regions <- getProximalPromoter(trena,target.gene, size.upstream, size.downstream)

   footprint.filter <- FootprintFilter(genomeDB = genome.db.uri, footprintDB = project.db.uri,
                                       regions = regions)
   }
}
\seealso{
\code{\link{getCandidates-FootprintFilter}}

Other Filtering Objects: 
\code{\link{VarianceFilter-class}}
}
\concept{Filtering Objects}
