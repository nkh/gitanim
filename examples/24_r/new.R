calculate_mean <- function(x) {
    if (length(x) == 0) return(NA)
    sum(x) / length(x)
}

calculate_stats <- function(x) {
    list(
        mean = calculate_mean(x),
        median = median(x),
        sd = sd(x),
        min = min(x),
        max = max(x)
    )
}

data <- c(1, 2, 3, 4, 5)
stats <- calculate_stats(data)
print(stats)
