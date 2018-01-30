#' @import rlang
#' @import purrr
#' @import tidyr
#' @import plyr
#' @import dplyr
#' @import stringr
#' @import phyloseq
#' @import ggplot2
#' @import shiny
#' @import plotly
#' @import utils
#' @import data.table
#' @import shinyjs

#' @title TaxID to Species
#'
#' Transforms taxID to the corresponding Species name.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#' @param taxID
#'
#'
#' @return Species name
#' @export
taxids2names <-
  function(phylo, TaxID)
    phylo@tax_table[TaxID, "Species"]  %>% as.character

#' Deal with NAs
#'
#' Replaces NAs with the following: {Class}_NA. Class stands for the last known class of the corresponding OTU.
#'
#' @param tax_table A table obtained by \link[phyloseq]{tax_table}.
#'
#'
#' @return Modified tax table
#' @export
clean_tax_table <- function(tax_table) {
  tax_table <- as.data.frame(tax_table)
  tax_table[] <- lapply(tax_table, as.character)
  inds <- which(is.na(tax_table), arr.ind = T)
  inds1 <- aggregate(row ~ col, data = inds, list)
  # rownames(inds) <- inds$col
  # inds <- inds$row
  env <- environment()
  tmp <- tax_table
  levels <- apply(inds1, 1, function(x) {
    tbl <- tax_table[x$row, 1:(x$col - 1)]
    tbl <- as.data.frame(tbl)
    levels <- apply(tbl, 1, function(y) {
      y[max(which(!is.na(y)))]
    })
    levels
    # assign("tmp", tax_table, env)
  }) %>% unlist

  tax_table[inds] <- paste0(levels, "_NA")
  tax_table
}

#' DESeq2 table
#'
#' Performs differential expression analysis using DESeq2. If \code{cond1} and \code{cond2} are both NULL then all conditions are taken.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#' @param attribute Column name of the sample table, obtained from \link[phyloseq]{sam_data}.
#' @param cond1 first condition.
#' @param cond2 second condition.
#'
#'
#' @return DESeq2 table returned from \link[DESeq2]{results}.
#' @export
deseq2_table <- function(phylo,
                         attribute,
                         cond1 = NULL,
                         cond2 = NULL) {
  if (is.null(phylo))
    return(NULL)
  environment(subset_samples) <- environment()
  tmp <- phylo
  if (!is.null(cond1) && !is.null(cond2))
    tmp <-
    subset_samples(tmp, unlist(tmp@sam_data[, attribute]) %in% c(cond1, cond2))

  # Remove samples with NA
  tmp <- subset_samples(tmp,!is.na(tmp@sam_data[, attribute]))
  tmp <- prune_taxa(taxa_sums(tmp) > 0, tmp)
  # make valid condition names
  conds <- if (all(!is.null(cond1),!is.null(cond2))) {
    tmp1 <- setNames(list(1, 2), c(cond1, cond2))
    tmp1[unlist(tmp@sam_data[, attribute])]
  }  else{
    as.integer(factor(tmp@sam_data %>% data.frame %>% .[[attribute]]))
  }
  tmp@sam_data[, attribute] <-
    paste0("cond", conds)
  deseq <-
    phyloseq_to_deseq2(tmp, as.formula(paste("~", attribute)))
  size.factors <-
    log10(tmp@sam_data$Total.Reads) / median(log10(tmp@sam_data$Total.Reads))
  DESeq2::sizeFactors(deseq) <- size.factors
  de_table <-
    DESeq2::DESeq(deseq, test = "Wald", fitType = "local") %>%
    DESeq2::results(cooksCutoff = FALSE) %>%
    .[sort.list(.$padj), ] %>%
    as.data.frame
  # %>% mutate(pvalue = -log10(pvalue), padj = -log10(padj))
  de_table
}

