// todo-cli: a simple command-line todo manager.
// Uses manual argument parsing with match statements.
// Errors are reported via eprintln + exit codes.

use std::env;
use std::fs;
use std::io::{self, Write, BufRead, BufReader};
use std::path::PathBuf;
use std::process::ExitCode;
use std::collections::BTreeMap;

const DEFAULT_DATA_PATH: &str = ".todos.json";

#[derive(Debug, Clone)]
struct Todo {
    id: u64,
    title: String,
    completed: bool,
    priority: u8,
    tags: Vec<String>,
}

impl Todo {
    fn new(id: u64, title: String, priority: u8) -> Self {
        Todo {
            id,
            title,
            completed: false,
            priority,
            tags: Vec::new(),
        }
    }
}

fn load_todos(path: &PathBuf) -> Vec<Todo> {
    if !path.exists() {
        return Vec::new();
    }
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: cannot read {}: {}", path.display(), e);
            return Vec::new();
        }
    };
    if content.trim().is_empty() {
        return Vec::new();
    }
    parse_todos(&content)
}

fn parse_todos(content: &str) -> Vec<Todo> {
    let mut todos = Vec::new();
    // Trivial line-based format: id|completed|priority|tags|title
    for line in content.lines() {
        let parts: Vec<&str> = line.splitn(5, '|').collect();
        if parts.len() != 5 {
            continue;
        }
        let id: u64 = match parts[0].parse() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let completed = parts[1] == "1";
        let priority: u8 = match parts[2].parse() {
            Ok(v) => v,
            Err(_) => 1,
        };
        let tags: Vec<String> = if parts[3].is_empty() {
            Vec::new()
        } else {
            parts[3].split(',').map(String::from).collect()
        };
        todos.push(Todo {
            id,
            title: parts[4].to_string(),
            completed,
            priority,
            tags,
        });
    }
    todos
}

fn save_todos(path: &PathBuf, todos: &[Todo]) -> bool {
    let mut out = String::new();
    for t in todos {
        out.push_str(&format!(
            "{}|{}|{}|{}|{}\n",
            t.id,
            if t.completed { 1 } else { 0 },
            t.priority,
            t.tags.join(","),
            t.title,
        ));
    }
    match fs::write(path, out) {
        Ok(_) => true,
        Err(e) => {
            eprintln!("error: cannot write {}: {}", path.display(), e);
            false
        }
    }
}

fn next_id(todos: &[Todo]) -> u64 {
    todos.iter().map(|t| t.id).max().unwrap_or(0) + 1
}

fn print_todo(t: &Todo, idx: usize) {
    let status = if t.completed { "[x]" } else { "[ ]" };
    let prio = match t.priority {
        3 => "!!!",
        2 => "!!",
        _ => "!",
    };
    let tags = if t.tags.is_empty() {
        String::new()
    } else {
        format!(" #{}", t.tags.join(" #"))
    };
    println!("{:4}. {} {} {} {}{}", idx + 1, status, prio, t.id, t.title, tags);
}

fn cmd_list(todos: &[Todo], filter: Option<&str>) {
    let mut filtered: Vec<&Todo> = Vec::new();
    for t in todos {
        match filter {
            Some("done") => if t.completed { filtered.push(t); },
            Some("todo") => if !t.completed { filtered.push(t); },
            Some("high") => if t.priority >= 3 { filtered.push(t); },
            _ => filtered.push(t),
        }
    }
    if filtered.is_empty() {
        println!("No todos found.");
        return;
    }
    for (idx, t) in filtered.iter().enumerate() {
        print_todo(t, idx);
    }
    let total = todos.len();
    let done = todos.iter().filter(|t| t.completed).count();
    println!("\n{} total, {} done, {} pending", total, done, total - done);
}

