defmodule FDB.Tutorial.TimeSeriesTest do
  use ExUnit.Case, async: false
  alias FDB.{Transaction, Database, Cluster, KeySelector}
  alias FDB.Coder.{Integer, Tuple, NestedTuple, ByteString, Subspace}
  use Timex
  import TestUtils
  use FDB.Future.Operators

  setup do
    flushdb()
  end

  test "timeseries" do
    coder = %Transaction.Coder{
      key:
        Subspace.new(
          "ts",
          Tuple.new({
            # date
            NestedTuple.new({
              NestedTuple.new({Integer.new(), Integer.new(), Integer.new()}),
              NestedTuple.new({Integer.new(), Integer.new(), Integer.new()})
            }),
            # website
            ByteString.new(),
            # page
            ByteString.new(),
            # browser
            ByteString.new()
          })
        ),
      value: Integer.new()
    }

    db =
      Cluster.create()
      |> Database.create(coder)

    populate(db)

    Database.transact(db, fn t ->
      m = Transaction.get_q(t, {{{2018, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "mozilla"})
      c = Transaction.get_q(t, {{{2018, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "chrome"})
      assert 2 == @m + @c
    end)

    result =
      Database.get_range_stream(
        db,
        KeySelector.first_greater_than({{{2018, 03, 01}, {0, 0, 0}}}),
        KeySelector.first_greater_or_equal({{{2018, 03, 31}, {23, 0, 0}}})
      )
      |> Enum.to_list()

    assert length(result) == 31 * 24 * 4
  end

  def populate(db) do
    Interval.new(from: ~D[2018-03-01], until: [months: 2], right_open: true)
    |> Interval.with_step(hours: 1)
    |> Task.async_stream(
      fn time ->
        time = NaiveDateTime.to_erl(time)

        Database.transact(db, fn t ->
          Transaction.set(t, {time, "www.ananthakumaran.in", "/books", "mozilla"}, 1)
          Transaction.set(t, {time, "www.ananthakumaran.in", "/books", "chrome"}, 1)
          Transaction.set(t, {time, "www.github.com", "/fdb", "mozilla"}, 1)
          Transaction.set(t, {time, "www.github.com", "/fdb", "chrome"}, 1)
        end)
      end,
      max_concurrency: 100
    )
    |> Stream.run()
  end
end
