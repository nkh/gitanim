from abc import ABC, abstractmethod
from typing import List, Optional
from dataclasses import dataclass

class Animal(ABC):
    def __init__(self, name: str, age: int = 0):
        self.name = name
        self.age = age

    @abstractmethod
    def speak(self) -> str:
        pass

    def __str__(self) -> str:
        return f"{self.__class__.__name__}({self.name}, {self.age})"

@dataclass
class Dog(Animal):
    breed: str = "Unknown"

    def speak(self) -> str:
        return f"{self.name} ({self.breed}) says Woof!"

    def fetch(self) -> str:
        return f"{self.name} fetches the ball!"

@dataclass
class Cat(Animal):
    indoor: bool = True

    def speak(self) -> str:
        return f"{self.name} says Meow!"

    def purr(self) -> str:
        return f"{self.name} purrs softly."

def make_speak(animals: List[Animal]) -> List[str]:
    return [animal.speak() for animal in animals]