fn cmd_add(path: &PathBuf, todos: &mut Vec<Todo>, args: &[String]) -> bool {
    if args.is_empty() {
        eprintln!("error: add requires a title");
        return false;
    }
    let mut priority: u8 = 1;
    let mut tags: Vec<String> = Vec::new();
    let mut title_parts: Vec<String> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        if arg == "-p" || arg == "--priority" {
            if i + 1 >= args.len() {
                eprintln!("error: -p requires a value");
                return false;
            }
            match args[i + 1].parse() {
                Ok(v) => priority = v,
                Err(_) => {
                    eprintln!("error: invalid priority: {}", args[i + 1]);
                    return false;
                }
            }
            i += 2;
        } else if arg == "-t" || arg == "--tag" {
            if i + 1 >= args.len() {
                eprintln!("error: -t requires a value");
                return false;
            }
            tags.push(args[i + 1].clone());
            i += 2;
        } else {
            title_parts.push(arg.clone());
            i += 1;
        }
    }
    if title_parts.is_empty() {
        eprintln!("error: add requires a title");
        return false;
    }
    let title = title_parts.join(" ");
    let id = next_id(todos);
    let mut todo = Todo::new(id, title, priority);
    todo.tags = tags;
    todos.push(todo);
    println!("Added todo #{}: {}", id, todos.last().unwrap().title);
    save_todos(path, todos)
}

fn cmd_complete(todos: &mut Vec<Todo>, args: &[String]) -> bool {
    if args.is_empty() {
        eprintln!("error: complete requires an id");
        return false;
    }
    let id: u64 = match args[0].parse() {
        Ok(v) => v,
        Err(_) => {
            eprintln!("error: invalid id: {}", args[0]);
            return false;
        }
    };
    let found = todos.iter_mut().find(|t| t.id == id);
    match found {
        Some(t) => {
            t.completed = true;
            println!("Completed #{}: {}", id, t.title);
            true
        }
        None => {
            eprintln!("error: no todo with id {}", id);
            false
        }
    }
}

fn cmd_remove(path: &PathBuf, todos: &mut Vec<Todo>, args: &[String]) -> bool {
    if args.is_empty() {
        eprintln!("error: remove requires an id");
        return false;
    }
    let id: u64 = match args[0].parse() {
        Ok(v) => v,
        Err(_) => {
            eprintln!("error: invalid id: {}", args[0]);
            return false;
        }
    };
    let original_len = todos.len();
    todos.retain(|t| t.id != id);
    if todos.len() == original_len {
        eprintln!("error: no todo with id {}", id);
        return false;
    }
    println!("Removed #{}", id);
    save_todos(path, todos)
}

fn cmd_tag(todos: &mut Vec<Todo>, args: &[String]) -> bool {
    if args.len() < 2 {
        eprintln!("error: tag requires <id> <tag>");
        return false;
    }
    let id: u64 = match args[0].parse() {
        Ok(v) => v,
        Err(_) => {
            eprintln!("error: invalid id: {}", args[0]);
            return false;
        }
    };
    let tag = &args[1];
    let found = todos.iter_mut().find(|t| t.id == id);
    match found {
        Some(t) => {
            if !t.tags.contains(tag) {
                t.tags.push(tag.clone());
            }
            println!("Tagged #{} with {}", id, tag);
            true
        }
        None => {
            eprintln!("error: no todo with id {}", id);
            false
        }
    }
}

fn cmd_stats(todos: &[Todo]) {
    let mut by_priority: BTreeMap<u8, usize> = BTreeMap::new();
    let mut by_tag: BTreeMap<String, usize> = BTreeMap::new();
    let mut done = 0;
    let mut pending = 0;
    for t in todos {
        *by_priority.entry(t.priority).or_insert(0) += 1;
        for tag in &t.tags {
            *by_tag.entry(tag.clone()).or_insert(0) += 1;
        }
        if t.completed { done += 1; } else { pending += 1; }
    }
    println!("Total: {} (done: {}, pending: {})", todos.len(), done, pending);
    println!("\nBy priority:");
    for (p, n) in &by_priority {
        println!("  P{}: {}", p, n);
    }
    if !by_tag.is_empty() {
        println!("\nBy tag:");
        for (t, n) in &by_tag {
            println!("  #{}: {}", t, n);
        }
    }
}

