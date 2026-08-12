use strict;
use warnings;
use feature 'say';

sub greet {
    my $name = shift;
    my $greeting = shift // "Hello";
    say "$greeting, $name!";
}

sub greet_all {
    my @names = @_;
    for my $name (@names) {
        greet($name);
    }
}

greet("World");
greet("Alice", "Hi");
greet_all("Bob", "Carol", "Dave");
