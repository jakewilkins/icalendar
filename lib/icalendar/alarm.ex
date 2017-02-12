defmodule ICalendar.Alarm do
  @moduledoc """
  Events can have Alarms.
  """

  defstruct uid:         nil,
            trigger:     nil,
            action:      nil,
            description: nil
end

defimpl ICalendar.Serialize, for: ICalendar.Alarm do

  def to_ics(alarm) do
    uid = if alarm.uid, do: "UID:#{alarm.uid}\n", else: ""
    """
    BEGIN:VALARM
    #{uid}TRIGGER#{alarm.trigger |> trigger_value}
    ACTION:#{alarm.action || "DISPLAY"}
    DESCRIPTION:#{alarm.description}
    END:VALARM
    """
  end

  defp trigger_value(tr) do
    if String.contains?(tr, ":"), do: tr, else: ":#{tr}"
  end
end
