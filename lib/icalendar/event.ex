defmodule ICalendar.Event do
  @moduledoc """
  Calendars have events.
  """

  defstruct summary:     nil,
            dtstart:     nil,
            dtend:       nil,
            description: nil,
            location:    nil,
            url:         nil,
            uid:         nil,
            status:      nil,
            categories:  nil,
            class:       nil,
            comment:     nil,
            geo:         nil,
            alarms:      nil,
            tzid:        nil

end

defimpl ICalendar.Serialize, for: ICalendar.Event do
  alias ICalendar.Util.KV

  def to_ics(event) do
    contents = to_kvs(event)
    """
    BEGIN:VEVENT
    #{contents}END:VEVENT
    """
  end

  defp to_kvs(event) do
    event
    |> Map.from_struct
    |> Enum.map(&to_kv/1)
    |> List.flatten
    #|> Enum.sort
    |> Enum.join
  end

  defp to_kv({:alarms, value}) when is_list(value) do
    Enum.map(value, &ICalendar.Serialize.to_ics/1)
  end
  defp to_kv({:alarms, value}) do
    ICalendar.Serialize.to_ics(value)
  end
  defp to_kv({key, value}) do
    name  = key |> to_string |> String.upcase
    KV.build(name, value)
  end
end
