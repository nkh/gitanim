class Person
  attr_accessor :name, :age, :email

  def initialize(name:, age:, email: nil)
    @name = name
    @age = age
    @email = email
  end

  def greet
    message = email ? "Hello, I'm #{@name} (#{@email})!" : "Hello, I'm #{@name}!"
    puts message
  end

  def to_h
    { name: @name, age: @age, email: @email }
  end
end
