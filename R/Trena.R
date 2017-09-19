.Trena <- setClass ("Trena",
                    representation = representation(
                        genomeName="character")
                        )
#------------------------------------------------------------------------------------------------------------------------
setGeneric('getRegulatoryChromosomalRegions',  signature='obj',
           function(obj, chromosome, chromStart, chromEnd, regulatoryRegionSources, targetGene, targetGeneTSS,
                    combine=FALSE, quiet=FALSE) standardGeneric("getRegulatoryChromosomalRegions"))


setGeneric('getRegulatoryTableColumnNames',  signature='obj', function(obj) standardGeneric ('getRegulatoryTableColumnNames'))
setGeneric('getGeneModelTableColumnNames',  signature='obj', function(obj) standardGeneric ('getGeneModelTableColumnNames'))
setGeneric('createGeneModel', signature='obj', function(obj, targetGene,  solverNames, tbl.regulatoryRegions, mtx)
              standardGeneric('createGeneModel'))
setGeneric('expandRegulatoryRegionsTableByTF', signature='obj', function(obj, tbl.reg) standardGeneric('expandRegulatoryRegionsTableByTF'))
#setGeneric('addGeneModelLayout', signature='obj', function(obj, g, xPos.span=1500) standardGeneric('addGeneModelLayout'))
setGeneric('assessSnp', signature='obj', function(obj, pfms, variant, shoulder, pwmMatchMinimumAsPercentage, genomeName="hg38")
              standardGeneric('assessSnp'))
#------------------------------------------------------------------------------------------------------------------------
# a temporary hack: some constants
genome.db.uri <- "postgres://bddsrds.globusgenomics.org/hg38"   # has gtf and motifsgenes tables
#------------------------------------------------------------------------------------------------------------------------
Trena = function(genomeName, quiet=TRUE)
{
   stopifnot(genomeName %in% c("hg19", "hg38", "mm10"))

   obj <- .Trena(genomeName=genomeName)

   obj

} # constructor
#------------------------------------------------------------------------------------------------------------------------
setMethod('getRegulatoryTableColumnNames', 'Trena',

      function(obj){
         c("chrom", "motifStart", "motifEnd", "motifName", "strand", "score", "length", "distance.from.tss", "id", "tf")
         })

#------------------------------------------------------------------------------------------------------------------------
setMethod('getGeneModelTableColumnNames', 'Trena',

      function(obj){
         c("tf", "randomForest", "pearson", "spearman", "betaLasso", "pcaMax", "concordance")
         })

