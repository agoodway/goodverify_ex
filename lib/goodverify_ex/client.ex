defmodule GoodverifyEx.Client do
  @moduledoc """
  HTTP client for the GoodVerify API.

  Configuration can be provided explicitly or via application config:

      config :goodverify_ex,
        base_url: "https://api.goodverify.com",
        api_key: "sk_..."
  """

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t() | nil,
          req_options: keyword()
        }

  defstruct [:base_url, :api_key, req_options: []]

  @doc "Create a new client with the given options."
  def new(opts \\ []) do
    %__MODULE__{
      base_url:
        Keyword.get(opts, :base_url) ||
          Application.get_env(:goodverify_ex, :base_url, "http://localhost:4000"),
      api_key:
        Keyword.get(opts, :api_key) ||
          Application.get_env(:goodverify_ex, :api_key),
      req_options: Keyword.get(opts, :req_options, [])
    }
  end

  @doc false
  def request(%__MODULE__{} = client, method, path, opts \\ []) do
    headers = build_headers(client)

    req_opts =
      [method: method, url: client.base_url <> path, headers: headers]
      |> Keyword.merge(opts)
      |> Keyword.merge(client.req_options)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp build_headers(%{api_key: nil}), do: []
  defp build_headers(%{api_key: key}), do: [{"authorization", "Bearer #{key}"}]
end
