#!/usr/bin/Rscript
## Author: Taylor Falk
## tfalk@bu.edu
## BU BF591
## Assignment Week 6

libs <- c("tidyverse", "ggVennDiagram", "BiocManager",
          "DESeq2", "edgeR", "limma")
# if you don't have a package installed, use BiocManager::install() or 
# install.packages(), as previously discussed.
for (package in libs) {
  suppressPackageStartupMessages(require(package, 
                                         quietly = T, 
                                         character.only = T))
  require(package, character.only = T)
}

#### load and filter ####
#' Load n' trim
#'
#' @param filename full file path as a string of the counts file 
#'
#' @return A _data frame_ with gene names as row names. A tibble will **not** work 
#' with the differential expression packages. The data frame is formatted as:
#' > head(counts_df)
#'                      vP0_1 vP0_2 vAd_1 vAd_2
#' ENSMUSG00000102693.2     0     0     0     0
#' ENSMUSG00000064842.3     0     0     0     0
#' 
#' @details As always, we need to load our data and start to shape it into the 
#' form we need for our analysis. Selects only the columns named "gene", "vP0_1", 
#' "vP0_2", "vAd_1", and "vAd_2" from the counts file. 
#'
#' @examples counts_df <- load_n_trim("/path/to/counts/verse_counts.tsv")
load_n_trim <- function(filename) {
  counts_data <- read.csv(filename, sep = "\t") 
  selected_data <- select(counts_data, "vP0_1", "vP0_2", "vAd_1", "vAd_2", "gene")
  selected_data <- selected_data %>% column_to_rownames(var = "gene")
  return(as.data.frame(selected_data))
}

#' Perform a DESeq2 analysis of rna seq data
#'
#' @param count_dataframe The data frame of gene names and counts.
#' @param coldata The coldata variable describing the experiment, a dataframe.
#' @param count_filter An arbitrary number of genes each row should contain or 
#' be excluded. DESeq2 suggests 10, but this could be customized while running. 
#' An integer.
#' @param condition_name A string identifying the comparison we are making. It 
#' follows the format "condition_[]_vs_[]". If I wanted to compare day4 and day7 
#' it would be "condition_day4_vs_day7".
#'
#' @return A dataframe of DESeq results. It has a header describing the 
#' condition, and 6 columns with genes as row names. 
#' @details This function is based on the DESeq2 User's Guide. These links describe 
#' the inputs and process we are working with. The output we are looking for comes 
#' from the DESeq2::results() function.
#' https://bioconductor.org/packages/release/bioc/vignettes/DESeq2/inst/doc/DESeq2.html#count-matrix-input
#' https://bioconductor.org/packages/release/bioc/vignettes/DESeq2/inst/doc/DESeq2.html#differential-expression-analysis
#'
#' @examples run_deseq(counts_df, coldata, 10, "condition_day4_vs_day7")
run_deseq <- function(count_dataframe, coldata, count_filter, condition_name) {
  
  dds_obj <- count_dataframe[rowSums(count_dataframe) >= count_filter, ]
  
  dds <- DESeqDataSetFromMatrix(countData = dds_obj,
                                colData = coldata,
                                design = ~condition)
  dds <- DESeq(dds)
  
  split_string <- unlist(strsplit(condition_name, "_"))
  condition_1 <- split_string[2]
  condition_2 <- split_string[4]
  
  res <- results(dds, contrast = c("condition", condition_1, condition_2))
  return(res)
}

