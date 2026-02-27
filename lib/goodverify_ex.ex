defmodule GoodverifyEx do
  @moduledoc """
  Elixir client for the GoodVerify API, generated from the OpenAPI specification.

  ## Configuration

      config :goodverify_ex,
        base_url: "https://api.goodverify.com",
        api_key: "sk_..."

  ## Usage

      client = GoodverifyEx.client(api_key: "sk_test_...")

      {:ok, %GoodverifyEx.Schemas.EmailVerifyResponse{}} =
        GoodverifyEx.verify_email(client, %{email: "user@example.com"})

      {:ok, %GoodverifyEx.Schemas.PhoneVerifyResponse{}} =
        GoodverifyEx.verify_phone(client, %{phone_number: "+12025551234"})

      {:ok, %GoodverifyEx.Schemas.AddressVerifyResponse{}} =
        GoodverifyEx.verify_address(client, %{address: "123 Main St, Springfield, IL 62704"})
  """

  @spec_path Path.join([__DIR__, "..", "openapi.json"])
  @external_resource @spec_path
  @openapi_spec File.read!(@spec_path) |> Jason.decode!()

  alias GoodverifyEx.Client

  @doc "Create a new API client."
  def client(opts \\ []), do: Client.new(opts)

  # Generate API functions from OpenAPI paths
  for {path, methods} <- @openapi_spec["paths"],
      {method, operation} <- methods do
    func_name =
      path
      |> String.replace_prefix("/api/v1/", "")
      |> String.replace("/", "_")
      |> String.to_atom()

    http_method = String.to_atom(method)
    summary = operation["summary"] || ""
    description = operation["description"] || ""

    response_ref =
      get_in(operation, ["responses", "200", "content", "application/json", "schema", "$ref"])

    response_module =
      if response_ref do
        ref_name = response_ref |> String.split("/") |> List.last()
        Module.concat(GoodverifyEx.Schemas, ref_name)
      end

    has_body = operation["requestBody"] != nil

    if has_body do
      @doc "#{summary}\n\n#{description}"
      def unquote(func_name)(%Client{} = client, params) when is_map(params) do
        case Client.request(client, unquote(http_method), unquote(path), json: params) do
          {:ok, body} when is_map(body) ->
            {:ok, unquote(response_module).from_map(body)}

          error ->
            error
        end
      end
    else
      @doc "#{summary}\n\n#{description}"
      def unquote(func_name)(%Client{} = client) do
        case Client.request(client, unquote(http_method), unquote(path)) do
          {:ok, body} when is_map(body) ->
            {:ok, unquote(response_module).from_map(body)}

          error ->
            error
        end
      end
    end
  end
end
