#' Brown class implementation
#'
#' @import methods
#' @export Brown
#' @exportClass Brown


Brown = setRefClass("Brown",
  contains = "BaseModel",
  fields=list(regimes="data.frame"),
  methods=list(
    getWeights = function(nrep) {
      nt = tree@nterm
      epochs = tree@epochs
      W = matrix(1, nt*nrep, 1)
      return(W)
    },
    getCovar = function(nrep, gamma) {
      nterm = tree@nterm
      bt = tree@branch.times
      v = matrix(0, nterm*nrep, nterm*nrep)
      for (i in 1:nterm) {
        for (k in 1:nrep) {
          for (j in 1:nterm) {
            for (l in 1:nrep) {
              p = k + (i-1)*nrep
              q = l + (j-1)*nrep
              v[p,q] = bt[i,j]
              if ((i == j) && (k == l)) {
                v[p,q] = v[p,q] + gamma
              }
            }
          }
        }
      }
      return(v)
    },
    computeLogLik = function (nrep, dat, gamma) {
      n <- length(dat)
      w <- getWeights(nrep)
      v <- getCovar(nrep, gamma)
      gsol <- try(
        glssoln(w,dat,v),
        silent=FALSE
      )
      if (inherits(gsol,'try-error')) {
        e <- rep(NA,n)
        theta <- rep(NA,ncol(w))
        res <- Inf
      } else {
        e <- gsol$residuals
        theta <- gsol$coeff
        q <- e%*%solve(v,e)
      }
      sigma.sq = q[1,1]/n
      det.v = determinant(v, logarithm=T)
      if (det.v$sign != 1) {
        stop("myloglik error: non-positive determinant",call.=FALSE)
      }
      log.det.v <- det.v$modulus
      res = n*log(2*pi) + n*(1+log(sigma.sq)) + log.det.v
      list(dev=res, gamma=gamma, sigma.sq=sigma.sq, theta=theta)
    },

    fitSlow = function(data, gamma, 
                       spe_col = 'species', rep_col = 'replicate', exp_col = 'expval',
                       lb = 1e-10, ub = 1e+10,...) {
      dat = data[c(spe_col, rep_col, exp_col)]
      names(dat) = c('species', 'replicate', 'expval')
      replicates = unique(dat$replicate)
      dat = dcast(dat, species~replicate, value.var='expval')
      otd = as(tree, 'data.frame')
      tmp <- merge(otd, data.frame(dat), by.x='labels', by.y='species', all=TRUE)
      # merging destroys index of dataframe
      rownames(tmp) <- tmp$nodes
      tmp = tmp[as.character(tree@term), replicates, drop=FALSE]
      dat = gather(data.frame(t(tmp)))$value

      nrep <- length(replicates)
      optim.diagn <- vector(mode='list',length=0)
      par = c(gamma)
      opt <- nloptr(par,
                    eval_f = function(par) {
                      computeLogLik(nrep=nrep, dat=dat, gamma=par[1])$dev
                    },
                    eval_grad_f=NULL,
                    eval_g_ineq=NULL,
                    eval_g_eq=NULL,
                    eval_jac_g_ineq=NULL,
                    eval_jac_g_eq=NULL,
                    lb=rep(lb, length(par)),
                    ub=rep(ub, length(par)),
                    opts <- list(algorithm="NLOPT_LN_SBPLX",
                                 maxeval=10000,
                                 ftol_rel=.Machine$double.eps^0.5))

      status = opt$status
      message = opt$message

      if (!((status>=1) && (status <= 4))) {
        message("unsuccessful convergence, code ", status, ", see documentation for ", 'nloptr')
        warning("unsuccessful convergence, message ", message)
      }

      optim.diagn <- list(convergence=opt$status,message=opt$message)

      sol <- computeLogLik(nrep=nrep, dat=dat, gamma=opt$solution[1])

      list(optim.diagn=optim.diagn,
        theta=setNames(sol$theta, 'global'),
        sigma.sq=sol$sigma.sq,
        gamma=sol$gamma,
        loglik=-0.5*sol$dev
      )
    },

    fit = function(data, gamma,
                   spe_col = 'species', rep_col = 'replicate', exp_col = 'expval',
                   lb = 1e-10, ub = 1e+10,...) {
      dat = data[c(spe_col, rep_col, exp_col)]
      names(dat) = c('species', 'replicate', 'expval')
      replicates = unique(dat$replicate)
      dat = dcast(dat, species~replicate, value.var='expval')
      otd = as(tree, 'data.frame')
      tmp <- merge(otd, data.frame(dat), by.x='labels', by.y='species', all=TRUE)
      # merging destroys index of dataframe
      rownames(tmp) <- tmp$nodes
      tmp = tmp[as.character(tree@term), replicates, drop=FALSE]
      dat = gather(data.frame(t(tmp)))$value
      nrep = length(replicates)

      opt <- brown_fit(dat=dat, nterm=tree@nterm, nrep=nrep, bt=tree@branch.times, gamma=gamma)

      if (!((opt$status>=1) && (opt$status <= 4))) {
        message("unsuccessful convergence, code ", opt$status, ", see documentation for ", 'nloptr')
        warning("unsuccessful convergence, message ", opt$message)
      }

      optim.diagn <- list(convergence=opt$status,message=opt$message)

      list(optim.diagn=optim.diagn,
        theta=setNames(opt$theta, levels(regimes$regimes)),
        sigma.sq=opt$sigma.sq,
        gamma=opt$gamma,
        loglik=opt$loglik
      )
    }
  )
)

