
### Imputed data

comp_list <- complete(alf_results$imputed, "all")
d <- comp_list[[1]]

ps_model <- glm(ps_formula, data = d, family = "binomial")
d$pscore <- predict(ps_model, type = "response")

ggplot(d, aes(x = pscore, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  theme_minimal()

### Matched data

ggplot(alf_results$matched_list[[1]], aes(x = distance, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  labs(x = "Propensity score", y = "Density", fill = "Tamsulosin user") +
  theme_minimal()


### Original inspired by Jos

fin_ref$pscore <- predict(ps_model, type = "response")


density_plot  <- ggplot(fin_ref, aes(x = pscore, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  labs(title = "Density of Propensity Scores by Tamsulosin User",
       x = "Propensity Score",
       y = "Density",
       fill = "Tamsulosin user") +
  theme_minimal() +
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))

print(density_plot)
ggsave(density_plot, "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\densityplot_tam_fin_propscor")