# Function to get glm statistics for specific attribtute in respect to DE
de_glm_df <- function(phylo, taxids, attribute, cond1, cond2) {
  if (is.null(phylo))
    return(NULL)
  environment(subset_samples) <- environment()
  phylo <-
    subset_samples(phylo, unlist(phylo@sam_data[, attribute]) %in% c(cond1, cond2))

  lapply(taxids, function(x) {
    species_name <- taxids2names(phylo, x)
    phylo@otu_table[x, ] %>%
      t %>%
      cbind(phylo@sam_data[, c(attribute, "Total.Reads")]) %>%
      set_colnames(c("Transcript", attribute, "Total.Reads")) %>%
      # {View(.); .} %>%
      MASS::glm.nb(as.formula(paste(
        "Transcript ~", attribute, "+ Total.Reads"
      )), .) %>%
      summary %>%
      coefficients %>%
      subset(!rownames(.) %in% c("Total.Reads", "(Intercept)")) %>%
      t
    # %>% set_colnames(sapply(colnames(.), function(y) paste0(y,".", species_name)))
  }) %>% as.data.frame %>% t %>% set_rownames(sapply(taxids, function(x)
    taxids2names(phylo, x)))
}

#' Alpha Diversity test
#'
#' Perform an anova test on diversity analysis.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#' @param attribute Column name of the sample table, obtained from \link[phyloseq]{sam_data}.
#'
#'
#' @return P-value
#' @export
diversity_test <- function(phylo, attribute) {
  if (is.null(phylo))
    return(NULL)
  if (length(unique(phylo@sam_data[[attribute]])) < 2) {
    stop("There is only 1 condition!")
  }
  alpha.diversity <- estimate_richness(phylo, measures = "Shannon")
  data <- cbind(sample_data(phylo), alpha.diversity)
  anova <- aov(as.formula(paste("Shannon ~", attribute)), data)
  summary(anova)
  summary(anova)[[1]][, "Pr(>F)"][1]
}

#' Generate Phyloseq object
#'
#' Generates the phyloseq Object of a specific study.
#'
#' @param study study ID
#' @param counts Table with counts
#' @param sample_info Sample_info table
#' @param lineage lineage table generated by link{generateLineage}
#'
#'
#' @return phyloseq object
#' @export
generatePhylo <- function(study, counts, sample_info, lineage) {
  ok <- sample_info$study == study
  otu <-
    otu_table(round(as.data.table(counts)[, ok, with = F]), taxa_are_rows =
                TRUE)
  sam <- sample_data(sample_info[ok, ])
  rownames(sam) <- colnames(otu)
  tax <- tax_table(lineage)
  rownames(tax) <- rownames(otu)
  tmp <- phyloseq(otu, tax, sam)
  bla <-
    strsplit(sample_data(tmp)$sample_attribute, " || ", fixed = T)
  bla <- try(do.call(rbind.fill,
                     lapply(bla, function(x)
                       str_split(x, ": ", n = 2) %>%
                         data.frame(stringsAsFactors = F) %>%
                         {
                           colnames(.) <- .[1, ]
                           as.data.table(.)[2, ]
                         })))
  bla <-
    if (class(bla) == "try-error")
      data.frame(Attribute = rep(NA, ncol(otu_table(tmp))))
  else
    data.frame(bla)
  rownames(bla) <- colnames(otu_table(tmp))
  bla$`Total.Reads` <- sam$spots
  bla$Selection <- rep("Group_0", nrow(bla))
  # Add column to samples table, that refers to all the samples
  bla$All <- rep("All", nrow(bla))
  bla$sraID <- colnames(otu)
  sample_data(tmp) <- bla
  prune_taxa(taxa_sums(tmp) > 0, tmp)
}

#' Phyloseq attributes
#'
#' Get attributes from given phyloseq object.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#'
#'
#' @return character vector of attributes
#' @export
getAttributes <- function(phylo) {
  sapply(1:length(sample_data(phylo)),
         function(x) {
           if (nrow(unique(sample_data(phylo)[, x])) >= 2)
             return(colnames(phylo@sam_data)[x])
         }) %>% unlist
}