#------------------------------------------------------------------------------------------------------------------------
.callFootprintFilter <- function(obj, source, chromosome, chromStart, chromEnd, targetGene, targetGeneTSS)
{
    chromLocString <- sprintf("%s:%d-%d", chromosome, chromStart, chromEnd)
    fpFilter <- FootprintFilter(genome.db.uri, source,  geneCenteredSpec=list(), regionsSpec=chromLocString)
    x.fp <- getCandidates(fpFilter)
    tbl.fp <- x.fp$tbl
    if(nrow(tbl.fp) == 0){
       warn("no footprints found in %s:%d-%d, targetGene is %s", chromosome, chromeStart, chromEnd, targetGene);
       return(tbl.fp)
       }

    colnames(tbl.fp) <- c("chrom", "motifStart", "motifEnd", "motifName", "length", "strand", "score1", "score", "score3", "tf")

    distance <- tbl.fp$motifStart - targetGeneTSS
    direction <- rep("upstream", length(distance))
    direction[which(distance < 0)] <- "downstream"
    tbl.fp$distance.from.tss <- distance
    tbl.fp$id <- sprintf("%s.fp.%s.%06d.%s", targetGene, direction, abs(distance), tbl.fp$motifName)
    tbl.fp <- tbl.fp[, getRegulatoryTableColumnNames(obj)]

    tbl.fp

} # .callFootprintFilter
#------------------------------------------------------------------------------------------------------------------------
.callHumanDHSFilter <- function(obj, chromosome, chromStart, chromEnd, targetGene, targetGeneTSS)
{
    printf("--- in .callHumanDHS")
    chromLocString <- sprintf("%s:%d-%d", chromosome, chromStart, chromEnd)
    dhsFilter <- HumanDHSFilter(genome="hg38",
                                encodeTableName="wgEncodeRegDnaseClustered",
                                pwmMatchPercentageThreshold=85L,
                                geneInfoDatabase.uri=genome.db.uri,
                                geneCenteredSpec=list(),
                                regionsSpec=chromLocString)

    x.dhs <- getCandidates(dhsFilter)

    if(all(is.na(x.dhs))){
       return(data.frame())
       }

    tbl.dhs <- x.dhs$tbl
    tbl.dhs$length <- nchar(tbl.dhs$match)
    distance <- tbl.dhs$motifStart - targetGeneTSS
    direction <- rep("upstream", length(distance))
    direction[which(distance < 0)] <- "downstream"

    colnames(tbl.dhs)[grep("motifRelativeScore", colnames(tbl.dhs))] <- "score"
    colnames(tbl.dhs)[grep("tfs", colnames(tbl.dhs))] <- "tf"
    tbl.dhs$distance.from.tss <- distance
    tbl.dhs$id <- sprintf("%s.dhs.%s.%06d.%s", targetGene, direction, abs(distance), tbl.dhs$motifName)

    tbl.dhs <- tbl.dhs[, getRegulatoryTableColumnNames(obj)]

    tbl.dhs

} # .callHumanDHSFilter
#------------------------------------------------------------------------------------------------------------------------
setMethod('getRegulatoryChromosomalRegions', 'Trena',

    function(obj, chromosome, chromStart, chromEnd, regulatoryRegionSources, targetGene, targetGeneTSS,
             combine=FALSE, quiet=FALSE){

         tbl.combined <- data.frame()
         result <- list()
           # some bookeeeping to permit duplicate sources, useful only in testing
         source.count <- 0
         all.source.names <- regulatoryRegionSources

         encodeDHS.source.index <- grep("encodeHumanDHS", regulatoryRegionSources)

         if(length(encodeDHS.source.index)){
            source.count <- source.count + 1
            regulatoryRegionSources <- regulatoryRegionSources[-encodeDHS.source.index]
            if(!quiet) printf("about to callHumanDHSFilter");
            tbl.dhs <- .callHumanDHSFilter(obj, chromosome, chromStart, chromEnd, targetGene, targetGeneTSS)
            result[[source.count]] <- tbl.dhs
            if(combine)
               tbl.combined <- rbind(tbl.combined, tbl.dhs)
            } # if encode DSH source requested


         for(source in regulatoryRegionSources){
            source.count <- source.count + 1
            if(!quiet) printf("about to call footprintFilter with source = '%s'", source);
            tbl.fp <- .callFootprintFilter(obj, source, chromosome, chromStart, chromEnd, targetGene, targetGeneTSS)
            if(combine)
               tbl.combined <- rbind(tbl.combined, tbl.fp)
            result[[source.count]] <- tbl.fp
            } # for source
         names(result) <- all.source.names
         if(combine)
            result[["all"]] <- tbl.combined
         result
         }) # getRegulatoryChromosomalRegions

#------------------------------------------------------------------------------------------------------------------------
setMethod('expandRegulatoryRegionsTableByTF', 'Trena',

     function(obj, tbl.reg){
        tbl.trimmed <- subset(tbl.reg, nchar(tf) != 0)
        tfs.split <- strsplit(tbl.trimmed$tf, ";")
        #length(tfs.split) # [1] 36929
        counts <- unlist(lapply(tfs.split, length))
        tfs.split.vec <- unlist(tfs.split)
        tbl.expanded <- expandRows(tbl.trimmed, counts, count.is.col=FALSE, drop=FALSE)
        stopifnot(length(tfs.split.vec) == nrow(tbl.expanded))
        tbl.expanded$tf <- tfs.split.vec
        tbl.expanded
        }) # expandRegulatoryRegionsTableByTF

#------------------------------------------------------------------------------------------------------------------------
setMethod('createGeneModel', 'Trena',

      function(obj, targetGene, solverNames, tbl.regulatoryRegions, mtx){

         stopifnot("geneSymbol" %in% colnames(tbl.regulatoryRegions))
         unique.tfs.from.regulatory.regions <- unique(tbl.regulatoryRegions$geneSymbol)
         tfs <- intersect(unique.tfs.from.regulatory.regions, rownames(mtx))
         printf("tf candidate count, in mtx, in tbl.regulatory.regions: %d/%d", length(tfs),
                length(unique.tfs.from.regulatory.regions))

         solver <- EnsembleSolver(mtx, targetGene=targetGene, candidateRegulators=tfs, solverNames)
         tbl.model <- run(solver)
         tbl.model
      }) # createGeneModel