#### edgeR ####
#' Perform an edgeR analysis of RNA seq data
#'
#' @param count_dataframe The same data frame of gene names and counts.
#' @param group Similar to the coldata, a simple data frame describing the 
#' experiment.
#'
#' @return A data frame with gene IDs for row names and three columns of data: 
#' logFC, logCPM, and PValue
#' @details EdgeR asks of us fewer inputs, so we can follow their workflow 
#' relatively easily. We followed the example in chapter 4.1, culminating in 4.1.8 
#' in this vignette:
#' https://bioconductor.org/packages/release/bioc/vignettes/edgeR/inst/doc/edgeRUsersGuide.pdf
#' After using estimateDisp(), you can return the correct results using exactTest().
#'
#' @examples run_edger(counts_df, group)
run_edger <- function(count_dataframe, group) {
  dge_data <- DGEList(counts = count_dataframe, group = group, remove.zeros = TRUE)
  keep <- filterByExpr(dge_data, group)
  dge_data <- dge_data[keep,,keep.lib.sizes = FALSE]  
  
  dge_data <- calcNormFactors(dge_data)
  dge_data <- estimateCommonDisp(dge_data)
  dge_data <- estimateTagwiseDisp(dge_data)
  
  test_res <- exactTest(dge_data)
  
  results_df <- data.frame(
     logFC = test_res$table$logFC,
     logCPM = rowMeans(cpm(dge_data)[rownames(test_res$table), ]),
     PValue = test_res$table$PValue
   )
  rownames(results_df) <- rownames(test_res$table)
  
  return(results_df)
}

 #### limma ####
#' Perform an analysis using Limma, with an mandatory voom component.
#'
#' @param count_dataframe The same dataframe as previous functions.
#' @param design A similar design data frame describing the experiment.
#'
#' @return A dataframe with gene IDs as row names and six columns, including logFC, 
#' P.Value, and adj.P.Val
#' @details As before, looking at the documentation will help determine what this 
#' function should do. The section of interest in the vignette is chapter 15.1 - 15.5:
#' http://bioconductor.org/packages/release/bioc/vignettes/limma/inst/doc/usersguide.pdf
#' 
#' Your limma implementation should follow the voom section as well. 
#' Your results can be returned with topTable() after 
#'
#' **Note** that topTable() does _not_ sort by default. You may want 
#' to read the help section on the `resort.by` parameter. We want the 
#' 1,000 smallest p-values.
#' 
#' @examples run_limma(counts_df, design, voom=TRUE)
run_limma <- function(counts_dataframe, design, group) {
  dge <- DGEList(counts = counts_dataframe, group = group)
  keep <- filterByExpr(dge, design)
  dge <- dge[keep,,keep.lib.sizes = FALSE]  
  
  v <- voom(dge, design = design, plot = FALSE)
  fit <- lmFit(v, design)
  fit <- eBayes(fit, trend=TRUE)
  table <- topTable(fit, coef=ncol(design), n = Inf, resort.by = 'P')
  return(table)
}

#### ggplot ####
#' Combine all the p-values and create a long format table.
#'
#' @param deseq Results from DESeq2
#' @param edger Results from edgeR
#' @param limma Results from Limma
#'
#' @return A two column tibble or dataframe with the name of the package in one 
#' column and the p-value in another. Dimensions will be 3,000 x 2.
#' @details In order to perform a facet wrap on our p-values somewhat painlessly, 
#' we want our data to be in _long_ format instead of _wide_ format. Long format is 
#' a way of structuring data to transform columns into rows. In our example, a 
#' dataframe that originally had one column each for DESeq, edgeR, and Limma 
#' p-values now only has two columns, where one of the columns describes the 
#' category of the other. The tidyr::gather() function is one convenient way of 
#' doing this. This technique is also known as "melting" a table.
#' 
#' When specifying p-values, notice the different names for p-value in each 
#' package (deseq "pvalue", edger "PValue", limma "P.Value").
#'
#' @examples > gathered <- combine_pval(deseq_res, edger_res, limma_res)
#' > head(gathered)
#' # A tibble: 6 × 2
#' package        pval
#' <chr>         <dbl>
#' 1 deseq   8.45e-304
#' 2 deseq   9.97e-261
#' 3 deseq   1.16e-206
combine_pval <- function(deseq, edger, limma) {
  deseq_long <- data.frame(deseq) %>% select(pval = pvalue)
  deseq_long <- deseq_long %>% mutate(package = "DESeq2", .before = "pval")
  
  edger_long <- data.frame(edger) %>% select(pval = PValue) 
  edger_long <- edger_long %>% mutate(package = "edger", .before = "pval")
  
  limma_long <- data.frame(limma) %>% select(pval = P.Value) 
  limma_long <- limma_long %>% mutate(package = "limma", .before = "pval")

  combo_pval <- rbind(deseq_long, edger_long, limma_long)

  return(combo_pval)
}

