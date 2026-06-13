data {
  int<lower=1> N;  // observations
  int<lower=1> N_county;
  array[N] int<lower=1, upper=N_county> county;
  vector[N] floor;
  vector[N] log_radon;
}
parameters {
  real mu_alpha;
  real<lower=0> sigma_alpha;
  vector<offset=mu_alpha, multiplier=sigma_alpha>[N_county] alpha; 
  real beta;
  real<lower=0> sigma;
}
model {
  log_radon ~ normal(alpha[county] + beta * floor, sigma);  
  alpha ~ normal(mu_alpha, sigma_alpha); // partial-pooling
  beta ~ normal(0, 10);
  sigma ~ normal(0, 10);
  mu_alpha ~ normal(0, 10);
  sigma_alpha ~ normal(0, 10);
}
generated quantities {
  array[N] real y_rep = normal_rng(alpha[county] + beta * floor, sigma);
}