defmodule ICalendar.Util.Deserialize do
  @moduledoc """
  Deserialize ICalendar Strings into Event structs
  """

  @caldav_property ~r/^[A-Z;=-]{1,}:.*/

  defmodule PartialAlarm do
    defstruct uid:         nil,
              trigger:     nil,
              action:      nil,
              description: nil
    def to_alarm(pa) do
      %ICalendar.Alarm{uid: pa.uid, trigger: pa.trigger, action: pa.action,
        description: pa.description}
    end
  end

  alias ICalendar.Event
  alias ICalendar.Property

  def build_event(lines) when is_list(lines) do
    lines
    |> Enum.reduce({[], nil}, &combine_lines/2)
    |> finalize_combine_lines
    |> Enum.map(&retrieve_kvs/1)
    |> Enum.reduce(%Event{}, &parse_attr/2)
  end

  def combine_lines(line, {lines, nil}), do: {lines, line}
  def combine_lines(line, {lines, current_line}) do
    if Regex.match?(@caldav_property, line) do
      {[current_line | lines], line}
    else
      {lines, current_line <> line}
    end
  end
  def finalize_combine_lines({lines, last}), do: [last | lines] |> Enum.reverse

  @doc ~S"""
  This function extracts the key and value parts from each line of a iCalendar
  string.

      iex> ICalendar.Util.Deserialize.retrieve_kvs("lorem:ipsum")
      %ICalendar.Property{key: "LOREM", params: %{}, value: "ipsum"}
  """
  def retrieve_kvs(line) do
    # Split Line up into key and value
    [key, value] = String.split(line, ":", parts: 2, trim: true)
    [key, params] = retrieve_params(key)

    %Property{key: String.upcase(key), value: value, params: params}
  end

  @doc ~S"""
  This function extracts parameter data from a key in an iCalendar string.

      iex> ICalendar.Util.Deserialize.retrieve_params(
      ...>   "DTSTART;TZID=America/Chicago")
      ["DTSTART", %{"TZID" => "America/Chicago"}]

  It should be able to handle multiple parameters per key:

      iex> ICalendar.Util.Deserialize.retrieve_params(
      ...>   "KEY;LOREM=ipsum;DOLOR=sit")
      ["KEY", %{"LOREM" => "ipsum", "DOLOR" => "sit"}]
  """
  def retrieve_params(key) do
    [key | params] = String.split(key, ";", trim: true)

    params =
      params
      |> Enum.reduce(%{}, fn(param, acc) ->
        [key, val] = String.split(param, "=", parts: 2, trim: true)
        Map.merge(acc, %{key => val})
      end)

    [key, params]
  end

  def parse_attr(%Property{key: "BEGIN", value: "VALARM"} = _prop,
                %{alarms: alarms} =  acc) do
    %{acc | alarms: [%PartialAlarm{} | alarms]}
  end
  def parse_attr(%Property{key: "END", value: "VALARM"} = _prop,
                %{alarms: [%PartialAlarm{} = pa | alarms]} =  acc) do
    alarm = pa |> PartialAlarm.to_alarm
    %{acc | alarms: [alarm | alarms]}
  end
  def parse_attr(property, %{alarms: [%PartialAlarm{} = pa | alarms]} = acc) do
    prop = property.key |> String.downcase |> String.to_atom
    pa = Map.put(pa, prop, property.value)
    %{acc | alarms: [pa | alarms]}
  end

  def parse_attr(
    %Property{key: "DESCRIPTION", value: description},
    acc
  ) do
    %{acc | description: desanitized(description)}
  end
  def parse_attr(
    %Property{key: "DTSTART", value: dtstart, params: params},
    acc
  ) do
    with {:ok, timestamp} <- to_date(dtstart, params) do
      %{acc | dtstart: timestamp}
    else
        _ ->
          acc
    end
  end
  def parse_attr(
    %Property{key: "DTEND", value: dtend, params: params},
    acc
  ) do
    with {:ok, timestamp} <- to_date(dtend, params) do
      %{acc | dtend: timestamp}
    else
      _ ->
        acc
    end
  end
  def parse_attr(
    %Property{key: "SUMMARY", value: summary},
    acc
  ) do
    %{acc | summary: desanitized(summary)}
  end
  def parse_attr(
    %Property{key: "LOCATION", value: location},
    acc
  ) do
    %{acc | location: desanitized(location)}
  end
  def parse_attr(
    %Property{key: "COMMENT", value: comment},
    acc
  ) do
    %{acc | comment: desanitized(comment)}
  end
  def parse_attr(
    %Property{key: "STATUS", value: status},
    acc
  ) do
    %{acc | status: status |> desanitized() |> String.downcase()}
  end
  def parse_attr(
    %Property{key: "CATEGORIES", value: categories},
    acc
  ) do
    %{acc | categories: String.split(desanitized(categories), ",")}
  end
  def parse_attr(
    %Property{key: "CLASS", value: class},
    acc
  ) do
    %{acc | class: class |> desanitized() |> String.downcase()}
  end
  def parse_attr(
    %Property{key: "GEO", value: geo},
    acc
  ) do
    %{acc | geo: to_geo(geo)}
  end
  def parse_attr(%Property{key: "UID", value: id}, acc) do
    %{acc | uid: id}
  end
  def parse_attr(%Property{key: "TZID", value: id}, acc) do
    %{acc | tzid: id}
  end
  def parse_attr(_prop, acc), do: acc

  @doc ~S"""
  This function is designed to parse iCal datetime strings into erlang dates.

  It should be able to handle dates from the past:

      iex> {:ok, date} = ICalendar.Util.Deserialize.to_date("19930407T153022Z")
      ...> Timex.to_erl(date)
      {{1993, 4, 7}, {15, 30, 22}}

  As well as the future:

      iex> {:ok, date} = ICalendar.Util.Deserialize.to_date("39930407T153022Z")
      ...> Timex.to_erl(date)
      {{3993, 4, 7}, {15, 30, 22}}

  And should return error for incorrect dates:

      iex> ICalendar.Util.Deserialize.to_date("1993/04/07")
      {:error, "Expected `2 digit month` at line 1, column 5."}

  It should handle timezones from  the Olson Database:

      iex> {:ok, date} = ICalendar.Util.Deserialize.to_date("19980119T020000",
      ...> %{"TZID" => "America/Chicago"})
      ...> [Timex.to_erl(date), date.time_zone]
      [{{1998, 1, 19}, {2, 0, 0}}, "America/Chicago"]
  """
  def to_date(date_string, %{"TZID" => timezone}) do
    date_string =
      case String.last(date_string) do
        "Z" -> date_string
        _   -> date_string <> "Z"
      end

    Timex.parse(date_string <> timezone, "{YYYY}{0M}{0D}T{h24}{m}{s}Z{Zname}")
  end
  
  def to_date(date_string, %{"VALUE" => "DATE"}) do
    Timex.parse(date_string, "{YYYY}{0M}{0D}")
  end

  def to_date(date_string, %{}) do
    to_date(date_string, %{"TZID" => "Etc/UTC"})
  end

  def to_date(date_string) do
    to_date(date_string, %{"TZID" => "Etc/UTC"})
  end

  defp to_geo(geo) do
    geo
    |> desanitized()
    |> String.split(";")
    |> Enum.map(fn x -> Float.parse(x) end)
    |> Enum.map(fn {x, _} -> x end)
    |> List.to_tuple()
  end

  @doc ~S"""

  This function should strip any sanitization that has been applied to content
  within an iCal string.

      iex> ICalendar.Util.Deserialize.desanitized(~s(lorem\\, ipsum))
      "lorem, ipsum"
  """
  def desanitized(string) do
    string
    |> String.replace(~s(\\), "")
  end
end
