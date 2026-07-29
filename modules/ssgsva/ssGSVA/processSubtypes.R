getCorData <- function(m, sub = NULL){
  if(!is.null(sub)){
    return(dplyr::select(as.data.frame(t(m)), any_of(sub)))
  } else{
    return(as.data.frame(t(m)))
  }
}
buildESDF <- function(rds.file, subset){
  enrichment.scores <- readRDS(rds.file)
  
  es.df <- getCorData(enrichment.scores, sub = subset)
  
  return(es.df)
}
getSubset <- function(p, n){
  return(as.vector(n[grep(pattern = p, n)]))
}
main <- function(fpath, subset){
  rds.files <- list.files(path = fpath,pattern = "\\.RDS$", full.names = TRUE)
  
  if(length(rds.files) > 1){
    enrichment.scores <- list()
    es.df             <- list()
    
    for(i in seq_along(rds.files)){
      fname          <- pipecore::getFileName(rds.files[i])
      es.df[[fname]] <- buildESDF(rds.files[i], subset = subset)
      
    }
    
    es.df <- Reduce(cbind, es.df)
    res <- data.frame("SampleID" = rownames(es.df), es.df)
    
  } else if(length(rds.files) == 1){
    if(!is.null(subset)){
      es.df <- buildESDF(rds.files[1], subset = subset)
    } else{
      es.df <- buildESDF(rds.files[1], subset = NULL)
    }
    
    res   <- data.frame("SampleID" = rownames(es.df), es.df)
  } else{
    stop("Missing an enrichment score table. Please provide at least one enrichment score table to subset!")
  }
  
  outfolder <- here::here(fpath)
  write.csv(res, here::here(outfolder, "esdf.csv"), row.names = F)
  
  print("Done!")
}

#---- Check Packages ----
pkgs <- c("here", "docopt")
pipecore::handleRequirements(pkgs)

#---- Header ----
"Mesothelioma AI Pipeline - Building the Correlations DF

Usage: survival_analysis.R [options]

Options:
  -h --help                     Show this screen.
  -e --enrichment_scores=<PATH> Path to the enrichment scores data frame folder.
  -s --subset=<PATH>            A .txt file that specifies what subset of ES to select.
"-> doc

#---- Flag Arguments ----
arguments <- docopt(doc, quoted_args = TRUE, help = TRUE)
print(arguments)

fpath <- normalizePath(arguments$enrichment_scores, winslash = "/", mustWork = FALSE)

if(arguments$subset == "NULL"){
  subset <- NULL
} else{
  subset <- unlist(strsplit(readLines(arguments$subset), ",\\s*"))
}


#---- Main ----
main(fpath, subset)

