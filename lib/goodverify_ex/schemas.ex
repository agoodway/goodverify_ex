defmodule GoodverifyEx.Schemas do
  @moduledoc """
  Generated schema structs from the GoodVerify OpenAPI specification.

  Each schema from `openapi.json` is compiled into an Elixir struct module
  with a `from_map/1` function that recursively converts JSON-decoded maps
  into typed structs, resolving `$ref`, `anyOf`, `allOf`, and array references.

  Recompiles automatically when `openapi.json` changes.
  """

  @spec_path Path.join([__DIR__, "..", "..", "openapi.json"])
  @external_resource @spec_path
  @openapi_spec File.read!(@spec_path) |> Jason.decode!()

  for {schema_name, schema_def} <- @openapi_spec["components"]["schemas"] do
    mod_name = Module.concat(__MODULE__, schema_name)
    props = schema_def["properties"] || %{}
    desc = schema_def["description"] || ""

    field_names = props |> Map.keys() |> Enum.sort() |> Enum.map(&String.to_atom/1)

    # Build a map of field_name => conversion rule for nested types
    conversions =
      for {prop_name, prop_def} <- props, into: %{} do
        conv =
          cond do
            match?(%{"$ref" => _}, prop_def) ->
              {:struct, prop_def["$ref"] |> String.split("/") |> List.last()}

            is_list(prop_def["anyOf"]) ->
              case Enum.find(prop_def["anyOf"], &match?(%{"$ref" => _}, &1)) do
                %{"$ref" => ref} -> {:struct, ref |> String.split("/") |> List.last()}
                _ -> :passthrough
              end

            is_list(prop_def["allOf"]) ->
              case Enum.find(prop_def["allOf"], &match?(%{"$ref" => _}, &1)) do
                %{"$ref" => ref} -> {:struct, ref |> String.split("/") |> List.last()}
                _ -> :passthrough
              end

            prop_def["type"] == "array" && is_map(prop_def["items"]) &&
                Map.has_key?(prop_def["items"], "$ref") ->
              {:list, prop_def["items"]["$ref"] |> String.split("/") |> List.last()}

            true ->
              :passthrough
          end

        {String.to_atom(prop_name), conv}
      end

    escaped_conversions = Macro.escape(conversions)

    Module.create(
      mod_name,
      quote do
        @moduledoc unquote(desc)

        defstruct unquote(field_names)

        @field_set MapSet.new(unquote(field_names))
        @conversions unquote(escaped_conversions)

        @doc "Convert a JSON-decoded map into a `#{inspect(__MODULE__)}` struct."
        def from_map(nil), do: nil

        def from_map(map) when is_map(map) do
          fields =
            for {key, value} <- map,
                atom_key = to_field_atom(key),
                atom_key in @field_set,
                into: %{} do
              {atom_key, convert_field(atom_key, value)}
            end

          struct(__MODULE__, fields)
        end

        defp to_field_atom(key) when is_atom(key), do: key
        defp to_field_atom(key) when is_binary(key), do: String.to_atom(key)

        defp convert_field(_key, nil), do: nil

        defp convert_field(key, value) do
          case Map.get(@conversions, key) do
            {:struct, ref_name} when is_map(value) ->
              Module.concat(GoodverifyEx.Schemas, ref_name).from_map(value)

            {:list, ref_name} when is_list(value) ->
              mod = Module.concat(GoodverifyEx.Schemas, ref_name)
              Enum.map(value, &mod.from_map/1)

            _ ->
              value
          end
        end
      end,
      __ENV__
    )
  end
end
