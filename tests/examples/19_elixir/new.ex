defmodule Greeter do
  @moduledoc "A module for greeting people"

  @doc "Returns a greeting message"
  @spec hello(String.t(), keyword()) :: String.t()
  def hello(name, opts \\ []) do
    lang = Keyword.get(opts, :lang, :en)
    greeting = case lang do
      :en -> "Hello"
      :fr -> "Bonjour"
      :es -> "Hola"
    end
    "#{greeting}, #{name}!"
  end
end
