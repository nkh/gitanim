use std::collections::HashMap;

fn main() {
    let nums = vec![1, 2, 3, 4, 5];

    // Calculate sum using fold
    let sum: i32 = nums.iter().fold(0, |acc, &x| acc + x);
    println!("Sum: {}", sum);

    // Calculate average
    let avg = sum as f64 / nums.len() as f64;
    println!("Average: {:.2}", avg);

    // Build a frequency map
    let mut freq: HashMap<i32, u32> = HashMap::new();
    for &n in &nums {
        *freq.entry(n).or_insert(0) += 1;
    }
    println!("Frequencies: {:?}", freq);
}
