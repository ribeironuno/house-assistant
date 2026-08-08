defmodule Brain.Text do
  @moduledoc """
  Small text helpers for normalizing Portuguese user input.
  """

  @articles ~r/^(o|a|os|as|um|uma|uns|umas)\s+/i

  @doc """
  Strips a leading Portuguese definite/indefinite article from a term.
  Returns `""` when the term was only an article.

  ## Examples

      iex> Brain.Text.strip_leading_articles("o leite")
      "leite"

      iex> Brain.Text.strip_leading_articles("umas bananas")
      "bananas"
  """
  def strip_leading_articles(term) when is_binary(term) do
    term
    |> String.trim()
    |> then(&Regex.replace(@articles, &1, ""))
    |> String.trim()
  end

  def strip_leading_articles(term), do: term
end