#' Create three separate facets for each of the diff. exp. pacakges.
#'
#' @param deseq Results from DESeq2
#' @param edger Results from edgeR
#' @param limma Results from Limma
#'
#' @return A tibble or dataframe with three columns: logFC, padj, and package. 
#' It should have 3,000 rows.
#' @details Once more, we want to used facet_wrap so we need to make our data long. 
#' You may try to use gather() again, or you could create three separate tables 
#' and combine them with rbind(). This table includes two columns from the original 
#' three dataframes. 
#'
#' @examples volcano <- create_facets(edger_res, deseq_res, limma_res)
#' > volcano
#' # A tibble: 3,000 × 3
#' logFC      padj   package
#' <dbl>     <dbl>     <chr>  
#' 1  -9.84 2.23e-180 edgeR  
#' 2   6.18 5.87e-179 edgeR  
create_facets <- function(deseq, edger, limma) {
  deseq_long <- data.frame(deseq) %>% select(padj = padj, logFC = log2FoldChange) %>%
    mutate(package = "DESeq2")
  
  edger_long <- data.frame(edger) %>% select(padj = padj, logFC = logFC) %>%
    mutate(package = "edgeR")
  
  limma_long <- data.frame(limma) %>% select(padj = adj.P.Val, logFC = logFC) %>%
    mutate(package = "Limma")
  
  combined_data <- bind_rows(deseq_long, edger_long, limma_long)
  
  return(combined_data)
}

#' Create an attractive volcano plot of three diff. exp. packages' data.
#'
#' @param volcano_data 
#'
#' @return A ggplot object of a facet_wrapped plot with attractive formatting.
#' @details Don't use default ggplot colors or the default theme. If you start to 
#' use ggplot with regularity, you will notice that the default theme has this 
#' boring gray background and very identifiable coloring of points. Does 
#' this work? Absolutely. Will many people notice or care? Probably not! But you 
#' will notice, and you will realize whoever put that figure together did not 
#' spend time or effort to make it visually attractive or more readable. The goal 
#' of plotting is to make data readable, so take the time to make your plots 
#' interesting and attractive. 
#' 
#' This function should do exactly that, be creative and modify ggplot options 
#' to create a volcano plot with good visual appeal and legible labels and titles. 
#' There are many ggplot resources available, and questions are easily found and 
#' answered on StackOverflow. Do not be afraid to search for specific questions 
#' you have with ggplot, it is very popular and odds are high someone has already 
#' tried to do whatever it is you're curious about. 
#' 
#' I suggest these two chapters for engaging with the ggplot documentation:
#' https://r-graphics.org/recipe-appearance-theme
#' https://r-graphics.org/chapter-colors
#'
#' @examples p <- theme_plot(volcano)
theme_plot <- function(volcano_data) {
  
  volcano_data$`adjusted P value` <- ifelse(volcano_data$padj < 1e-100, "Above 1e-100", "Below 1e-100")
  
  p <- ggplot(volcano_data, aes(x = logFC, y = -log10(padj), color = `adjusted P value`)) + 
    geom_point(alpha = 0.7) + scale_color_manual(values = c("Above 1e-100" = "cornflowerblue", "Below 1e-100" = "darkblue")) + 
    labs(title = "Volcano Plot Comparison of 3 Differential Expression Packages in R") 
  p <- p + xlab(substitute(Log[2]~"Fold Change", list()))
  p <- p + ylab(substitute(paste(-Log[10]~"Adjusted P Value")))
  p <- p + facet_grid(cols = vars(package))
  p <- p + theme(
    panel.background = element_rect(fill = "white"), 
    plot.title = element_text(color = "black"),  
    strip.background = element_rect(fill = "lightblue"),  
    strip.text = element_text(color = "white"),  
    panel.grid.major = element_line(color = "gray", linetype = "dashed"),
    panel.grid.minor = element_line(color = "lightgray", linetype = "dashed")
  )
  p <- p + geom_hline(yintercept = 0, color = "black", linetype = "dashed")
  return(p)
}