fn cmd_export(todos: &[Todo], path: &str) -> bool {
    let mut out = String::from("id,title,completed,priority,tags\n");
    for t in todos {
        let completed = if t.completed { "true" } else { "false" };
        let tags = if t.tags.is_empty() {
            String::new()
        } else {
            format!("\"{}\"", t.tags.join(";"))
        };
        let title = format!("\"{}\"", t.title.replace('"', "\"\""));
        out.push_str(&format!("{},{},{},{},{}\n", t.id, title, completed, t.priority, tags));
    }
    match fs::write(path, out) {
        Ok(_) => {
            println!("Exported {} todos to {}", todos.len(), path);
            true
        }
        Err(e) => {
            eprintln!("error: cannot write {}: {}", path, e);
            false
        }
    }
}

fn cmd_import(path: &PathBuf, todos: &mut Vec<Todo>, src: &str) -> bool {
    let content = match fs::read_to_string(src) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: cannot read {}: {}", src, e);
            return false;
        }
    };
    let mut imported = 0;
    for line in content.lines().skip(1) {
        if line.trim().is_empty() { continue; }
        // Naive CSV split — does not handle quoted commas properly.
        let fields: Vec<&str> = line.split(',').collect();
        if fields.len() < 4 { continue; }
        let id: u64 = fields[0].parse().unwrap_or_else(|_| next_id(todos));
        let title = fields[1].trim_matches('"').to_string();
        let completed = fields[2] == "true";
        let priority: u8 = fields[3].parse().unwrap_or(1);
        let tags: Vec<String> = if fields.len() >= 5 {
            fields[4].trim_matches('"').split(';')
                .filter(|s| !s.is_empty()).map(String::from).collect()
        } else {
            Vec::new()
        };
        todos.push(Todo { id, title, completed, priority, tags });
        imported += 1;
    }
    println!("Imported {} todos", imported);
    save_todos(path, todos)
}

fn print_usage(prog: &str) {
    eprintln!("Usage: {} <command> [args...]", prog);
    eprintln!();
    eprintln!("Commands:");
    eprintln!("  list [done|todo|high]        Show todos");
    eprintln!("  add [-p N] [-t TAG]... TITLE  Add a new todo");
    eprintln!("  complete <id>                 Mark a todo complete");
    eprintln!("  remove <id>                   Remove a todo");
    eprintln!("  tag <id> <tag>                Add a tag to a todo");
    eprintln!("  stats                         Show summary statistics");
    eprintln!("  export <path>                 Export todos to CSV");
    eprintln!("  import <path>                 Import todos from CSV");
    eprintln!("  help                          Show this help");
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_usage(&args[0]);
        return ExitCode::from(1);
    }
    let prog = &args[0];
    let command = &args[1];
    let rest: Vec<String> = args[2..].to_vec();
    let data_path = PathBuf::from(
        env::var("TODO_DATA").unwrap_or_else(|_| DEFAULT_DATA_PATH.to_string())
    );
    let mut todos = load_todos(&data_path);

    let success = match command.as_str() {
        "list" | "ls" => {
            let filter = if rest.is_empty() { None } else { Some(rest[0].as_str()) };
            cmd_list(&todos, filter);
            true
        }
        "add" => cmd_add(&data_path, &mut todos, &rest),
        "complete" | "done" => {
            if cmd_complete(&mut todos, &rest) {
                save_todos(&data_path, &todos)
            } else {
                false
            }
        }
        "remove" | "rm" => cmd_remove(&data_path, &mut todos, &rest),
        "tag" => {
            if cmd_tag(&mut todos, &rest) {
                save_todos(&data_path, &todos)
            } else {
                false
            }
        }
        "stats" => { cmd_stats(&todos); true }
        "export" => {
            if rest.is_empty() {
                eprintln!("error: export requires a path");
                false
            } else {
                cmd_export(&todos, &rest[0])
            }
        }
        "import" => {
            if rest.is_empty() {
                eprintln!("error: import requires a path");
                false
            } else {
                cmd_import(&data_path, &mut todos, &rest[0])
            }
        }
        "help" | "-h" | "--help" => {
            print_usage(prog);
            true
        }
        unknown => {
            eprintln!("error: unknown command: {}", unknown);
            print_usage(prog);
            false
        }
    };

    if success {
        ExitCode::from(0)
    } else {
        ExitCode::from(1)
    }
}
