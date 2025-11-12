defmodule NxHailo.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # cmd "epmd -daemon"
    # Node.start(:"nerves@#{Toolshed.hostname()}.local")
    # Node.set_cookie(:mycookie)

    children = [
      {Phoenix.PubSub, name: NxHailo.PubSub},
      # NxHailo.MJPEGStream
    ]


    opts = [strategy: :one_for_one, name: NxHailo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
