// todo-cli: a simple command-line todo manager.
// Refactored to use clap derive, thiserror-based error types, and tracing.
//
// Cargo dependencies:
//   clap = { version = "4", features = ["derive"] }
//   thiserror = "1"
//   tracing = "0.1"
//   tracing-subscriber = { version = "0.3", features = ["env-filter"] }
//   serde = { version = "1", features = ["derive"] }
//   serde_json = "1"

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tracing::{debug, error, info, instrument, warn};

const DEFAULT_DATA_PATH: &str = ".todos.json";

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
enum TodoError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("data file is corrupt: {0}")]
    Corrupt(String),

    #[error("todo with id {0} not found")]
    NotFound(u64),

    #[error("invalid id '{0}'")]
    InvalidId(String),

    #[error("invalid priority '{0}' (must be 1-3)")]
    InvalidPriority(String),

    #[error("missing required argument: {0}")]
    MissingArg(&'static str),

    #[error("CSV parse error at line {line}: {reason}")]
    Csv { line: usize, reason: String },
}

type Result<T> = std::result::Result<T, TodoError>;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Todo {
    id: u64,
    title: String,
    completed: bool,
    priority: Priority,
    #[serde(default)]
    tags: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
enum Priority {
    Low,
    Medium,
    High,
}

impl Priority {
    fn from_int(value: u8) -> Result<Self> {
        match value {
            1 => Ok(Priority::Low),
            2 => Ok(Priority::Medium),
            3 => Ok(Priority::High),
            other => Err(TodoError::InvalidPriority(other.to_string())),
        }
    }

    fn as_int(self) -> u8 {
        match self {
            Priority::Low => 1,
            Priority::Medium => 2,
            Priority::High => 3,
        }
    }

    fn symbol(self) -> &'static str {
        match self {
            Priority::Low => "!",
            Priority::Medium => "!!",
            Priority::High => "!!!",
        }
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct TodoStore {
    todos: Vec<Todo>,
    next_id: u64,
}

impl TodoStore {
    fn new() -> Self {
        TodoStore { todos: Vec::new(), next_id: 1 }
    }

    #[instrument(skip(self))]
    fn load(path: &PathBuf) -> Result<Self> {
        if !path.exists() {
            debug!("data file does not exist, starting fresh");
            return Ok(Self::new());
        }
        let content = fs::read_to_string(path)?;
        if content.trim().is_empty() {
            return Ok(Self::new());
        }
        let store: TodoStore = serde_json::from_str(&content)
            .map_err(|e| TodoError::Corrupt(e.to_string()))?;
        Ok(store)
    }

    #[instrument(skip(self))]
    fn save(&self, path: &PathBuf) -> Result<()> {
        let json = serde_json::to_string_pretty(self)?;
        let mut tmp = path.clone();
        tmp.set_extension("json.tmp");
        fs::write(&tmp, json)?;
        fs::rename(&tmp, path)?;
        debug!("saved {} todos to {}", self.todos.len(), path.display());
        Ok(())
    }

    fn add(&mut self, title: String, priority: Priority, tags: Vec<String>) -> &Todo {
        let id = self.next_id;
        self.next_id += 1;
        let todo = Todo { id, title, completed: false, priority, tags };
        self.todos.push(todo);
        self.todos.last().unwrap()
    }

    fn complete(&mut self, id: u64) -> Result<&Todo> {
        let todo = self.todos.iter_mut().find(|t| t.id == id)
            .ok_or(TodoError::NotFound(id))?;
        todo.completed = true;
        Ok(todo)
    }

    fn remove(&mut self, id: u64) -> Result<()> {
        let original = self.todos.len();
        self.todos.retain(|t| t.id != id);
        if self.todos.len() == original {
            return Err(TodoError::NotFound(id));
        }
        Ok(())
    }

    fn add_tag(&mut self, id: u64, tag: String) -> Result<&Todo> {
        let todo = self.todos.iter_mut().find(|t| t.id == id)
            .ok_or(TodoError::NotFound(id))?;
        if !todo.tags.contains(&tag) {
            todo.tags.push(tag);
        }
        Ok(todo)
    }

    fn list(&self, filter: Option<ListFilter>) -> Vec<&Todo> {
        self.todos.iter().filter(|t| match filter {
            Some(ListFilter::Done) => t.completed,
            Some(ListFilter::Pending) => !t.completed,
            Some(ListFilter::High) => t.priority == Priority::High,
            None => true,
        }).collect()
    }

    fn stats(&self) -> TodoStats {
        let mut by_priority: BTreeMap<Priority, usize> = BTreeMap::new();
        let mut by_tag: BTreeMap<String, usize> = BTreeMap::new();
        let mut done = 0;
        let mut pending = 0;
        for t in &self.todos {
            *by_priority.entry(t.priority).or_insert(0) += 1;
            for tag in &t.tags {
                *by_tag.entry(tag.clone()).or_insert(0) += 1;
            }
            if t.completed { done += 1; } else { pending += 1; }
        }
        TodoStats {
            total: self.todos.len(),
            done,
            pending,
            by_priority,
            by_tag,
        }
    }
}

#[derive(Debug)]
enum ListFilter {
    Done,
    Pending,
    High,
}

impl std::str::FromStr for ListFilter {
    type Err = TodoError;
    fn from_str(s: &str) -> Result<Self> {
        match s {
            "done" | "completed" => Ok(ListFilter::Done),
            "todo" | "pending"   => Ok(ListFilter::Pending),
            "high"               => Ok(ListFilter::High),
            other => Err(TodoError::Corrupt(
                format!("unknown list filter: {other}"),
            )),
        }
    }
}

struct TodoStats {
    total: usize,
    done: usize,
    pending: usize,
    by_priority: BTreeMap<Priority, usize>,
    by_tag: BTreeMap<String, usize>,
}

// ---------------------------------------------------------------------------
// CLI definition
// ---------------------------------------------------------------------------

#[derive(Parser, Debug)]
#[command(name = "todo", version, about = "A simple command-line todo manager")]
struct Cli {
    /// Path to the data file.
    #[arg(long, env = "TODO_DATA", default_value = DEFAULT_DATA_PATH)]
    data: PathBuf,

    /// Increase verbosity (-v info, -vv debug, -vvv trace).
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// List todos.
    List {
        /// Filter: done, pending, or high.
        filter: Option<ListFilter>,
    },
    /// Add a new todo.
    Add {
        /// Priority (1=low, 2=medium, 3=high).
        #[arg(short, long, value_parser = parse_priority, default_value = "1")]
        priority: Priority,
        /// Tags to attach.
        #[arg(short, long, value_name = "TAG")]
        tag: Vec<String>,
        /// Title of the todo (quoted if it contains spaces).
        title: Vec<String>,
    },
    /// Mark a todo as complete.
    Complete { id: u64 },
    /// Remove a todo.
    Remove { id: u64 },
    /// Tag a todo.
    Tag {
        id: u64,
        tag: String,
    },
    /// Show summary statistics.
    Stats,
    /// Export todos to CSV.
    Export {
        /// Output path; use - for stdout.
        path: String,
    },
    /// Import todos from CSV.
    Import {
        path: PathBuf,
    },
}

fn parse_priority(s: &str) -> Result<Priority> {
    let n: u8 = s.parse().map_err(|_| TodoError::InvalidPriority(s.to_string()))?;
    Priority::from_int(n)
}

// ---------------------------------------------------------------------------
// Command handlers
// ---------------------------------------------------------------------------

fn print_todo(t: &Todo, idx: usize) {
    let status = if t.completed { "[x]" } else { "[ ]" };
    let tags = if t.tags.is_empty() {
        String::new()
    } else {
        format!(" #{}", t.tags.join(" #"))
    };
    println!("{:4}. {} {} {} {}{}", idx + 1, status, t.priority.symbol(),
             t.id, t.title, tags);
}

#[instrument(skip(store))]
fn cmd_list(store: &TodoStore, filter: Option<ListFilter>) {
    let filtered = store.list(filter);
    if filtered.is_empty() {
        println!("No todos found.");
        return;
    }
    for (idx, t) in filtered.iter().enumerate() {
        print_todo(t, idx);
    }
    let stats = store.stats();
    println!("\n{} total, {} done, {} pending",
             stats.total, stats.done, stats.pending);
}

#[instrument(skip(store))]
fn cmd_add(store: &mut TodoStore, title: Vec<String>, priority: Priority,
           tags: Vec<String>) -> Result<()> {
    if title.is_empty() {
        return Err(TodoError::MissingArg("title"));
    }
    let title = title.join(" ");
    let todo = store.add(title, priority, tags);
    info!(id = todo.id, "added todo");
    println!("Added todo #{}: {}", todo.id, todo.title);
    Ok(())
}

#[instrument(skip(store))]
fn cmd_complete(store: &mut TodoStore, id: u64) -> Result<()> {
    let todo = store.complete(id)?;
    info!(id, "completed todo");
    println!("Completed #{}: {}", id, todo.title);
    Ok(())
}

#[instrument(skip(store))]
fn cmd_remove(store: &mut TodoStore, id: u64) -> Result<()> {
    store.remove(id)?;
    info!(id, "removed todo");
    println!("Removed #{}", id);
    Ok(())
}

#[instrument(skip(store))]
fn cmd_tag(store: &mut TodoStore, id: u64, tag: String) -> Result<()> {
    let todo = store.add_tag(id, tag.clone())?;
    info!(id, tag = %tag, "tagged todo");
    println!("Tagged #{} with {}", id, tag);
    Ok(())
}

fn cmd_stats(store: &TodoStore) {
    let stats = store.stats();
    println!("Total: {} (done: {}, pending: {})",
             stats.total, stats.done, stats.pending);
    println!("\nBy priority:");
    for (p, n) in &stats.by_priority {
        println!("  P{}: {}", p.as_int(), n);
    }
    if !stats.by_tag.is_empty() {
        println!("\nBy tag:");
        for (t, n) in &stats.by_tag {
            println!("  #{}: {}", t, n);
        }
    }
}

fn cmd_export(store: &TodoStore, path: &str) -> Result<()> {
    let mut out = String::from("id,title,completed,priority,tags\n");
    for t in &store.todos {
        let completed = if t.completed { "true" } else { "false" };
        let tags = if t.tags.is_empty() {
            String::new()
        } else {
            format!("\"{}\"", t.tags.join(";"))
        };
        let title = format!("\"{}\"", t.title.replace('"', "\"\""));
        out.push_str(&format!("{},{},{},{},{}\n",
            t.id, title, completed, t.priority.as_int(), tags));
    }
    if path == "-" {
        let stdout = std::io::stdout();
        let mut lock = stdout.lock();
        lock.write_all(out.as_bytes())?;
    } else {
        fs::write(path, out)?;
    }
    info!(path, count = store.todos.len(), "exported todos");
    println!("Exported {} todos to {}", store.todos.len(), path);
    Ok(())
}

fn cmd_import(store: &mut TodoStore, path: &PathBuf) -> Result<()> {
    let content = fs::read_to_string(path)?;
    let mut imported = 0usize;
    for (lineno, line) in content.lines().enumerate().skip(1) {
        if line.trim().is_empty() { continue; }
        let fields = parse_csv_line(line)
            .map_err(|e| TodoError::Csv { line: lineno, reason: e })?;
        if fields.len() < 4 {
            return Err(TodoError::Csv {
                line: lineno, reason: "expected >= 4 fields".into(),
            });
        }
        let id: u64 = fields[0].parse()
            .map_err(|_| TodoError::Csv {
                line: lineno, reason: format!("invalid id: {}", fields[0]),
            })?;
        let title = fields[1].clone();
        let completed = fields[2] == "true";
        let priority_int: u8 = fields[3].parse().unwrap_or(1);
        let priority = Priority::from_int(priority_int).unwrap_or(Priority::Low);
        let tags = if fields.len() >= 5 {
            fields[4].split(';')
                .filter(|s| !s.is_empty()).map(String::from).collect()
        } else {
            Vec::new()
        };
        store.todos.push(Todo { id, title, completed, priority, tags });
        if id >= store.next_id {
            store.next_id = id + 1;
        }
        imported += 1;
    }
    info!(imported, "imported todos");
    println!("Imported {} todos", imported);
    Ok(())
}

/// Minimal CSV line parser that handles quoted fields.
fn parse_csv_line(line: &str) -> std::result::Result<Vec<String>, String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if in_quotes {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    current.push('"');
                    chars.next();
                } else {
                    in_quotes = false;
                }
            } else {
                current.push(c);
            }
        } else if c == '"' {
            in_quotes = true;
        } else if c == ',' {
            fields.push(std::mem::take(&mut current));
        } else {
            current.push(c);
        }
    }
    fields.push(current);
    Ok(fields)
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn init_tracing(verbose: u8) {
    let filter = match verbose {
        0 => "warn",
        1 => "info",
        2 => "debug",
        _ => "trace",
    };
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(filter)),
        )
        .with_target(false)
        .try_init();
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    init_tracing(cli.verbose);
    debug!(?cli.command, data = ?cli.data, "starting");

    let mut store = TodoStore::load(&cli.data)?;
    let needs_save: bool;

    match &cli.command {
        Command::List { filter } => {
            cmd_list(&store, *filter);
            needs_save = false;
        }
        Command::Add { priority, tag, title } => {
            cmd_add(&mut store, title.clone(), *priority, tag.clone())?;
            needs_save = true;
        }
        Command::Complete { id } => {
            cmd_complete(&mut store, *id)?;
            needs_save = true;
        }
        Command::Remove { id } => {
            cmd_remove(&mut store, *id)?;
            needs_save = true;
        }
        Command::Tag { id, tag } => {
            cmd_tag(&mut store, *id, tag.clone())?;
            needs_save = true;
        }
        Command::Stats => {
            cmd_stats(&store);
            needs_save = false;
        }
        Command::Export { path } => {
            cmd_export(&store, path)?;
            needs_save = false;
        }
        Command::Import { path } => {
            cmd_import(&mut store, path)?;
            needs_save = true;
        }
    }

    if needs_save {
        if let Err(e) = store.save(&cli.data) {
            error!(error = %e, "failed to save");
            return Err(e);
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::from(0),
        Err(e) => {
            error!("{e}");
            ExitCode::from(1)
        }
    }
}