#------------------------------------------------------------------------------------------------------------------------
setMethod('assessSnp', 'TrenaUtils',

     function(obj, pfms=list(), variant, shoulder, pwmMatchMinimumAsPercentage, genomeName="hg38"){

        motifMatcher <- MotifMatcher(name=variant, genomeName=genomeName, pfms=pfms, quiet=TRUE)
        tbl.variant <- trena:::.parseVariantString(motifMatcher, variant)
        tbl.regions <- data.frame(chrom=tbl.variant$chrom,
                                  start=tbl.variant$loc-shoulder,
                                  end=tbl.variant$loc+shoulder,
                                  stringsAsFactors=FALSE)
        x.wt  <- findMatchesByChromosomalRegion(motifMatcher, tbl.regions,
                                                pwmMatchMinimumAsPercentage=pwmMatchMinimumAsPercentage)
        if(nrow(x.wt$tbl) == 0){
           warning(sprintf("no motifs found in reference sequence in neighborhood of %s with shoulder %d",
                           variant, shoulder))
           return(data.frame())
           }


        x.mut <- findMatchesByChromosomalRegion(motifMatcher, tbl.regions,
                                                pwmMatchMinimumAsPercentage=pwmMatchMinimumAsPercentage,
                                                variant=variant)



        if(nrow(x.mut$tbl) == 0){
           warning(sprintf("no motifs altered by %s with shoulder %d", variant, shoulder))
           return(data.frame())
           }

        tbl.wt.50 <- findMatchesByChromosomalRegion(motifMatcher, tbl.regions, 50)$tbl
        tbl.wt.50$signature <- sprintf("%s;%s;%s", tbl.wt.50$motifName, tbl.wt.50$motifStart, tbl.wt.50$strand)
        tbl.mut.50 <- findMatchesByChromosomalRegion(motifMatcher, tbl.regions, 50, variant=variant)$tbl
        tbl.mut.50$signature <- sprintf("%s;%s;%s", tbl.mut.50$motifName, tbl.mut.50$motifStart, tbl.mut.50$strand)

        tbl <- rbind(x.wt$tbl[, c(1,12, 2,3,4,5,7,8,13)], x.mut$tbl[, c(1,12, 2,3,4,5,7,8,13)])
        tbl <- tbl[order(tbl$motifName, tbl$motifRelativeScore, decreasing=TRUE),]
        tbl$signature <- sprintf("%s;%s;%s", tbl$motifName, tbl$motifStart, tbl$strand)
        tbl <- tbl [, c(1,2,10,3:9)]

        signatures.in.both <- intersect(subset(tbl, status=="mut")$signature, subset(tbl, status=="wt")$signature)
        signatures.only.in.wt <- setdiff(subset(tbl, status=="wt")$signature, subset(tbl, status=="mut")$signature)
        signatures.only.in.mut <- setdiff(subset(tbl, status=="mut")$signature, subset(tbl, status=="wt")$signature)

        tbl$assessed <- rep("failed", nrow(tbl))

        if(length(signatures.in.both) > 0) {
           indices <- sort(unlist(lapply(signatures.in.both, function(sig) grep(sig, tbl$signature))))
           tbl$assessed[indices] <- "in.both"
           }

        if(length(signatures.only.in.wt) > 0) {
           indices <- sort(unlist(lapply(signatures.only.in.wt, function(sig) grep(sig, tbl$signature))))
           tbl$assessed[indices] <- "wt.only"
           }

        if(length(signatures.only.in.mut) > 0) {
           indices <- sort(unlist(lapply(signatures.only.in.mut, function(sig) grep(sig, tbl$signature))))
           tbl$assessed[indices] <- "mut.only"
           }

        tbl$delta <- 0

           # find the mut scores for each of the "wt.only" entries, subtract from the wt score
        tbl.wt.only  <- subset(tbl, assessed=="wt.only", select=c(signature, motifRelativeScore))
        if(nrow(tbl.wt.only) > 0){
           sigs <- tbl.wt.only$signature
           tbl.mut.scores <- subset(tbl.mut.50, signature %in% sigs, select=c(signature, motifRelativeScore))
           deltas <- unlist(lapply(sigs, function(sig){wt.score  <- subset(tbl.wt.only, signature==sig)$motifRelativeScore;
                                                mut.score <- subset(tbl.mut.scores, signature==sig)$motifRelativeScore;
                                                delta <- wt.score - mut.score
                                                }))
           tbl$delta[match(sigs, tbl$signature)] <- deltas
           } # if some wt.only entries

           # find the wt scores for each of the "mut.only" entries, subtract from the mut score
        tbl.mut.only  <- subset(tbl, assessed=="mut.only", select=c(signature, motifRelativeScore))
        sigs <- tbl.mut.only$signature
        tbl.wt.scores <- subset(tbl.wt.50, signature %in% sigs, select=c(signature, motifRelativeScore))
        deltas <- unlist(lapply(sigs, function(sig){mut.score  <- subset(tbl.mut.only, signature==sig)$motifRelativeScore;
                                                    wt.score <- subset(tbl.wt.scores, signature==sig)$motifRelativeScore;
                                                    delta <- wt.score - mut.score
                                                 }))
        tbl$delta[match(sigs, tbl$signature)] <- deltas
        coi <-  c("motifName", "status", "assessed", "motifRelativeScore", "delta",
                  "signature", "chrom", "motifStart", "motifEnd", "strand",
                  "match", "tf")

        tbl <- tbl[, coi]
        tbl$variant <- variant
        tbl
        }) # assessSnp

#------------------------------------------------------------------------------------------------------------------------