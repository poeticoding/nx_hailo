defmodule NxHailo.Trackers.Track do
  @enforce_keys [:id, :bbox, :last_seen]
  defstruct id: nil, bbox: nil, hits: 1, misses: 0, last_seen: nil, born_at: nil, exit_at: nil
end
