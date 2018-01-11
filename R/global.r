#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

is_in_package <- function() !identical(environment(is_in_package), .GlobalEnv)

#' @import data.table
#' @import rlang
#' @import purrr
#' @import tidyr
#' @import plyr
#' @import dplyr
#' @import stringr
#' @import phyloseq
#' @import ggplot2
#' @import shiny
#' @import htmltools
#' @import plotly
#' @import utils
#' @import shinyjs

if(!is_in_package()){
  library(data.table)
  library(rlang)
  library(purrr)
  library(tidyr)
  library(plyr)
  library(dplyr)
  library(stringr)
  library(phyloseq)
  library(ggplot2)
  library(shiny)
  library(htmltools)
  library(plotly)
  library(utils)
  library(shinyjs)
}

DIR <- ifelse(is_in_package(), "R/data", "data")
MAX_SAMPLES <- 150

print('test1')

load(file.path(DIR, 'study_info.RData'))
