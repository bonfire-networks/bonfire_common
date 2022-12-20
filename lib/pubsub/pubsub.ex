defmodule Bonfire.Common.PubSub do
  import Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Common.PubSub

  @doc """
  Subscribe to something for realtime updates, like a feed or thread
  """

  # def subscribe(topics, socket \\ nil)

  def subscribe(topics, socket) when is_list(topics) do
    Enum.each(topics, &subscribe(&1, socket))
  end

  def subscribe(topic, socket_etc) when is_binary(topic) do
    # debug(socket)
    if socket_connected_or_user?(socket_etc) do
      do_subscribe(topic)
    else
      debug(topic, "LiveView is not connected so we skip subscribing to")
    end
  end

  def subscribe(topic, socket) do
    with topic when is_binary(topic) and topic != "" <- Utils.maybe_to_string(topic) do
      debug(topic, "transformed the topic into a string we can subscribe to")
      subscribe(topic, socket)
    else
      _ ->
        warn(
          topic,
          "could not transform the topic into a string we can subscribe to"
        )
    end
  end

  defp do_subscribe(topic) when is_binary(topic) and topic != "" do
    debug(topic, "subscribed")

    endpoint = Config.get(:endpoint_module, Bonfire.Web.Endpoint)

    # endpoint.unsubscribe(maybe_to_string(topic)) # to avoid duplicate subscriptions?
    endpoint.subscribe(topic)

    # Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, topic)
  end

  @doc """
  Broadcast some data for realtime updates, for example to a feed or thread
  """
  def broadcast(topics, payload) when is_list(topics) do
    Enum.each(topics, &broadcast(&1, payload))
  end

  def broadcast(topic, {payload_type, _data} = payload) do
    debug(payload_type, inspect(topic))
    do_broadcast(topic, payload)
  end

  def broadcast(topic, data)
      when (is_atom(topic) or is_binary(topic)) and topic != "" and
             not is_nil(data) do
    debug(topic)
    do_broadcast(topic, data)
  end

  def broadcast(_, _), do: warn("pubsub did not broadcast")

  defp do_broadcast(topic, data) do
    # endpoint = Config.get(:endpoint_module, Bonfire.Web.Endpoint)
    # endpoint.broadcast_from(self(), topic, step, state)
    Phoenix.PubSub.broadcast(Bonfire.Common.PubSub, Utils.maybe_to_string(topic), data)
  end

  @doc "Broadcast while attaching telemetry info. The receiving module must `use Bonfire.Common.PubSub` to correctly unwrap the Event"
  defmacro broadcast_with_telemetry(topic, message) do
    quote do
      current_function = Bonfire.Common.PubSub.current_function(__ENV__)

      Bonfire.Common.PubSub.broadcast_with_telemetry(
        unquote(topic),
        unquote(message),
        current_function
      )
    end
  end

  defmodule Event do
    defstruct [:message, :otel_ctx]
  end

  def broadcast_with_telemetry(topic, message, source) do
    require OpenTelemetry.Tracer

    opts = %{attributes: %{broadcaster: source}}

    OpenTelemetry.Tracer.with_span "bonfire.pubsub:broadcast", opts do
      event = %Event{message: message, otel_ctx: OpenTelemetry.Tracer.current_span_ctx()}
      Bonfire.Common.PubSub.broadcast(topic, event)
    end
  end

  defmacro __using__(_opts) do
    quote do
      def handle_info(%Bonfire.Common.PubSub.Event{} = event, socket) do
        require OpenTelemetry.Tracer

        OpenTelemetry.Tracer.set_current_span(event.otel_ctx)
        opts = %{attributes: %{handler: inspect(__ENV__.module)}}

        OpenTelemetry.Tracer.with_span "acme:handle_event", opts do
          handle_info(event.message, socket)
        end
      end
    end
  end

  def current_function(env) do
    {fun, arity} = env.function
    "#{inspect(env.module)}.#{fun}/#{arity}"
  end

  defp socket_connected_or_user?(%Phoenix.LiveView.Socket{} = socket),
    do: Utils.socket_connected?(socket)

  defp socket_connected_or_user?(other),
    do: if(Utils.current_user(other), do: true, else: false)
end
