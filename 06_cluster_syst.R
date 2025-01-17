library(here)
library(tidyverse)
library(energy)
library(jsonlite)

args <- commandArgs(trailingOnly = TRUE)

dists.file <- args[1]
labels.file <- args[2]
output.dir <- args[3]


pairwise.dists <- as.matrix(read_table(here(dists.file), col_names = FALSE))
wcs <- read_json(here("stim/wcs_row_F.json"))

# Read the JSON content as a character string, replace NaNs with "NaN" (as a string), and parse it
json_content <- readLines(here(labels.file), warn = FALSE)
json_text <- paste(json_content, collapse = "\n")
modified_json_text <- gsub("\\bNaN\\b", '"NaN"', json_text)
parsed_json <- fromJSON(modified_json_text, simplifyVector = TRUE)
signal.labels <- as.data.frame(parsed_json)


cluster.info <- read_csv(here("outputs/cluster_output.csv"))
# %>% filter(min_cluster_size == 3)



euclidean <- function(a, b) {
  sqrt(sum((a - b)^2))
}

permutation_test <- function(value, signal.dists, color.dists) {
  permuted_dc <- numeric(10000) # for 1000 permutations

  # Permutation test
  for (i in 1:10000) {
    # Shuffle the rows of the color_distances matrix
    shuffled.color.dists <- color.dists[sample(nrow(color.dists)), ]

    permuted_dc[i] <- dcor(signal.dists, shuffled.color.dists)
  }

  observed_rank <- sum(permuted_dc >= value) + 1
  p_value <- observed_rank / (length(permuted_dc) + 1)

  return(p_value)
}




speaker.ids <- unique(signal.labels[, 2])
btwn.clust.systs <- matrix(ncol = 5, nrow = 0)
within.clust.systs <- matrix(ncol = 6, nrow = 0)
colnames(btwn.clust.systs) <- c("speaker", "n_clusters", "dcor", "p", "min_cluster_size")
colnames(within.clust.systs) <- c("speaker", "cluster_idx", "n_signals", "dcor", "p", "min_cluster_size")

print("Calculating between- and within-cluster systematicity...")
for (min_cluster_size_ in unique(cluster.info$min_cluster_size)) {
  cluster.info.filtered <- filter(cluster.info, min_cluster_size == min_cluster_size_)

  # For each participant, extract their signal distances from big pairwise matrix
  for (id in speaker.ids) {
    if (id == "init") {
      next
    }

    cluster.indices <- unique(filter(cluster.info.filtered, speaker == id, cluster_label != -1)$cluster_label)
    n.clusters <- length(cluster.indices)

    color.medoids <- matrix(ncol = 3, nrow = 0)
    signal.medoids <- matrix(ncol = 2, nrow = 0)

    # Loop through each cluster and calculate within-cluster systematicity
    cluster.systs <- c()
    medoid.indices <- c()



    for (cluster.idx in cluster.indices) {
      referents.in.cluster <-
        filter(cluster.info.filtered, speaker == id, cluster_label == cluster.idx)$referent

      # if there's only one referent, or its clustered as noise, ignore
      if (length(referents.in.cluster) == 1) {
        next
      }

      signal.indices <-
        which((signal.labels$V2 %in% id) &
          (signal.labels$V3 %in% referents.in.cluster)) # change later for informative column labels

      n.signals <- length((signal.indices)) # number of signals in each cluster

      signal.dists <- matrix(NA, nrow = n.signals, ncol = n.signals)
      color.dists <- matrix(NA,
        nrow =
          n.signals, ncol = n.signals
      )

      # within a signal, what are the pairwise distances?
      for (i in 1:n.signals) {
        for (j in 1:n.signals) {
          signal.dist <-
            pairwise.dists[signal.indices[i], signal.indices[j]]

          color.idx.i <-
            strtoi(signal.labels[signal.indices[i], 4]) + 1 # correct for zero-indexing
          color.idx.j <-
            strtoi(signal.labels[signal.indices[j], 4]) + 1
          color.dist <- euclidean(unlist(wcs$luv[[color.idx.i]]), unlist(wcs$luv[[color.idx.j]]))

          signal.dists[i, j] <- signal.dist
          color.dists[i, j] <- color.dist
        }
      }


      # Within-cluster stuff
      this.cluster.syst <- dcor(signal.dists, color.dists)
      p_value <- permutation_test(this.cluster.syst, signal.dists, color.dists)
      within.clust.systs <- rbind(within.clust.systs, c(id, cluster.idx, n.signals, this.cluster.syst, p_value, min_cluster_size_)) # TODO: study cluster syst p values

      # Between-cluster stuff
      medoid.idx <- signal.indices[which.min(colSums(signal.dists))] # check if this is right
      medoid.indices <- c(medoid.indices, medoid.idx)

      # signal.medoid.label <- signal.labels[signal.indices[medoid.idx], ]
      # signal.medoid <- filter(cluster.info, speaker == signal.medoid.label$V2, referent == signal.medoid.label$V3)[c("mds_1", "mds_2")] #TODO: extract indices instead and for colors keep it to distances Collect medoid indices instead
      # color.medoid <- wcs$luv[[strtoi(signal.medoid.label$V4) + 1]]
      #
      # signal.medoids <- rbind(signal.medoids, signal.medoid)
      # color.medoids <- rbind(color.medoids, color.medoid)
    }



    # Within-cluster systematicity
    # within.clust.syst <- mean(cluster.systs)
    # within.clust.systs <- rbind(within.clust.systs, c(id, within.clust.syst)) # todo: save all p values for all clusters

    # Between-cluster systematicity

    ## make distance matrix for medoids and referents
    signal.medoid.dists <- matrix(nrow = n.clusters, ncol = n.clusters)
    color.medoid.dists <- matrix(nrow = n.clusters, ncol = n.clusters)
    for (i in 1:n.clusters) {
      for (j in 1:n.clusters) {
        signal.dist <- pairwise.dists[medoid.indices[i], medoid.indices[j]]

        color.idx.i <-
          strtoi(signal.labels[medoid.indices[i], 4]) + 1 # correct for zero-indexing
        color.idx.j <-
          strtoi(signal.labels[medoid.indices[j], 4]) + 1
        color.dist <- euclidean(unlist(wcs$luv[[color.idx.i]]), unlist(wcs$luv[[color.idx.j]]))

        signal.medoid.dists[i, j] <- signal.dist
        color.medoid.dists[i, j] <- color.dist
      }
    }

    # calculate between-cluster systematiciity
    btwn.clust.syst <- dcor(signal.medoid.dists, color.medoid.dists)
    p_value <- permutation_test(btwn.clust.syst, signal.medoid.dists, color.medoid.dists)
    btwn.clust.systs <- rbind(btwn.clust.systs, c(id, n.clusters, btwn.clust.syst, p_value, min_cluster_size_)) # todo for later: add p value
  }
}




write.csv(btwn.clust.systs, here(paste0(output.dir, "/btwn_clust_syst.csv")), row.names = FALSE)
write.csv(within.clust.systs, here(paste0(output.dir, "/within_clust_syst.csv")), row.names = FALSE)
