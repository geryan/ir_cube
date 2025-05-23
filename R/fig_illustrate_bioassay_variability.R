# illustrate the inherent variability in biassay data at a set of locations with
# high sampling density

source("R/packages.R")
source("R/functions.R")

# load the fitted model objects here, to set up predictions
load(file = "temporary/fitted_model.RData")

# load the mask
mask <- rast("data/clean/raster_mask.tif")

insecticides_plot <- tibble(
  insecticide = types,
  class = classes[classes_index]
) %>%
  arrange(desc(class), insecticide) %>%
  pull(insecticide)

insecticides_plot_small <- c("Deltamethrin",
                             "Permethrin",
                             "Alpha-cypermethrin")

ir_africa <- readRDS("data/clean/all_gambiae_complex_data.RDS")

df <- ir_africa %>%
  group_by(insecticide_type) %>%
  # subset to the most common concentration for each insecticide
  filter(
    concentration == sample_mode(concentration)
  ) %>%
  ungroup() %>%
  filter(
    # drop any from before when we have data on net coverage
    year_start >= baseline_year
  ) %>%
  mutate(
    # create an index to the simulation year (in 1-indexed integers)
    year_id = year_start - baseline_year + 1,
    # add on cell ids corresponding to these observations,
    cell = cellFromXY(mask,
                      as.matrix(select(., longitude, latitude)))
  ) %>%
  # drop a handful of datapoints missing covariates
  filter(
    !is.na(extract(mask, cell)[, 1])
  ) %>%
  # add an index to the vector of unique cells (now they have been subsetted)
  mutate(
    cell_id = match(cell, unique(cell))
  )

# subset df to the cell and year with the most bioassay results
df_most_sampled <- df %>%
  filter(
    insecticide_type %in% insecticides_plot_small
  ) %>%
  mutate(
    cell_year_type = sprintf("location %i\n(%i)\n%s",
                             cell_id,
                             year_start,
                             insecticide_type)
  ) %>%
  group_by(
    cell_year_type,
    cell_id,
    year_start,
    insecticide_type
  ) %>%
  summarise(
    count = n(),
    .groups = "drop"
  ) %>%
  arrange(
    desc(count)
  ) %>%
  slice(1:6) %>%
  # bind_cols(
  #   xyFromCell(mask, .$cell)
  # ) %>%
  # reverse_geocode(
  #   lat = y,
  #   long = x,
  #   method = 'osm',
  #   full_results = TRUE
  # ) %>%
  # mutate(
  #   precise_place = str_split_i(address, ",", 1),
  #   precise_place = case_when(
  #     grepl("Placodji", address) ~ "Placodji, Cotonou",
  #     grepl("Busia", address) ~ "Busia",
  #     .default = precise_place
  #   ),
  #   place = paste(precise_place, country, sep = ", ")
  # ) %>%
  select(
    cell_year_type,
    cell_id,
    year_start,
    insecticide_type,
    count,
    # place
  ) %>%
  left_join(
    mutate(df,
           index = row_number()),
    by = c("cell_id", "year_start", "insecticide_type")
  ) %>%
  mutate(
    Susceptibility = died / mosquito_number
  )

# re-estimate rho for this set
examples <- unique(df_most_sampled$cell_year_type)
n_examples <- length(examples)
df_fit <- df_most_sampled %>%
  mutate(
    example_id = match(cell_year_type, examples)
  )

rho <- variable(0, 1)
probs <- variable(0, 1, dim = n_examples)

distribution(df_fit$died) <- betabinomial_p_rho(N = df_fit$mosquito_number,
                                                p = probs[df_fit$example_id],
                                                rho = rho)
m <- model(rho)  
rho_draws <- mcmc(m)
o <- greta::opt(m, adjust = FALSE)
rho_ml <- o$par$rho
rho_bayes <- summary(rho_draws)$statistics["Mean"]

# compute expected and observed statistics of these to elucidate the distribution
df_most_sampled_stats <- df_most_sampled %>%
  group_by(cell_year_type, insecticide_type) %>%
  summarise(
    # point estimate of suitability
    Susceptibility = sum(died) / sum(mosquito_number),
    .groups = "drop"
  ) %>%
  mutate(
    # 95% CIs under binomial (independence) sampling assumption
    binom_lower_100 = qbinom(0.025, 100, Susceptibility) / 100,
    binom_upper_100 = qbinom(0.975, 100, Susceptibility) / 100,
    # 95% CIs under betabinomial (non-independence) sampling assumption, using
    # the posterior mean estimated by our model
    # MLE is lower, maybe biased down
    # rho = rho_ml,
    rho = rho_bayes,
    alpha = Susceptibility * (1 / rho - 1),
    beta = alpha * (1 - Susceptibility) / Susceptibility,
    betabinom_lower_100 = qbbinom(0.025, 100, alpha, beta) / 100,
    betabinom_upper_100 = qbbinom(0.975, 100, alpha, beta) / 100,
  )

colour_types <- scales::hue_pal(direction = -1)(9)
types_plot_id <- match(insecticides_plot_small, insecticides_plot)
colours_plot <- colour_types[types_plot_id]

