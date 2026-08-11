struct Task: Identifiable {
    var id = UUID()
    var title: String
    var completed: Bool = false
    var priority: Priority = .medium

    enum Priority {
        case low, medium, high
    }
}

let tasks = [
    Task(title: "Buy groceries", priority: .high),
    Task(title: "Walk dog", priority: .medium),
    Task(title: "Read book", priority: .low)
]
for task in tasks {
    print("[\(task.priority)] \(task.title)")
}
