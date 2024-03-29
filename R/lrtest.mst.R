lrtest.mst <- 
function(object, split = "median", cores = NULL, se = TRUE, ...) {
call <- match.call()

data_orig <- object$data
# use.method lrtest
mstdesign <- object$mstdesign

if(!is.null(cores)){
  if(cores > parallel::detectCores()){
    stop(paste0("You specified more cores than your computer have. Please change to equal or lower of: ",
    parallel::detectCores()," cores \n"))
  }
  cl <- parallel::makeCluster(cores)
}

  if(any(split %in% c("mean","median"))) {
    
    na_patterns <- factor(apply(is.na(object$data), 1, function(x) paste(which(x), collapse = "\r")))
    #na_pattern_levels <- levels(na_patterns)
    sum_i <- rowSums(object$data,na.rm = TRUE)
    order_i <- order(na_patterns)
    sum_i <- sum_i[order_i]
    na_patterns <- na_patterns[order_i]
    object$data <- object$data[order_i,]

    if (split == "mean") {
      mean_ig <- sapply(split(sum_i, na_patterns), function(x){
       x_mean <- mean(x)
       ifelse(x <= x_mean, 1, 2)
      })
      split_i <- factor(unlist(mean_ig), 
                      levels = c(1,2), 
                      labels = c("low score <= [mean]","high score  > [mean]"))
    }
    if (split == "median") {
      median_ig <- sapply(split(sum_i, na_patterns), function(x){
        x_median <- stats::median(x)
        ifelse(x <= x_median, 1, 2)
       })
       split_i <- factor(unlist(median_ig), 
                       levels = c(1,2), 
                       labels = c("low score <= [median]","high score > [median]"))
    }
  } else {
    if(!length(split) == nrow(object$data)){
      stop("The submitted split vector does not match the amount of persons in your data\n")
    } 
    if(length(unique(split)) != 2){
      stop("Please submit a dichotomous split vector!\n")
    }
    split_i <- as.factor(as.character(split))
  }


# Split the data after (generated) grouping vector
datalist <- split.data.frame(object$data, split_i) # 3 x faster than by 
names(datalist) <- levels(split_i)


# maybe in a future version of this function, it will be possible, that the items are excluded automatically

#----------item to be deleted---------------
deleted_items <- lapply(datalist, function(x) {
                      data_check(dat = x)$status  #items to be removed within subgroup
                    })

deleted_item <- unique(unlist(deleted_items))
if (length(deleted_item) >= (ncol(object$data)-1)) {
  stop("\nNo items with appropriate response patterns left to perform LR-test!\n")
}

if(length(deleted_item) > 0){
  #warning(paste0(
  #  cat("\nThe following items were excluded due to inappropriate response patterns within subgroups: \n"),
  #  paste(deleted_item, collapse=" "),
  #  cat("\nFull and subgroup models are estimated without these items!\n")
  #), immediate.=TRUE)
  cat("The following items have to be excluded due to inappropriate response patterns within subgroups: ", deleted_item)
  stop("It is necessary, that all Items in the dataset are also specified in the submitted mstdesign and vice versa! \nPlease update the mstdesign and the data.\n")
}


#if (length(deleted_item) > 0) {
#  object$data <- object$data[,!colnames(object$data)%in%deleted_item]
#  datalist <- split.data.frame(object$data, split_i) # 3 x faster than by 
#  datalist[[3]] <- object$data # add for basis model
#  names(datalist) <- c(levels(split_i),"basis")
#} 

if(!is.null(cores)){
  if (object$model == "Rasch model (mst)") {
    parallel::clusterExport(cl, list("raschmodel.mst","data_processing_mst"), envir = environment(lrtest.mst))
    likpar <- parallel::parSapply(cl,datalist,function(x) {
                               objectg <- raschmodel.mst(x, mstdesign = mstdesign, se = se, ...)
                               likg <- objectg$loglik
                               nparg <- length(objectg$betapar)
                               betapar <- objectg$betapar
                               se <- objectg$se.beta
                               list(likg,nparg,betapar,se,objectg) 
                               })
    on.exit(parallel::stopCluster(cl))
  }
}else{
  if (object$model == "Rasch model (mst)") {
    likpar <- sapply(datalist,function(x) {
                     objectg <- raschmodel.mst(x, mstdesign = mstdesign, se = se, ...)
                     likg <- objectg$loglik
                     nparg <- length(objectg$betapar)
                     betapar <- objectg$betapar
                     se <- objectg$se.beta
                     list(likg,nparg,betapar,se,objectg) 
                    })
  }
}

# if (length(deleted_item) > 0) {
# loglik_basis <- unlist(likpar[1,"basis"])
# betapar_basis <- likpar[,"basis"][[3]]
# } else {
  loglik_basis <- object$loglik
  betapar_basis <- object$betapar
# }

fitobj <- likpar[5, ]
likpar <- likpar[-5,]


loglikg <- sum(unlist(likpar[1,unique(split_i)]))
LRvalue <- 2*(abs(loglikg-loglik_basis))
df <- sum(unlist(likpar[2,unique(split_i)]))-(length(betapar_basis)) - 1
pvalue <- 1 - stats::pchisq(LRvalue, df)
betapars_subgroup <- likpar[3,unique(split_i)]
separs_subgroup <- likpar[4,unique(split_i)]

result <- list(data_orig = data_orig, 
               betapars_subgroup = betapars_subgroup, 
               se.beta_subgroup = separs_subgroup,
               model = object$model,
               LRvalue = LRvalue,
               df = df, 
               pvalue = pvalue, 
               loglik_subgroup = unlist(likpar[1,unique(split_i)], use.names = FALSE),
               split_subgroup = split_i, 
               call = call, 
               fitobj = fitobj)
return(result)
}