#' Load phyloseq
#'
#' Load phyloseq object into memory. Run first phyloseq_generator.r.
#'
#' @param dir directory of the data.
#' @param study study ID
#' @param envir enviroment to load phyloseq object
#'
#'
#' @export
loadPhylo <-
  function(study,
           dir = pkg_file("data"),
           envir = environment(loadPhylo)) {
    try(load(file.path(dir, "studies", paste0(study, ".RData")), envir))
  }

#' Generate Lineage
#'
#' Generates lineage table.
#'
#' @param feature_info table of features for OTUs
#'
#'
#' @return lineage table
#' @export
generateLineage <- function(feature_info) {
  lineage <-
    do.call(rbind, lapply(as.character(feature_info[, 'Lineage']), function(x)
      strsplit(x, ";", fixed = T)[[1]]))
  lineage <- cbind(lineage, as.character(feature_info[, 'Name']))
  lineage[which(lineage[, 1] == ''), 1] <- "Viruses"
  lineage[which(lineage == '')] <- NA
  colnames(lineage) <-
    c("Kingdom",
      "Phylum",
      "Class",
      "Order",
      "Family",
      "Genus",
      'Species')
  lineage
}

#' Make Sankey links table
#'
#' Creates a table with information about all the links from \code{source} to \code{target}.
#'     This table can be used to create a shankey plot.
#'
#' @param tax_table filtered tax table from a \link[phyloseq]{phyloseq} object
#' @param otu_table otu_table from a \link[phyloseq]{phyloseq} object
#' @param source \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")}
#' @param target \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")}
#' @param source_filter String to filter \code{source} values.
#' @param level_filter \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")}
#'
#' @return A data.frame with info about the links.
#' @export
makeSankey_links <-
  function(tax_table,
           otu_table,
           source,
           target,
           source_filter,
           level_filter) {
    group <- tax_table[, target]

    target_means <- rowsum(otu_table, group) %>% rowMeans() %>%
    {
      . / sum(.) * 100
    }

    # Filter tax_table
    if (!is.null(source_filter)) {
      if (is.null(level_filter))
        level_filter <- source
      tax_table <-
        filter(tax_table, tax_table[, level_filter] == source_filter)
    }

    links <-
      tax_table[, c(source, target)] %>% data.frame(stringsAsFactors = F) %>%
      distinct %>% setNames(c("Source", "Target")) %>%
      mutate(
        Value = target_means[.$Target],
        Source_level = rep(source, nrow(.)),
        Target_level = rep(target, nrow(.))
      ) %>%
      .[order(.$Value, decreasing = T),] %>% .[which(.$Value > 0.5),]

    links
  }

#' Metafeature mean relative abundance table
#'
#' Create a table of the mean relative abundance of each metafeature per study.
#'
#' @param study_info The table study_info
#' @param studies A vector of study IDs
#' @param dir The data directory
#'
#' @export
mfMeans <- function(study_info, studies, dir) {
  # use rbind.fill from plyr
  tbl <- lapply(studies, function(x) {
    loadPhylo(x, dir, environment())
    means <- relativeCounts(phylo) %>% apply(1, mean)
    names(means) <- taxids2names(phylo, names(means))
    as.data.frame(t(means))
  }) %>% rbind.fill %>% t
  colnames(tbl) <- studies
  tbl[which(tbl < 1)] <- NA
  tbl
}

#' Relative Counts
#'
#' Divides the counts of each samples by the total number of reads (including non-microbial reads) in each sample.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#'
#' @return A data frame of relative counts
#' @export
relativeCounts <- function(phylo) {
  otu_table <- data.frame(phylo@otu_table)
  readsPerSample <-
    phylo@sam_data[colnames(otu_table), "Total.Reads"] %>% t
  otu_table / readsPerSample[col(otu_table)] * 1e6
}
