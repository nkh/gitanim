data class User(
    val name: String,
    val age: Int,
    val email: String? = null,
    val role: String = "user"
)

fun main() {
    val user = User("Alice", 30, "alice@example.com", "admin")
    println("Name: ${user.name}, Age: ${user.age}")
    println("Email: ${user.email}, Role: ${user.role}")
}
