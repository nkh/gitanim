object MathUtils {
  def square(x: Int): Int = x * x
  def cube(x: Int): Int = x * x * x
  def power(base: Int, exp: Int): Int =
    if (exp == 0) 1 else base * power(base, exp - 1)
  def factorial(n: Int): Int =
    if (n <= 1) 1 else n * factorial(n - 1)
}
