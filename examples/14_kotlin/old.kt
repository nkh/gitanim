data class User(val name: String, val age: Int)

fun main() {
    val user = User("Alice", 30)
    println("Name: ${user.name}, Age: ${user.age}")
}
