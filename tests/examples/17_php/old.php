<?php
class Logger {
    private $messages = [];

    public function log($message) {
        $this->messages[] = $message;
    }

    public function getMessages() {
        return $this->messages;
    }
}
