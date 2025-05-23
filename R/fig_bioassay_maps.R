# Plot the spatial distribution of sampling effort for all pyrethroids, and for
# each insecticide.

# load packages and functions
source("R/packages.R")
source("R/functions.R")

# load the fitted model objects here, to set up predictions
load(file = "temporary/fitted_model.RData")

# load time-varying net coverage data and flatten it
mask <- rast("data/clean/raster_mask.tif")
mask_poly <- as.polygons(mask)

# set colours
pyrethroid_blue <- "#56B1F7"

# get all the pyrethroids
pyrethroids <- tibble(
  insecticide = types,
  class = classes[classes_index]
) %>%
  arrange(desc(class), insecticide) %>%
  filter(class == "Pyrethroids") %>%
  pull(insecticide)

# make labels for plotting insecticides
insecticides_plot <- tibble(
  insecticide = types,
  class = classes[classes_index]
) %>%
  arrange(desc(class), insecticide) %>%
  pull(insecticide)

insecticide_type_labels <- sprintf("%s) %s%s",
                                   LETTERS[1 + seq_along(insecticides_plot)],
                                   insecticides_plot,
                                   ifelse(insecticides_plot %in% pyrethroids,
                                          "*",
                                          ""))

insecticides_plot_lookup <- tibble(
  insecticide = insecticides_plot,
  insecticide_type_label = insecticide_type_labels
)

df_sub <- df %>%
  rename(
    year = year_start,
    country = country_name,
    insecticide = insecticide_type
  )

# subset to pyrethroids, and add on UN geoscheme regions for Africa
df_pyrethroids <- df_sub %>%
  filter(
    insecticide_class == "Pyrethroids",
  )

points_pyrethroids <- df_pyrethroids %>%
  group_by(
    latitude, longitude
  ) %>%
  summarise(
    mosquito_number = sum(mosquito_number),
    .groups = "drop"
  ) %>%
  arrange(mosquito_number)

points_all <- df_sub %>%
  group_by(
    insecticide, latitude, longitude
  ) %>%
  summarise(
    mosquito_number = sum(mosquito_number),
    .groups = "drop"
  ) %>%
  left_join(
    insecticides_plot_lookup,
    by = "insecticide"
  ) %>%
  arrange(mosquito_number)
 
pyrethroid_spatial_plot <- ggplot() +
  geom_spatvector(
    data = mask_poly,
    colour = "transparent",
    fill = grey(0.9)
  ) +
  geom_point(
    aes(
      x = longitude,
      y = latitude,
      fill = insecticide_type,
      size = mosquito_number,
    ),
    data = points_pyrethroids,
    shape = 21,
    fill = pyrethroid_blue
  ) +
  scale_size_area(
    max_size = 4
  ) +
  facet_wrap(~"A) All pyrethroids*",
             ncol = 1) +
  guides(
    size = guide_legend(title = "No. tested")
  ) +
  # ggtitle(
  #   label = "A) All pyrethroids*"
  # ) +
  theme_ir_maps() +
  theme(
    strip.text.x = element_text(hjust = 0)
  )

all_spatial_plot <- ggplot() +
  geom_spatvector(
    data = mask_poly,
    colour = "transparent",
    fill = grey(0.9)
  ) +
  geom_point(
    aes(
      x = longitude,
      y = latitude,
      size = mosquito_number,
      fill = insecticide_type_label
    ),
    data = points_all,
    shape = 21
  ) +
  scale_fill_discrete(
    direction = -1,
    guide = FALSE) +
  scale_size_area(
    max_size = 4
  ) +
  ylim(min(df_sub$latitude), max(df_sub$latitude)) +
  guides(
    size = guide_legend(title = "No. tested")
  ) +
  facet_wrap(~insecticide_type_label,
             ncol = 3) +
  theme_ir_maps() +
  theme(
    strip.text.x = element_text(hjust = 0)
  )

# use patchwork to set up the multi-panel plot
pyrethroid_spatial_plot + all_spatial_plot +
  plot_layout(ncol = 2, widths = c(1, 1.3))

ggsave("figures/bioassay_map_plots.png",
       bg = "white",
       scale = 0.8,
       width = 14,
       height = 6)