set.seed(1)
df_most_sampled %>%
  # shuffle the x axes so the points don't overlap too much
  mutate(
    x_random = sample(seq(0.2, 1.8, length.out = n()))
  ) %>%
  ggplot(
    aes(
      xmin = 0,
      xmax = 2,
      group = cell_year_type
    )
  ) +
  geom_rect(
    aes(
      ymax = betabinom_upper_100,
      ymin = betabinom_lower_100,
    ),
    data = df_most_sampled_stats,
    fill = grey(0.9)
  ) +
  geom_rect(
    aes(
      ymax = binom_upper_100,
      ymin = binom_lower_100,
    ),
    data = df_most_sampled_stats,
    fill = grey(0.7)
  ) +
  geom_rect(
    aes(
      ymax = Susceptibility,
      ymin = Susceptibility
    ),
    data = df_most_sampled_stats,
    linewidth = 1,
    colour = grey(0.4)
  ) +
  geom_point(
    aes(
      y = Susceptibility,
      size = mosquito_number,
      x = x_random,
      fill = insecticide_type
    ),
    shape = 21
  ) +
  facet_wrap(~cell_year_type,
             nrow = 1,
             strip.position = "bottom") +
  scale_y_continuous(
    labels = scales::percent,
    limits = c(0, 1)
  ) +
  scale_x_continuous(
    limits = c(0, 2)
  ) +
  scale_fill_manual(
    values = colours_plot
  ) +
  xlab("") +
  theme_minimal() +
  guides(
    fill = "none",
    size = guide_legend(title = "No. tested")
  ) +
  theme(
    axis.text.x = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank()
  ) +
  ggtitle(
    "Significant variability in replicated bioassay results",
    sprintf("95%s sampling intervals under binomial (mid grey) and betabinomial
(light grey; estimated correlation rho=%s) intervals assume sample size N=100.",
            "%",
            round(rho_bayes, 2))
  )

ggsave(
  "figures/bioassay_variability.png",
  bg = "white",
  scale = 0.9,
  width = 8,
  height = 6
)

# Multiple discriminating concentration bioassay results against Pyrethroids at
# a single locations (5km grid cells) and years, as an example of the inherent
# variability in this type of data. Dark grey horizontal lines give the (sample
# size weighted) mean of the susceptibility estimates, medium grey bands give
# the 95% sampling interval of a binomial distribution, with this mean and 100
# samples, light grey bands give the 95% sampling interval of a beta-binomial
# distribution, with this mean, 100 samples, and correlation parameter estimate
# from each dataset independently.

# find the original sources for these and unserstand why there are soe sampled, and what was originally reported

# location 339 (2012, 2014) is Busia, Western Kenya, with significant testing as
# part of the IIR project (Implications of Insecticide Resistance consortium
# https://parasitesandvectors.biomedcentral.com/articles/10.1186/s13071-018-3101-4)
# and the Insecticide Resistance Project Kenya (Githinji et al.
# https://onlinelibrary.wiley.com/doi/10.1155/2020/9423682)

# location 397 (2011) is in New Halfa, Sudan, from Ismail et al., with multiple replicates
# in these locations
# https://parasitesandvectors.biomedcentral.com/articles/10.1186/s13071-018-2732-9

# Location 5 from Benin, Yadouleton et al. (2010)
# https://doi.org/10.1186/1475-2875-9-83 however it looks like the GPS
# coordinates given were only for cotonou, not the specific parts there, so
# variability could be due to local differences

# Location 1014 (2015) is from Cameroon, from Mandeng et al
df_most_sampled_stats
df_most_sampled %>%
  # group_by(cell_year_type, insecticide_type, source) %>%
  # summarise(n = n()) %>%
  View()



# Using this estimate of the dispersion in susceptibility bioassays (and
# assuming each was sampled from a single location), plot how the statistical
# power to estimate the population susceptibility depends on the total number of
# mosquitoes assayed, and the number of unique collections they are collated
# from

tibble(
  n = seq(50, 500, by = 10)
) %>%
  rowwise() %>%
  mutate(
    moe_1 = moe_betabinomial(n, rho = rho_bayes),
    moe_3 = moe_betabinomial_cluster(n, rho = rho_bayes, clusters = 3),
    moe_5 = moe_betabinomial_cluster(n, rho = rho_bayes, clusters = 5),
    moe_10 = moe_betabinomial_cluster(n, rho = rho_bayes, clusters = 10),
    moe_50 = moe_betabinomial_cluster(n, rho = rho_bayes, clusters = 50),
    moe_independent = moe_binomial(n)
  ) %>%
  pivot_longer(
    cols = starts_with("moe"),
    names_to = "clusters",
    values_to = "moe",
    names_prefix = "moe_"
  ) %>%
  mutate(
    clusters = factor(
      clusters,
      levels = c(na.omit(unique(as.numeric(clusters))), "independent")
    )
  ) %>%
  ggplot(
    aes(
      x = n,
      y = moe,
      group = clusters,
      colour = clusters
    )
  ) +
  geom_line(
    linewidth = 1
  ) +
  scale_y_continuous(labels = scales::percent,
                     limits = c(0, 0.5)) +
  theme_minimal() +
  scale_x_continuous(breaks = c(50, 100, 250, 500)) +
  ylab("Margin of error") +
  xlab("Number of mosquitoes") +
  ggtitle(
    "Statistical power of cluster-stratified susceptibility bioassays",
  )

ggsave("figures/cluster_sampling_power.png",
       bg = "white",
       width = 6,
       height = 5)
