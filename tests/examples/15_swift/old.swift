struct Task {
    var title: String
    var completed: Bool = false
}

let tasks = [Task(title: "Buy groceries"), Task(title: "Walk dog")]
for task in tasks {
    print(task.title)
}
