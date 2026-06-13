alist(
  log_radon ~ dnorm(alpha[county] + beta * floor, sigma),
  alpha[county] ~ dnorm(mu_alpha, sigma_alpha),
  beta ~ dnorm(0, 10),
  sigma ~ dnorm(0, 10),
  mu_alpha ~ dnorm(0, 10),
  sigma_alpha ~ dnorm(0, 10)
)
