defmodule AcariClientTest do
  use ExUnit.Case
  doctest AcariClient

  test "greets the world" do
    assert AcariClient.hello() == :world
  end
end
