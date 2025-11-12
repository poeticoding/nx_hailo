defmodule NxHailo.MJPEGStream do
  @moduledoc false
  use GenServer
  @soi <<0xFF, 0xD8>>
  @eoi <<0xFF, 0xD9>>

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def subscribe(pid \\ self()), do: GenServer.cast(__MODULE__, {:sub, pid})

  @cmd "/usr/bin/rpicam-vid"
  @args ["-t","0","-n", "--width","640","--height","360","--framerate","25","--codec","mjpeg","-o","-"]

  def get_frame(pid_or_name \\ __MODULE__) do
    GenServer.call(pid_or_name, :get_frame)
  end

  def init(_opts) do
    port = Port.open({:spawn_executable, @cmd}, [:binary, args: @args])
    # Process.flag(:trap_exit, true)
    {:ok, %{port: port, buf: <<>>, last: nil}}
  end

  def handle_call(:get_frame, _from, state) do
    {:reply, state.last, state}
  end

  def handle_info({port, {:data, bin}}, %{port: port} = state) do
    buf = state.buf <> bin
    {frames, rest} = extract(buf, [])
    broadcast_frames(frames)
    # bound buffer: if it grows too large, keep only from the last SOI
    rest = if byte_size(rest) > 2_000_000, do: drop_to_last_soi(rest), else: rest
    {:noreply, %{state | buf: rest, last: List.first(frames)}}
  end

  # def handle_info({:EXIT, _port, _status}, s), do: {:stop, :normal, s}

  defp extract(bin, frames) do
    case :binary.match(bin, @soi) do
      :nomatch -> {frames, bin}
      {soi, 2} ->
        after_soi = binary_part(bin, soi, byte_size(bin) - soi)
        case :binary.match(after_soi, @eoi) do
          :nomatch -> {frames, binary_part(bin, soi, byte_size(bin) - soi)}
          {eoi_rel, 2} ->
            eoi = soi + eoi_rel + 2
            frame = binary_part(bin, soi, eoi - soi)
            extract(binary_part(bin, eoi, byte_size(bin) - eoi), [frame | frames])
        end
    end
  end

  defp drop_to_last_soi(bin) do
    case :binary.matches(bin, @soi) do
      [] -> <<>>
      matches ->
        {last, _} = List.last(matches)
        binary_part(bin, last, byte_size(bin) - last)
    end
  end

  def broadcast_frames(frames) do
    last_frame = List.first(frames)
    if last_frame do
      Phoenix.PubSub.broadcast(NxHailo.PubSub, "camera:frame", {:frame, last_frame})
    end
  end
end
