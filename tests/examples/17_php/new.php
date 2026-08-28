<?php
class Logger {
    private array $messages = [];
    private string $level;

    public function __construct(string $level = 'INFO') {
        $this->level = $level;
    }

    public function log(string $message): void {
        $timestamp = date('Y-m-d H:i:s');
        $this->messages[] = "[$timestamp] [$this->level] $message";
    }

    public function getMessages(): array {
        return $this->messages;
    }

    public function clear(): void {
        $this->messages = [];
    }
}
