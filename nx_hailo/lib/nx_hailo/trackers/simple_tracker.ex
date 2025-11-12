defmodule NxHailo.Trackers.SimpleTracker do
  alias NxHailo.Trackers.Track

  @type tracker_state :: %{
    next_id: non_neg_integer(),
    tracks: %{non_neg_integer() => Track.t()}
  }

  @type bbox :: %{
    xmin: integer(),
    xmax: integer(),
    ymin: integer(),
    ymax: integer()
  }

  # [:ymin, :ymax, :xmin, :xmax, :score, :class_name, :class_id]
  @type detection :: %{
    xmin: integer(),
    xmax: integer(),
    ymin: integer(),
    ymax: integer(),
    score: float(),
    class_name: String.t(),
    class_id: non_neg_integer()
  }


  @iou_tresh 0.40
  @max_age 20
  @min_hits 5

  @spec new() :: tracker_state()
  def new do
    %{next_id: 1, tracks: %{}}
  end

  # @spec update(state :: tracker_state(), [detection()], non_neg_integer())
  def update(state, detections, now_ms) do
    current_tracks = state.tracks

    # best confidence first
    dets =
      detections
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.with_index()

    # tracks to associate to new detections
    track_ids =
      current_tracks
      |> Map.keys()
      |> MapSet.new()

    ### 1. greedy association: for each detection, pick the free track with max IoU
    # track_ids is a set of tracks that still need a match in the new frame
    {matches, free_track_ids} =
      Enum.reduce(dets, {[], track_ids}, fn {det, det_idx}, {acc_m, track_ids} ->
        {best_track_id, best_iou} =
          track_ids
          |> Enum.map(fn track_id -> {track_id, iou(current_tracks[track_id].bbox, det)} end)
          |> Enum.max_by(&elem(&1, 1), fn -> {nil, -1.0} end)

        if not is_nil(best_track_id) and best_iou >= @iou_tresh do
          { [{best_track_id, det_idx, det} | acc_m], MapSet.delete(track_ids, best_track_id) }
        else
          {acc_m, track_ids}
        end
      end)

    matched_det_idxs =
      matches
      |> Enum.map(fn {_id, det_idx, _det} -> det_idx end)
      |> MapSet.new()

    ### 2. Update matched tracks
    {updated_tracks, enter_events} =
      Enum.reduce(matches, {current_tracks, []}, fn {track_id, _det_idx, det}, {acc, enter_events} ->
        matched_track = current_tracks[track_id]
        updated_hits = matched_track.hits + 1
        updated_track = %Track{matched_track | bbox: get_bbox(det), hits: updated_hits, misses: 0, last_seen: now_ms}

        enter_events =
          if matched_track.hits == @min_hits do
            [%{type: :enter, track: updated_track} | enter_events]
          else
            enter_events
          end

        {Map.put(acc, track_id, updated_track), enter_events}
      end)


    ### 3. Create new tracks
    new_dets =
      dets
      # discaring the dets that matched tracks
      |> Enum.reject(fn {_det, det_id} -> MapSet.member?(matched_det_idxs, det_id) end)
      |> Enum.map(fn {det, _det_id} -> det end)


    {updated_tracks, next_id} =
      Enum.reduce(new_dets, {updated_tracks, state.next_id}, fn det, {tracks, next_id} ->
        new_track = %Track{
          id: next_id,
          bbox: get_bbox(det),
          hits: 1,
          misses: 0,
          last_seen: now_ms,
          born_at: now_ms
        }

        {Map.put(tracks, next_id, new_track), next_id + 1}
      end)

    ### 4. Age and close unmatched tracks

    # updated_tracks is a mix of matched and unmatched tracks
    # we need to remove old tracks
    {updated_tracks, exit_events} =
      Enum.reduce(free_track_ids, {updated_tracks, []}, fn track_id, {tracks, exit_events} ->
        unmatched_track = tracks[track_id]
        unmatched_track = %{unmatched_track | misses: unmatched_track.misses + 1}
        if unmatched_track.misses > @max_age do
          {Map.delete(tracks, track_id), [%{type: :exit, track: %{unmatched_track | exit_at: now_ms}} | exit_events]}
        else
          {Map.put(tracks, track_id, unmatched_track), exit_events}
        end
      end)

    ### updated state and events
    updated_state = %{state | tracks: updated_tracks, next_id: next_id}
    events = %{enter: enter_events, exit: exit_events}

    {updated_state, events}
  end

  @spec iou(bbox_a :: bbox(), bbox_b :: bbox()) :: float()
  def iou(bbox_a, bbox_b) do
    %{xmin: x1_a, xmax: x2_a, ymin: y1_a, ymax: y2_a} = bbox_a
    %{xmin: x1_b, xmax: x2_b, ymin: y1_b, ymax: y2_b} = bbox_b

    x1 = max(x1_a, x1_b)
    y1 = max(y1_a, y1_b)
    x2 = min(x2_a, x2_b)
    y2 = min(y2_a, y2_b)

    # A ∩ B
    int_w = max(x2 - x1, 0)
    int_h = max(y2 - y1, 0)
    intersection = int_w * int_h


    # A U B
    aw = x2_a - x1_a
    ah = y2_a - y1_a
    bw = x2_b - x1_b
    bh = y2_b - y1_b
    union = aw * ah + bw * bh - intersection

    if union > 0, do: intersection / union, else: 0.0
  end


  defp get_bbox(det) do
    Map.take(det, [:xmin, :xmax, :ymin, :ymax])
  end

  def now_ms do
    DateTime.utc_now(:millisecond) |> DateTime.to_unix(:millisecond)
  end
end
