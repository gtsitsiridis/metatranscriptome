% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/global_de.r
\name{globalDE}
\alias{globalDE}
\title{Global Differential Expression

Perform DESeq2 on each group of samples for each study.}
\usage{
globalDE(input_dir = pkg_file("data"), max_samples = 1000, log = F)
}
\arguments{
\item{input_dir}{A directory that contains data generated by \link[MetaMap]{transformData}. The default is inside the package.}

\item{max_samples}{Only studies with at most \code{max_samples} will be used. The default is 1000.}

\item{log}{A logical value indicating whether a log file should be generated with info about the process. The default is \code{FALSE}}
}
\value{
CSV files containing DESeq2 tables.
}
